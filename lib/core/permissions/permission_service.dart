import 'dart:io';
import 'package:flutter/services.dart';

/// Checks and requests storage permissions for file path access.
///
/// On Android 11+ (API 30+), MANAGE_EXTERNAL_STORAGE is needed to access
/// arbitrary filesystem paths outside the app-specific directory.
/// On Windows/Linux/macOS, no permission is needed (always granted).
class PermissionService {
  static const _channel = MethodChannel('com.wisebreeze.brarchive/permissions');

  /// Returns true if the app has permission to access [path].
  static Future<bool> hasStoragePermission(String path) async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('hasStoragePermission', {
        'path': path,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Requests storage permission. Returns true if granted.
  static Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('requestStoragePermission');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }
}
