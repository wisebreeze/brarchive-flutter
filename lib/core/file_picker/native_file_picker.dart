import 'dart:io';
import 'package:flutter/services.dart';

/// Native file picker using platform method channels.
///
/// - Android: uses Intent.ACTION_OPEN_DOCUMENT (Storage Access Framework)
/// - Windows: uses Win32 GetOpenFileNameW / SHBrowseForFolder via method channel
///
/// This avoids the file_picker package dependency which pulls in
/// flutter_plugin_android_lifecycle and causes compileSdk conflicts.
class NativeFilePicker {
  static const _channel = MethodChannel('com.wisebreeze.brarchive/file_picker');

  /// Picks a single file. Returns the absolute path or null if cancelled.
  ///
  /// [extensions] is a list of extensions without dot, e.g. ['zip', 'mcpack'].
  /// On Android the path is a content URI; the native side copies it to the
  /// app cache and returns a real file path.
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
}
