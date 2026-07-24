import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../i18n/i18n.dart';
import 'brarchive_codec.dart';

/// Configuration for the brarchive converter, mirroring brarchive-go's config.toml.
class ConverterConfig {
  /// File extensions that should be packed into brarchive.
  final List<String> includeExts;

  /// Directory names to exclude when scanning for target files.
  final List<String> excludeDirs;

  /// Special folders whose subdirectories are processed recursively.
  final List<String> specialFolders;

  /// Files to exclude by relative path or name.
  final List<String> excludeFiles;

  /// Output folder name inside the archive (the __brarchive folder).
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
/// Pack:   zip/mcpack -> extract -> find target files (.json/.json5/.ui)
///         -> serialize into __brarchive/*.brarchive -> re-zip
/// Unpack: zip/mcpack -> extract -> find __brarchive/*.brarchive
///         -> deserialize -> restore original files -> re-zip
class BrarchiveConverter {
  BrarchiveConverter({
    this.config = const ConverterConfig(),
    required this.log,
    required this.i18n,
  });

  final ConverterConfig config;
  final void Function(String) log;
  final I18n i18n;

  /// Pack: convert target files inside the archive into brarchive format.
  Future<ConvertResult> pack({
    required String inputPath,
    required String outputDir,
  }) async {
    final sw = Stopwatch()..start();
    try {
      log(i18n.t('logExtracting'));
      final archive = await _readArchive(inputPath);
      final files = _archiveToMap(archive);

      // Scan for target files
      log(i18n.t('logScanning'));
      final targetFiles = <String, Uint8List>{};
      final allKeys = files.keys.toList()..sort();
      for (final path in allKeys) {
        if (_isExcludedFile(path)) continue;
        if (_isInsideExcludedDir(path)) continue;
        final ext = p.extension(path).toLowerCase();
        if (config.isTargetExtension(ext)) {
          targetFiles[path] = files[path]!;
        }
      }

      if (targetFiles.isEmpty) {
        // No target files: just copy the archive as-is
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

      // Group target files by their parent directory
      final byDir = <String, Map<String, Uint8List>>{};
      for (final entry in targetFiles.entries) {
        final dir = p.dirname(entry.key);
        final name = p.basename(entry.key);
        byDir.putIfAbsent(dir, () => {})[name] = entry.value;
      }

      log(i18n.t('logFoundTargets', {
        'count': '${targetFiles.length}',
        'dir': '${byDir.length} directories',
      }));
      log(i18n.t('logCreatingBrarchive'));

      // Build new file map: remove target files, add __brarchive/*.brarchive
      final newFiles = Map<String, Uint8List>.from(files);
      for (final entry in targetFiles.entries) {
        newFiles.remove(entry.key);
      }
      for (final entry in byDir.entries) {
        final dir = entry.key;
        final brarchiveName = '${p.basename(dir.isEmpty ? "root" : dir)}.brarchive';
        final brarchivePath = dir.isEmpty
            ? '${config.outputDir}/$brarchiveName'
            : '$dir/${config.outputDir}/$brarchiveName';
        log(i18n.t('logSerializing', {
          'count': '${entry.value.length}',
          'output': brarchivePath,
        }));
        newFiles[brarchivePath] = BrarchiveCodec.serialize(entry.value);
      }

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

  /// Unpack: restore original files from __brarchive/*.brarchive inside the archive.
  Future<ConvertResult> unpack({
    required String inputPath,
    required String outputDir,
  }) async {
    final sw = Stopwatch()..start();
    try {
      log(i18n.t('logExtracting'));
      final archive = await _readArchive(inputPath);
      final files = _archiveToMap(archive);

      // Find all __brarchive/*.brarchive files
      final brarchiveFiles = <String, Uint8List>{};
      final allKeys = files.keys.toList()..sort();
      for (final path in allKeys) {
        final parts = _splitPath(path);
        final brarchiveIdx = parts.indexWhere(
          (e) => e.toLowerCase() == config.outputDir.toLowerCase(),
        );
        if (brarchiveIdx == -1) continue;
        if (brarchiveIdx != parts.length - 2) continue; // must be parent of file
        final ext = p.extension(path).toLowerCase();
        if (ext == '.brarchive') {
          brarchiveFiles[path] = files[path]!;
        }
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

      // Deserialize each brarchive file and restore contents
      final newFiles = Map<String, Uint8List>.from(files);
      for (final entry in brarchiveFiles.entries) {
        final brarchivePath = entry.key;
        final dir = p.dirname(brarchivePath); // strip the __brarchive component
        final parentDir = p.dirname(dir);

        log(i18n.t('logRestoringFiles', {'file': p.basename(brarchivePath)}));
        final restored = BrarchiveCodec.deserialize(entry.value);
        for (final r in restored.entries) {
          final restorePath = parentDir.isEmpty ? r.key : '$parentDir/${r.key}';
          log(i18n.t('logWritingFile', {
            'file': restorePath,
            'size': '${r.value.length}',
          }));
          newFiles[restorePath] = r.value;
        }
        log(i18n.t('logRestoredFiles', {'count': '${restored.length}'}));

        // Remove the __brarchive folder entries
        newFiles.remove(brarchivePath);
      }

      // Remove any remaining __brarchive directory entries
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

  // ---- Helpers ----

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

  bool _isExcludedFile(String path) {
    return config.isExcludedFile(path);
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
