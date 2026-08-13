import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

class ShizukuService {
  static const MethodChannel _channel = MethodChannel('com.axios.installer/shizuku');

  /// Checks if Shizuku binder service is running on the Android device.
  Future<bool> isAvailable() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? available = await _channel.invokeMethod<bool>('isShizukuAvailable');
      return available ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Checks if Shizuku permission is currently granted to this application.
  Future<bool> checkPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? granted = await _channel.invokeMethod<bool>('checkPermission');
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Triggers the Android system permission prompt for Shizuku.
  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? requested = await _channel.invokeMethod<bool>('requestPermission');
      return requested ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Executes a shell command with elevated Shizuku ADB permissions (non-root).
  Future<Map<String, dynamic>> execCommand(String command) async {
    if (!Platform.isAndroid) {
      return {'exitCode': -1, 'output': 'Platform not supported'};
    }
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('execCommand', {
        'command': command,
      });
      if (res != null) {
        return {
          'exitCode': res['exitCode'] ?? -1,
          'output': res['output'] ?? '',
        };
      }
    } catch (e) {
      return {'exitCode': -1, 'output': e.toString()};
    }
    return {'exitCode': -1, 'output': 'Command failed to execute'};
  }

  /// Copies a file using Shizuku ADB shell privileges for non-rooted devices.
  Future<Map<String, dynamic>> copyAsShizuku(String sourcePath, String destPath) async {
    try {
      final targetDir = destPath.substring(0, destPath.lastIndexOf('/'));
      try {
        await Process.run('chmod', ['666', sourcePath]);
      } catch (_) {}

      final cmd = 'mkdir -p "$targetDir" && cp -f "$sourcePath" "$destPath" && chmod 644 "$destPath"';
      final result = await execCommand(cmd);
      return {
        'success': result['exitCode'] == 0,
        'output': result['output'] ?? '',
        'exitCode': result['exitCode'] ?? -1,
      };
    } catch (e) {
      return {'success': false, 'output': e.toString(), 'exitCode': -1};
    }
  }

  /// Pastes key text using Shizuku ADB shell privileges.
  Future<Map<String, dynamic>> writeKeyAsShizuku(String key, String destPath) async {
    try {
      final cleanKey = key.trim();
      final targetDir = destPath.substring(0, destPath.lastIndexOf('/'));
      final cmd = 'mkdir -p "$targetDir" && printf "%s" "$cleanKey" > "$destPath" && chmod 666 "$destPath"';
      final result = await execCommand(cmd);
      return {
        'success': result['exitCode'] == 0,
        'output': result['output'] ?? '',
        'exitCode': result['exitCode'] ?? -1,
      };
    } catch (e) {
      return {'success': false, 'output': e.toString(), 'exitCode': -1};
    }
  }
}
