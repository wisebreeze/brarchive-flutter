import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../i18n/i18n.dart';
import 'brarchive_codec.dart';

/// Configuration for the brarchive converter, mirroring brarchive-go's config.toml.
class ConverterConfig {
  final List<String> includeExts;
  final List<String> excludeDirs;
  final List<String> specialFolders;
  final List<String> excludeFiles;
  final String outputDir;

  const ConverterConfig({
    this.includeExts = const ['.json', '.json5', '.ui'],
    this.excludeDirs = const ['textures', 'materials', 'texts', 'sounds'],
    this.specialFolders = const ['subpacks'],
    this.excludeFiles = const ['ui/_global_variables.json'],
    this.outputDir = '__brarchive',
  });

  bool isTargetExtension(String ext) {
    final lower = ext.toLowerCase();
    return includeExts.any((e) => e.toLowerCase() == lower);
  }

  bool isExcludedFolder(String name) {
    return excludeDirs.any((d) => d.toLowerCase() == name.toLowerCase());
  }

  bool isSpecialFolder(String name) {
    return specialFolders.any((s) => s.toLowerCase() == name.toLowerCase());
  }

  bool isExcludedFile(String path) {
    final normalized = path.replaceAll('\\', '/');
    final base = p.basename(normalized);
    return excludeFiles.any((f) {
      final fn = f.toLowerCase();
      return normalized.toLowerCase() == fn || base.toLowerCase() == fn;
    });
  }
}

/// Result of a pack/unpack operation.
class ConvertResult {
  final bool success;
  final String? outputPath;
  final String? error;
  final Duration duration;

  const ConvertResult({
    required this.success,
    this.outputPath,
    this.error,
    required this.duration,
  });
}

/// Converts between zip/mcpack archives and the brarchive format.
///
/// The logic mirrors brarchive-go:
///
/// **Pack**: extract archive → walk directories → for each directory
/// containing target files (.json/.json5/.ui), serialize them into a
/// `.brarchive` file placed inside `__brarchive/` at the archive root
/// (or at the subpack root for directories inside `subpacks/`). The
/// brarchive file name equals the source directory name, and the path
/// inside `__brarchive/` mirrors the source directory's parent path.
/// Original target files are removed, then the tree is re-zipped.
///
/// **Unpack**: extract archive → find all `__brarchive/` folders →
/// for each `.brarchive` file, deserialize and restore files to the
/// directory implied by the path relative to `__brarchive/`. Remove
/// `__brarchive/` folders, then re-zip.
class BrarchiveConverter {
  BrarchiveConverter({
    this.config = const ConverterConfig(),
    required this.log,
    required this.i18n,
  });

  final ConverterConfig config;
  final void Function(String) log;
  final I18n i18n;

  // ------------------------------------------------------------------
  // Pack
  // ------------------------------------------------------------------

  Future<ConvertResult> pack({
    required String inputPath,
    required String outputDir,
  }) async {
    final sw = Stopwatch()..start();
    try {
      log(i18n.t('logExtracting'));
      final archive = await _readArchive(inputPath);
      final files = _archiveToMap(archive);

      log(i18n.t('logScanning'));

      // Group target files by their parent directory.
      // Key = directory path (relative, /-separated), Value = {filename: content}
      final byDir = <String, Map<String, Uint8List>>{};
      final allKeys = files.keys.toList()..sort();
      for (final path in allKeys) {
        if (config.isExcludedFile(path)) continue;
        if (_isInsideExcludedDir(path)) continue;
        final ext = p.extension(path).toLowerCase();
        if (!config.isTargetExtension(ext)) continue;

        final dir = p.dirname(path);
        final name = p.basename(path);
        byDir.putIfAbsent(dir, () => {})[name] = files[path]!;
      }

      if (byDir.isEmpty) {
        log(i18n.t('logNoBrarchiveFound'));
        final outPath = _uniqueOutputPath(inputPath, outputDir, suffix: '_packed');
        await File(outPath).writeAsBytes(_encodeZip(archive));
        sw.stop();
        return ConvertResult(
          success: true,
          outputPath: outPath,
          duration: sw.elapsed,
        );
      }

      log(i18n.t('logFoundTargets', {
        'count': '${byDir.values.fold(0, (s, m) => s + m.length)}',
        'dir': '${byDir.length} directories',
      }));
      log(i18n.t('logCreatingBrarchive'));

      // Build new file map: copy all files, then remove target files and
      // add __brarchive/*.brarchive entries.
      final newFiles = Map<String, Uint8List>.from(files);

      // Remove original target files
      for (final dirEntry in byDir.entries) {
        for (final fileName in dirEntry.value.keys) {
          final fullPath = dirEntry.key.isEmpty ? fileName : '${dirEntry.key}/$fileName';
          newFiles.remove(fullPath);
        }
      }

      // Create brarchive files
      for (final dirEntry in byDir.entries) {
        final dir = dirEntry.key;
        final entries = dirEntry.value;

        final dirName = dir.isEmpty ? 'root' : p.basename(dir);
        final brarchiveName = '$dirName.brarchive';

        // Determine where __brarchive goes:
        // - If dir is inside a special folder (subpacks), __brarchive goes
        //   at the subpack root.
        // - Otherwise, __brarchive goes at the archive root.
        final brarchiveBase = _getBrarchiveBase(dir);

        // The path inside __brarchive/ mirrors the source dir's parent
        // relative to the brarchive base.
        final relParent = _relativeParent(brarchiveBase, dir);
        final brarchivePath = relParent.isEmpty
            ? '$brarchiveBase/${config.outputDir}/$brarchiveName'
            : '$brarchiveBase/${config.outputDir}/$relParent/$brarchiveName';

        log(i18n.t('logSerializing', {
          'count': '${entries.length}',
          'output': brarchivePath,
        }));
        newFiles[brarchivePath] = BrarchiveCodec.serialize(entries);
      }

      // Clean up empty directories (remove directory entries that are now empty)
      _removeEmptyDirEntries(newFiles);

      log(i18n.t('logZipping'));
      final outArchive = _buildArchive(newFiles);
      final outPath = _uniqueOutputPath(inputPath, outputDir, suffix: '_packed');
      await File(outPath).writeAsBytes(_encodeZip(outArchive));

      sw.stop();
      return ConvertResult(
        success: true,
        outputPath: outPath,
        duration: sw.elapsed,
      );
    } catch (e, st) {
      sw.stop();
      log(i18n.t('logError', {'error': e.toString()}));
      stderr.writeln(st);
      return ConvertResult(
        success: false,
        error: e.toString(),
        duration: sw.elapsed,
      );
    }
  }

