import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
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

  /// Whether to also pack image files (.png, .jpg, .jpeg, .tga) into brarchive.
  final bool packImages;

  /// Whether to delete original files after packing them into brarchive.
  final bool removeProcessedFiles;

  /// Whether to skip restoring empty (0-byte) entries from brarchive during
  /// unpack, so they don't overwrite existing non-empty files.
  final bool skipEmptyEntries;

  /// Whether to only pack UTF-8 encoded files. When enabled, files that
  /// are not valid UTF-8 (e.g. binary files with text extensions) are
  /// skipped during packing. Does not apply to image files when packImages
  /// is enabled.
  final bool utf8Only;

  const ConverterConfig({
    this.includeExts = const ['.json', '.json5', '.ui'],
    this.excludeDirs = const ['textures', 'materials', 'texts', 'sounds'],
    this.specialFolders = const ['subpacks'],
    this.excludeFiles = const ['ui/_global_variables.json'],
    this.outputDir = '__brarchive',
    this.packImages = false,
    this.removeProcessedFiles = true,
    this.skipEmptyEntries = true,
    this.utf8Only = true,
  });

  bool isTargetExtension(String ext) {
    final lower = ext.toLowerCase();
    if (includeExts.any((e) => e.toLowerCase() == lower)) return true;
    if (packImages) {
      const imageExts = ['.png', '.jpg', '.jpeg', '.tga'];
      return imageExts.contains(lower);
    }
    return false;
  }

  /// Returns the effective list of excluded folder names.
  /// When packImages is enabled, 'textures' is removed from the exclusion
  /// list so image files inside it can be packed.
  List<String> get effectiveExcludeDirs {
    if (!packImages) return excludeDirs;
    return excludeDirs.where((d) => d.toLowerCase() != 'textures').toList();
  }

  bool isExcludedFolder(String name) {
    final dirs = effectiveExcludeDirs;
    return dirs.any((d) => d.toLowerCase() == name.toLowerCase());
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

      // Run heavy work in a background isolate to avoid blocking the UI.
      final result = await compute(_packIsolateEntry, _PackParams(
        inputPath: inputPath,
        outputDir: outputDir,
        config: config,
      ));

      for (final entry in result.logs) {
        log(entry);
      }

      sw.stop();
      return ConvertResult(
        success: true,
        outputPath: result.outputPath,
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

      final result = await compute(_unpackIsolateEntry, _UnpackParams(
        inputPath: inputPath,
        outputDir: outputDir,
        config: config,
      ));

      for (final entry in result.logs) {
        log(entry);
      }

      sw.stop();
      return ConvertResult(
        success: true,
        outputPath: result.outputPath,
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
}

// --------------------------------------------------------------------
// Background isolate entry points (top-level functions)
// --------------------------------------------------------------------

class _PackParams {
  final String inputPath;
  final String outputDir;
  final ConverterConfig config;
  const _PackParams({
    required this.inputPath,
    required this.outputDir,
    required this.config,
  });
}

class _UnpackParams {
  final String inputPath;
  final String outputDir;
  final ConverterConfig config;
  const _UnpackParams({
    required this.inputPath,
    required this.outputDir,
    required this.config,
  });
}

class _IsolateResult {
  final String outputPath;
  final List<String> logs;
  const _IsolateResult({required this.outputPath, required this.logs});
}

/// Actual pack implementation that runs in a background isolate.
Future<_IsolateResult> _packIsolateImpl(_PackParams params) async {
  final logs = <String>[];
  final config = params.config;

  logs.add('Extracting archive...');
  final bytes = await File(params.inputPath).readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);
  final files = <String, Uint8List>{};
  for (final file in archive) {
    if (file.isFile) {
      final name = file.name.replaceAll('\\', '/');
      // file.content returns the decompressed data. It may be a List<int>
      // or an InputStream depending on the archive package version.
      // Always copy into a new Uint8List to avoid views into internal
      // buffers that get reused.
      final raw = file.content;
      if (raw is List<int>) {
        files[name] = Uint8List.fromList(raw);
      } else if (raw is Uint8List) {
        files[name] = Uint8List.fromList(raw);
      }
    }
  }

  logs.add('Scanning for target files (.json, .json5, .ui)...');

  // Group target files by their parent directory.
  // Key = directory path (relative, /-separated), Value = {filename: content}
  final byDir = <String, Map<String, Uint8List>>{};
  final allKeys = files.keys.toList()..sort();
  for (final path in allKeys) {
    if (config.isExcludedFile(path)) continue;
    if (_isInsideExcludedDir(path, config)) continue;
    final ext = p.extension(path).toLowerCase();
    if (!config.isTargetExtension(ext)) continue;

    final dir = p.dirname(path);
    // Skip root-level files (dir is '.' or empty)
    if (dir == '.' || dir.isEmpty) continue;

    final name = p.basename(path);
    final content = files[path]!;

    // If utf8Only is enabled and this is not an image file, check that
    // the content is valid UTF-8 before including it.
    if (config.utf8Only) {
      final isImage = const ['.png', '.jpg', '.jpeg', '.tga'].contains(ext);
      if (!isImage && !_isValidUtf8(content)) {
        logs.add('Skipping non-UTF-8 file: $path');
        continue;
      }
    }

    byDir.putIfAbsent(dir, () => {})[name] = content;
  }

  if (byDir.isEmpty) {
    logs.add('No target directories found, copying as-is');
    final outPath = _uniqueOutputPath(params.inputPath, params.outputDir, suffix: '_packed');
    await File(outPath).writeAsBytes(Uint8List.fromList(ZipEncoder().encode(archive)!));
    return _IsolateResult(outputPath: outPath, logs: logs);
  }

  final totalFiles = byDir.values.fold(0, (s, m) => s + m.length);
  logs.add('Found $totalFiles target file(s) in ${byDir.length} directories');
  logs.add('Creating __brarchive folder');

  // Build new file map: copy all files, then remove target files and
  // add __brarchive/*.brarchive entries.
  final newFiles = Map<String, Uint8List>.from(files);

  // Remove original target files (if removeProcessedFiles is enabled)
  if (config.removeProcessedFiles) {
    for (final dirEntry in byDir.entries) {
      for (final fileName in dirEntry.value.keys) {
        final fullPath = '${dirEntry.key}/$fileName';
        newFiles.remove(fullPath);
      }
    }
    logs.add('Removed original target files');
  } else {
    logs.add('Keeping original target files (removeProcessedFiles=false)');
  }

  // Create brarchive files
  for (final dirEntry in byDir.entries) {
    final dir = dirEntry.key;
    final entries = dirEntry.value;

    final dirName = p.basename(dir);
    final brarchiveName = '$dirName.brarchive';

    // Determine where __brarchive goes:
    // - If dir is inside a special folder (subpacks), __brarchive goes
    //   at the subpack root.
    // - Otherwise, __brarchive goes at the archive root.
    final brarchiveBase = _getBrarchiveBase(dir, config);

    // The path inside __brarchive/ mirrors the source dir's parent
    // relative to the brarchive base.
    final relParent = _relativeParent(brarchiveBase, dir);
    final brarchivePath = relParent.isEmpty
        ? '$brarchiveBase${config.outputDir}/$brarchiveName'
        : '$brarchiveBase${config.outputDir}/$relParent/$brarchiveName';

    logs.add('Serializing ${entries.length} file(s) into $brarchivePath');
    newFiles[brarchivePath] = BrarchiveCodec.serialize(entries);
  }

  // Clean up empty directories
  _removeEmptyDirEntries(newFiles);

  logs.add('Creating output archive...');
  final outArchive = Archive();
  final sortedKeys = newFiles.keys.toList()..sort();
  for (final name in sortedKeys) {
    final data = newFiles[name]!;
    final content = List<int>.from(data);
    outArchive.addFile(ArchiveFile(name, content.length, content));
  }
  final outPath = _uniqueOutputPath(params.inputPath, params.outputDir, suffix: '_packed');
  await File(outPath).writeAsBytes(Uint8List.fromList(ZipEncoder().encode(outArchive)!));

  logs.add('Output saved to: $outPath');
  return _IsolateResult(outputPath: outPath, logs: logs);
}

Future<_IsolateResult> _unpackIsolateImpl(_UnpackParams params) async {
  final logs = <String>[];
  final config = params.config;

  logs.add('Extracting archive...');
  final bytes = await File(params.inputPath).readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);
  final files = <String, Uint8List>{};
  for (final file in archive) {
    if (file.isFile) {
      final name = file.name.replaceAll('\\', '/');
      final raw = file.content;
      if (raw is List<int>) {
        files[name] = Uint8List.fromList(raw);
      } else if (raw is Uint8List) {
        files[name] = Uint8List.fromList(raw);
      }
    }
  }

  // Find all __brarchive folders and the .brarchive files within them.
  final brarchiveFiles = <String, Uint8List>{};
  final brarchiveFolderMap = <String, String>{};

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
    logs.add('No __brarchive folders found, copying as-is');
    final outPath = _uniqueOutputPath(params.inputPath, params.outputDir, suffix: '_unpacked');
    await File(outPath).writeAsBytes(Uint8List.fromList(ZipEncoder().encode(archive)!));
    return _IsolateResult(outputPath: outPath, logs: logs);
  }

  logs.add('Found ${brarchiveFiles.length} .brarchive file(s)');

  // Build new file map
  final newFiles = Map<String, Uint8List>.from(files);

  // Deserialize each brarchive file and restore contents
  for (final entry in brarchiveFiles.entries) {
    final brarchivePath = entry.key;
    final brarchiveDir = brarchiveFolderMap[brarchivePath]!;

    logs.add('Restoring files from ${p.basename(brarchivePath)}');

    final restored = BrarchiveCodec.deserialize(entry.value);

    // The parent of __brarchive is where files should be restored.
    // If __brarchive is at the archive root, parent is '' (root).
    final parentOfBrarchive = p.dirname(brarchiveDir);
    final parentIsRoot = parentOfBrarchive == '.' || parentOfBrarchive.isEmpty;

    // The relative path of the .brarchive file inside __brarchive/
    // determines the target subdirectory.
    final relInBrarchive = p.relative(brarchivePath, from: brarchiveDir);
    final targetRelDir = p.withoutExtension(relInBrarchive);
    final targetRelDirIsRoot = targetRelDir == '.' || targetRelDir.isEmpty;

    // Build the target directory without producing '.' or empty segments
    String targetDir;
    if (parentIsRoot && targetRelDirIsRoot) {
      targetDir = ''; // restore to archive root
    } else if (parentIsRoot) {
      targetDir = targetRelDir; // e.g. "ui"
    } else if (targetRelDirIsRoot) {
      targetDir = parentOfBrarchive; // e.g. "subpacks/light"
    } else {
      targetDir = '$parentOfBrarchive/$targetRelDir';
    }

    for (final r in restored.entries) {
      final restorePath = targetDir.isEmpty ? r.key : '$targetDir/${r.key}';

      // Skip empty (0-byte) entries if configured, so they don't overwrite
      // existing non-empty files (e.g. manifest stubs in brarchive).
      if (config.skipEmptyEntries && r.value.isEmpty) {
        logs.add('Skipping empty entry: $restorePath');
        continue;
      }

      logs.add('Writing $restorePath (${r.value.length} bytes)');
      newFiles[restorePath] = Uint8List.fromList(r.value);
    }
    logs.add('Restored ${restored.length} file(s)');
  }

  // Remove all __brarchive folder entries and files
  newFiles.removeWhere((path, _) {
    final parts = _splitPath(path);
    return parts.any((e) => e.toLowerCase() == config.outputDir.toLowerCase());
  });

  logs.add('Creating output archive...');
  final outArchive = Archive();
  final sortedKeys = newFiles.keys.toList()..sort();
  for (final name in sortedKeys) {
    final data = newFiles[name]!;
    // Deep-copy the content as a plain List<int> to ensure the archive
    // package can read it reliably. Uint8List views can become invalid
    // after isolate transfers or GC, causing 0-byte output.
    final content = List<int>.from(data);
    outArchive.addFile(ArchiveFile(name, content.length, content));
  }
  final outPath = _uniqueOutputPath(params.inputPath, params.outputDir, suffix: '_unpacked');
  await File(outPath).writeAsBytes(Uint8List.fromList(ZipEncoder().encode(outArchive)!));

  logs.add('Output saved to: $outPath');
  return _IsolateResult(outputPath: outPath, logs: logs);
}

