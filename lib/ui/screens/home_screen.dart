import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_state.dart';
import '../../core/brarchive/brarchive_converter.dart';
import '../../core/file_picker/native_file_picker.dart';
import '../../core/i18n/i18n.dart';
import '../../core/permissions/permission_service.dart';
import 'settings_screen.dart';

/// Main screen of the brarchive converter app.
///
/// Layout:
///   - AppBar with overflow "more" menu (language + theme)
///   - Input file picker row
///   - Output directory picker row (defaults to Downloads)
///   - Pack / Unpack action buttons
///   - Console output panel
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _inputController = TextEditingController();
  final _outputController = TextEditingController();
  final _consoleController = TextEditingController();
  final _scrollController = ScrollController();
  final _logBuffer = StringBuffer();

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initDefaultOutput();
  }

  Future<void> _initDefaultOutput() async {
    final dir = await NativeFilePicker.getDownloadsDirectory();
    if (mounted) {
      _outputController.text = dir;
    }
  }

  void _log(String line) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    _logBuffer.writeln('[$ts] $line');
  }

  /// Flushes buffered logs to the console widget in a single update.
  /// Called after batch operations complete to avoid O(n²) string
  /// concatenation when hundreds of log lines are produced.
  void _flushLogs() {
    if (_logBuffer.isEmpty) return;
    final newText = _logBuffer.toString();
    _logBuffer.clear();
    // Append to existing text in one operation
    _consoleController.text = _consoleController.text + newText;
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent,
        );
      }
    });
  }

  Future<void> _pickInputFile() async {
    final result = await NativeFilePicker.pickFile(extensions: ['zip', 'mcpack']);
    if (result != null && result.isNotEmpty) {
      final path = await NativeFilePicker.resolveToFilePath(result);
      _inputController.text = path;
    }
  }

  Future<void> _pickOutputDir() async {
    final result = await NativeFilePicker.pickDirectory();
    if (result != null && result.isNotEmpty) {
      _outputController.text = result;
    }
  }

  Future<void> _runConversion(bool isPack) async {
    if (_busy) return;
    final state = context.read<AppState>();
    final i18n = state.i18n;

    final rawInput = _inputController.text.trim();
    final outputDir = _outputController.text.trim();

    if (rawInput.isEmpty) {
      _showError(i18n.t('errNoInput'));
      return;
    }
    if (outputDir.isEmpty) {
      _showError(i18n.t('errNoOutput'));
      return;
    }

    // Resolve content:// URIs to real file paths (Android SAF)
    String inputPath = rawInput;
    if (inputPath.startsWith('content://')) {
      inputPath = await NativeFilePicker.resolveToFilePath(inputPath);
    }

    final ext = p.extension(inputPath).toLowerCase();
    if (ext != '.zip' && ext != '.mcpack') {
      _showError(i18n.t('errInvalidInput'));
      return;
    }

    // Check storage permission
    final hasPerm = await PermissionService.hasStoragePermission(inputPath) &&
        await PermissionService.hasStoragePermission(outputDir);
    if (!hasPerm) {
      final granted = await _showPermissionDialog(i18n);
      if (!granted) return;
      final recheck = await PermissionService.hasStoragePermission(inputPath) &&
          await PermissionService.hasStoragePermission(outputDir);
      if (!recheck) {
        _showError(i18n.t('errPermissionDenied'));
        return;
      }
    }

    if (!File(inputPath).existsSync()) {
      _showError(i18n.t('errInputNotExist'));
      return;
    }
    if (!Directory(outputDir).existsSync()) {
      _showError(i18n.t('errOutputNotExist'));
      return;
    }

    setState(() => _busy = true);
    _log(i18n.t('logStarted', {
      'action': i18n.t(isPack ? 'actionPack' : 'actionUnpack'),
      'file': p.basename(inputPath),
    }));
    _flushLogs();

    final converter = BrarchiveConverter(
      log: _log,
      i18n: i18n,
      config: ConverterConfig(
        packImages: state.packImages,
        removeProcessedFiles: state.removeProcessedFiles,
        skipEmptyEntries: state.skipEmptyEntries,
      ),
    );

    try {
      final result = isPack
          ? await converter.pack(inputPath: inputPath, outputDir: outputDir)
          : await converter.unpack(inputPath: inputPath, outputDir: outputDir);

      // Flush all logs collected from the background isolate in one batch
      _flushLogs();

      if (result.success) {
        _log(i18n.t('logOutputAt', {'path': result.outputPath!}));
        _log(i18n.t('logDone', {
          'duration': '${result.duration.inMilliseconds}ms',
        }));
        _flushLogs();
        _showSnack(i18n.t('statusDone'), isError: false);
      } else {
        _showSnack(i18n.t('statusError'), isError: true);
      }
    } catch (e) {
      _log(i18n.t('logError', {'error': e.toString()}));
      _flushLogs();
      _showSnack(i18n.t('statusError'), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _showPermissionDialog(I18n i18n) async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(i18n.t('permissionRequired')),
        content: Text(i18n.t('permissionMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(i18n.t('grant')),
          ),
        ],
      ),
    );
    if (result != true) return false;
    return await PermissionService.requestStoragePermission();
  }

  void _showError(String message) {
    _showSnack(message, isError: true);
  }

  void _showSnack(String message, {required bool isError}) {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: isError ? cs.onErrorContainer : cs.onPrimaryContainer,
          ),
        ),
        backgroundColor: isError ? cs.errorContainer : cs.primaryContainer,
      ),
    );
  }

  @override
  void dispose() {
    _inputController.dispose();
    _outputController.dispose();
    _consoleController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final i18n = state.i18n;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(i18n.t('appTitle')),
        actions: [_buildMoreMenu(state, i18n)],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  AppBar().preferredSize.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom - 32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildInputRow(i18n, cs),
                const SizedBox(height: 12),
                _buildOutputRow(i18n, cs),
                const SizedBox(height: 20),
                _buildActionButtons(i18n, cs),
                const SizedBox(height: 20),
                SizedBox(
                  height: 300,
                  child: _buildConsole(i18n, cs),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputRow(I18n i18n, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          i18n.t('inputLabel'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                decoration: InputDecoration(
                  hintText: i18n.t('inputHint'),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: _pickInputFile,
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(i18n.t('browse')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOutputRow(I18n i18n, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          i18n.t('outputLabel'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _outputController,
                decoration: InputDecoration(
                  hintText: i18n.t('outputHint'),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: _pickOutputDir,
              icon: const Icon(Icons.drive_folder_upload_outlined),
              label: Text(i18n.t('browse')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButtons(I18n i18n, ColorScheme cs) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _busy ? null : () => _runConversion(true),
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.archive_outlined),
            label: Text(i18n.t('pack')),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: _busy ? null : () => _runConversion(false),
            style: FilledButton.styleFrom(
              backgroundColor: cs.secondaryContainer,
              foregroundColor: cs.onSecondaryContainer,
            ),
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.unarchive_outlined),
            label: Text(i18n.t('unpack')),
          ),
        ),
      ],
    );
  }

  Widget _buildConsole(I18n i18n, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.terminal_outlined, size: 18, color: cs.primary),
            const SizedBox(width: 6),
            Text(
              i18n.t('console'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Spacer(),
            if (_consoleController.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'Clear',
                onPressed: _busy
                    ? null
                    : () => setState(() => _consoleController.clear()),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: _consoleController.text.isEmpty
                ? Center(
                    child: Text(
                      i18n.t('consoleEmpty'),
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  )
                : SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      _consoleController.text,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.4,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildMoreMenu(AppState state, I18n i18n) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: i18n.t('more'),
      onSelected: (value) async {
        if (value == 'settings') {
          if (!mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
        } else if (value == 'github') {
          await _launchUrl('https://github.com/wisebreeze/brarchive-flutter');
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'settings',
          child: Row(
            children: [
              const Icon(Icons.settings_outlined),
              const SizedBox(width: 12),
              Text(i18n.t('settings')),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'github',
          child: Row(
            children: [
              const Icon(Icons.code),
              const SizedBox(width: 12),
              Text(i18n.t('githubRepo')),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