  // ------------------------------------------------------------------
  // Unpack
  // ------------------------------------------------------------------

  Future<ConvertResult> unpack({
    required String inputPath,
    required String outputDir,
  }) async {
    final sw = Stopwatch()..start();
    try {
      log(i18n.t('logExtracting'));
      final archive = await _readArchive(inputPath);
      final files = _archiveToMap(archive);

      // Find all __brarchive folders and the .brarchive files within them.
      // Key = full path of .brarchive file, Value = its content
      final brarchiveFiles = <String, Uint8List>{};
      // Track which __brarchive folder each file belongs to
      final brarchiveFolderMap = <String, String>{}; // file path -> __brarchive dir path

      final allKeys = files.keys.toList()..sort();
      for (final path in allKeys) {
        final parts = _splitPath(path);
        final brarchiveIdx = parts.indexWhere(
          (e) => e.toLowerCase() == config.outputDir.toLowerCase(),
        );
        if (brarchiveIdx == -1) continue;
        final ext = p.extension(path).toLowerCase();
        if (ext != '.brarchive') continue;

        final brarchiveDir = parts.sublist(0, brarchiveIdx + 1).join('/');
        brarchiveFiles[path] = files[path]!;
        brarchiveFolderMap[path] = brarchiveDir;
      }

      if (brarchiveFiles.isEmpty) {
        log(i18n.t('logNoBrarchiveFound'));
        final outPath = _uniqueOutputPath(inputPath, outputDir, suffix: '_unpacked');
        await File(outPath).writeAsBytes(_encodeZip(archive));
        sw.stop();
        return ConvertResult(
          success: true,
          outputPath: outPath,
          duration: sw.elapsed,
        );
      }

      log(i18n.t('logFoundBrarchiveFiles', {
        'count': '${brarchiveFiles.length}',
      }));

      // Build new file map
      final newFiles = Map<String, Uint8List>.from(files);

      // Deserialize each brarchive file and restore contents
      for (final entry in brarchiveFiles.entries) {
        final brarchivePath = entry.key;
        final brarchiveDir = brarchiveFolderMap[brarchivePath]!;

        log(i18n.t('logRestoringFiles', {'file': p.basename(brarchivePath)}));

        final restored = BrarchiveCodec.deserialize(entry.value);

        // The parent of __brarchive is where files should be restored
        final parentOfBrarchive = p.dirname(brarchiveDir);

        // The relative path of the .brarchive file inside __brarchive/
        // determines the target subdirectory.
        // E.g., __brarchive/ui.brarchive → restore to parent/ui/
        // E.g., __brarchive/ui/sub.brarchive → restore to parent/ui/sub/
        final relInBrarchive = p.relative(brarchivePath, from: brarchiveDir);
        final targetRelDir = p.withoutExtension(relInBrarchive);

        final targetDir = targetRelDir == '.'
            ? parentOfBrarchive
            : '$parentOfBrarchive/$targetRelDir';

        for (final r in restored.entries) {
          final restorePath = targetDir.isEmpty ? r.key : '$targetDir/${r.key}';
          log(i18n.t('logWritingFile', {
            'file': restorePath,
            'size': '${r.value.length}',
          }));
          newFiles[restorePath] = r.value;
        }
        log(i18n.t('logRestoredFiles', {'count': '${restored.length}'}));
      }

      // Remove all __brarchive folder entries and files
      newFiles.removeWhere((path, _) {
        final parts = _splitPath(path);
        return parts.any((e) => e.toLowerCase() == config.outputDir.toLowerCase());
      });

      log(i18n.t('logZipping'));
      final outArchive = _buildArchive(newFiles);
      final outPath = _uniqueOutputPath(inputPath, outputDir, suffix: '_unpacked');
      await File(outPath).writeAsBytes(_encodeZip(outArchive));

      sw.stop();
      return ConvertResult(
        success: true,
        outputPath: outPath,
        duration: sw.elapsed,
      );
    } catch (e, st) {
      sw.stop();
      log(i18n.t('logError', {'error': e.toString()}));
      stderr.writeln(st);
      return ConvertResult(
        success: false,
        error: e.toString(),
        duration: sw.elapsed,
      );
    }
  }

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  /// Determines the base directory for the __brarchive folder.
  ///
  /// If [dir] is inside a special folder (e.g. subpacks), the base is
  /// the subpack root. Otherwise, the base is the archive root ('').
  String _getBrarchiveBase(String dir) {
    if (dir.isEmpty) return '';
    final parts = _splitPath(dir);
    for (final special in config.specialFolders) {
      final idx = parts.indexWhere((e) => e.toLowerCase() == special.toLowerCase());
      if (idx != -1 && idx + 1 < parts.length) {
        // Inside a special folder; base is the subpack root
        // (special folder + first child, e.g. "subpacks/light")
        return parts.sublist(0, idx + 2).join('/');
      }
    }
    return '';
  }