// --------------------------------------------------------------------
// Top-level isolate entry points for compute()
// --------------------------------------------------------------------

Future<_IsolateResult> _packIsolateEntry(_PackParams params) async {
  return _packIsolateImpl(params);
}

Future<_IsolateResult> _unpackIsolateEntry(_UnpackParams params) async {
  return _unpackIsolateImpl(params);
}

// --------------------------------------------------------------------
// Helpers (top-level for isolate access)
// --------------------------------------------------------------------

/// Checks whether [data] is valid UTF-8 encoded text.
/// Returns false for binary data or text in other encodings (GBK, etc.).
bool _isValidUtf8(Uint8List data) {
  if (data.isEmpty) return true;
  try {
    utf8.decode(data, allowMalformed: false);
    return true;
  } catch (_) {
    return false;
  }
}

/// Determines the base directory for the __brarchive folder.
///
/// If [dir] is inside a special folder (e.g. subpacks), the base is
/// the subpack root. Otherwise, the base is the archive root ('').
String _getBrarchiveBase(String dir, ConverterConfig config) {
  if (dir.isEmpty) return '';
  final parts = _splitPath(dir);
  for (final special in config.specialFolders) {
    final idx = parts.indexWhere((e) => e.toLowerCase() == special.toLowerCase());
    if (idx != -1 && idx + 1 < parts.length) {
      // Inside a special folder; base is the subpack root
      // (special folder + first child, e.g. "subpacks/light")
      return '${parts.sublist(0, idx + 2).join('/')}/';
    }
  }
  return '';
}

/// Computes the parent path of [dir] relative to [base].
String _relativeParent(String base, String dir) {
  if (dir.isEmpty) return '';
  if (base.isEmpty) {
    // dir relative to root
    final parent = p.dirname(dir);
    return parent == '.' ? '' : parent;
  }
  // dir relative to base
  final rel = p.relative(dir, from: base.endsWith('/') ? base.substring(0, base.length - 1) : base);
  final parent = p.dirname(rel);
  return parent == '.' ? '' : parent;
}

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

bool _isInsideExcludedDir(String path, ConverterConfig config) {
  final parts = _splitPath(path);
  for (final part in parts) {
    if (config.isExcludedFolder(part)) return true;
  }
  return false;
}

List<String> _splitPath(String path) {
  return path.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).toList();
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
