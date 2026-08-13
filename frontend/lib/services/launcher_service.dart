import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'shizuku_service.dart';

class LauncherService {
  static const _channel = MethodChannel('com.axios.installer/launcher');

  /// Attempts to launch an installed Android application package with 3-tier fallback.
  Future<bool> launchApp(String packageName) async {
    // Tier 1: Native Android PackageManager Intent Launch
    try {
      final bool? success = await _channel.invokeMethod<bool>('launchApp', {
        'packageName': packageName,
      });
      if (success == true) {
        return true;
      }
    } on PlatformException catch (e) {
      debugPrint('Native launcher intent failed: ${e.message}');
    } catch (_) {}

    // Tier 2: Shizuku (ADB shell) Launch for Non-Rooted Devices
    try {
      final shizukuService = ShizukuService();
      if (await shizukuService.isAvailable() && await shizukuService.checkPermission()) {
        final res = await shizukuService.execCommand(
          'monkey -p $packageName -c android.intent.category.LAUNCHER 1',
        );
        if (res['exitCode'] == 0) {
          return true;
        }
      }
    } catch (_) {}

    // Tier 3: Root (su) Shell Launch
    try {
      final res = await Process.run('su', [
        '-c',
        'monkey -p $packageName -c android.intent.category.LAUNCHER 1'
      ]);
      if (res.exitCode == 0) {
        return true;
      }
    } catch (_) {}

    return false;
  }
}