  /// Computes the parent path of [dir] relative to [base].
  /// E.g., base="subpacks/light", dir="subpacks/light/ui" → "ui"
  /// E.g., base="", dir="ui/sub" → "ui"
  String _relativeParent(String base, String dir) {
    if (dir.isEmpty) return '';
    if (base.isEmpty) {
      // dir relative to root
      final parent = p.dirname(dir);
      return parent == '.' ? '' : parent;
    }
    // dir relative to base
    final rel = p.relative(dir, from: base);
    final parent = p.dirname(rel);
    return parent == '.' ? '' : parent;
  }

  /// Removes entries that represent empty directories (zip entries ending
  /// with '/' whose contents have all been removed).
  void _removeEmptyDirEntries(Map<String, Uint8List> files) {
    final dirEntries = files.keys.where((k) => k.endsWith('/')).toList();
    for (final dirEntry in dirEntries) {
      final prefix = dirEntry;
      final hasFiles = files.keys.any(
        (k) => !k.endsWith('/') && k.startsWith(prefix),
      );
      if (!hasFiles) {
        files.remove(dirEntry);
      }
    }
  }

  Future<Archive> _readArchive(String path) async {
    final bytes = await File(path).readAsBytes();
    final ext = p.extension(path).toLowerCase();
    if (ext == '.zip' || ext == '.mcpack') {
      return ZipDecoder().decodeBytes(bytes);
    }
    throw UnsupportedError('unsupported archive format: $ext');
  }

  Uint8List _encodeZip(Archive archive) {
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  Map<String, Uint8List> _archiveToMap(Archive archive) {
    final result = <String, Uint8List>{};
    for (final file in archive) {
      if (file.isFile) {
        final name = file.name.replaceAll('\\', '/');
        result[name] = Uint8List.fromList(file.content as List<int>);
      }
    }
    return result;
  }

  Archive _buildArchive(Map<String, Uint8List> files) {
    final archive = Archive();
    final sortedKeys = files.keys.toList()..sort();
    for (final name in sortedKeys) {
      archive.addFile(ArchiveFile(name, files[name]!.length, files[name]!));
    }
    return archive;
  }

  List<String> _splitPath(String path) {
    return path.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).toList();
  }

  bool _isInsideExcludedDir(String path) {
    final parts = _splitPath(path);
    for (final part in parts) {
      if (config.isExcludedFolder(part)) return true;
    }
    return false;
  }

  String _uniqueOutputPath(
    String inputPath,
    String outputDir, {
    required String suffix,
  }) {
    final base = p.basenameWithoutExtension(inputPath);
    final ext = p.extension(inputPath).toLowerCase() == '.mcpack'
        ? '.mcpack'
        : '.zip';
    var candidate = p.join(outputDir, '$base$suffix$ext');
    var i = 1;
    while (File(candidate).existsSync()) {
      candidate = p.join(outputDir, '$base$suffix ($i)$ext');
      i++;
    }
    return candidate;
  }
}
