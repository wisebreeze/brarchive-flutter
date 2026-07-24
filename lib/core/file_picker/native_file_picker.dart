import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart' as pp;

/// Native file picker using platform method channels.
///
/// - Android: uses Intent.ACTION_OPEN_DOCUMENT (Storage Access Framework)
/// - Windows: uses Win32 GetOpenFileNameW / IFileDialog via method channel
///
/// This avoids the file_picker package dependency which pulls in
/// flutter_plugin_android_lifecycle and causes compileSdk conflicts.
class NativeFilePicker {
  static const _channel = MethodChannel('com.wisebreeze.brarchive/file_picker');

  /// Picks a single file. Returns the absolute path or null if cancelled.
  static Future<String?> pickFile({List<String>? extensions}) async {
    try {
      final result = await _channel.invokeMethod<String>('pickFile', {
        'extensions': extensions ?? [],
      });
      return result;
    } on PlatformException {
      return null;
    }
  }

  /// Picks a directory. Returns the absolute path or null if cancelled.
  static Future<String?> pickDirectory() async {
    try {
      final result = await _channel.invokeMethod<String>('pickDirectory');
      return result;
    } on PlatformException {
      return null;
    }
  }

  /// Copies a file (from a possibly content-URI path on Android) to a
  /// temporary location and returns the real path. On desktop this is a no-op.
  static Future<String> resolveToFilePath(String uriOrPath) async {
    if (Platform.isAndroid && uriOrPath.startsWith('content://')) {
      try {
        final result = await _channel.invokeMethod<String>('resolvePath', {
          'uri': uriOrPath,
        });
        if (result != null) return result;
      } on PlatformException {
        // fall through
      }
    }
    return uriOrPath;
  }

  /// Returns the system Downloads directory path.
  /// On Android, uses Environment.getExternalStoragePublicDirectory(DIRECTORY_DOWNLOADS).
  /// On Windows/Linux/macOS, uses path_provider's getDownloadsDirectory.
  static Future<String> getDownloadsDirectory() async {
    if (Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<String>('getDownloadsDirectory');
        if (result != null && result.isNotEmpty) return result;
      } on PlatformException {
        // fall through
      }
    }
    // Desktop fallback via path_provider
    try {
      final dir = await pp.getDownloadsDirectory();
      if (dir != null) return dir.path;
    } catch (_) {}
    // Ultimate fallback
    return (await pp.getApplicationDocumentsDirectory()).path;
  }
}
