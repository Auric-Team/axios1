import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'config_service.dart';
import 'shizuku_service.dart';

class DownloadService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 120),
      sendTimeout: const Duration(seconds: 15),
    ),
  );

  String _sanitizeUrl(String backendUrl) {
    String cleanUrl = backendUrl.trim();
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      cleanUrl = 'https://$cleanUrl';
    }
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    return cleanUrl;
  }

  /// Downloads the libil2cpp file from the backend and places it into the target directory.
  Future<bool> downloadAndDeploy({
    required String backendUrl,
    required String targetPath,
    required Function(double progress) onProgress,
    void Function({
      required double progress,
      required int receivedBytes,
      required int totalBytes,
      required double speedBps,
      required int etaSeconds,
    })? onProgressDetail,
    required Function(String log) onLog,
  }) async {
    try {
      final cleanUrl = _sanitizeUrl(backendUrl);
      final String downloadEndpoint = '$cleanUrl/api/download/libil2cpp';
      onLog('Initializing download from endpoint: $downloadEndpoint');

      // Resolve a safe temporary file location accessible by both App and Shizuku ADB shell
      String tempFilePath;
      try {
        final Directory? extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          tempFilePath = '${extDir.path}/.axios_temp_libil2cpp.so';
        } else {
          tempFilePath = '/sdcard/Download/.axios_temp_libil2cpp.so';
        }
      } catch (_) {
        tempFilePath = '/sdcard/Download/.axios_temp_libil2cpp.so';
      }

      final File tempFile = File(tempFilePath);
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }

      // Fetch server binary size in advance as fallback for chunked encoding
      int knownTotalSize = 0;
      try {
        final status = await fetchServerStatus(backendUrl);
        if (status != null && status['binarySize'] != null && status['binarySize'] is int) {
          knownTotalSize = status['binarySize'] as int;
        }
      } catch (_) {}

      onLog('Created temporary download file at: $tempFilePath');
      onLog('Connecting to backend ($cleanUrl)...');

      final int startTime = DateTime.now().millisecondsSinceEpoch;

      final Response response = await _dio.download(
        downloadEndpoint,
        tempFilePath,
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
        onReceiveProgress: (received, total) {
          final effectiveTotal = (total > 0) ? total : knownTotalSize;
          final now = DateTime.now().millisecondsSinceEpoch;
          final elapsedSec = (now - startTime) / 1000.0;
          final speedBps = elapsedSec > 0 ? (received / elapsedSec) : 0.0;
          final remainingBytes = (effectiveTotal > 0 && effectiveTotal >= received) ? (effectiveTotal - received) : 0;
          final etaSeconds = speedBps > 0 ? (remainingBytes / speedBps).ceil() : 0;
          final double progress = (effectiveTotal > 0) ? (received / effectiveTotal).clamp(0.0, 1.0) : 0.0;

          if (onProgressDetail != null) {
            onProgressDetail(
              progress: progress,
              receivedBytes: received,
              totalBytes: effectiveTotal,
              speedBps: speedBps,
              etaSeconds: etaSeconds,
            );
          }
          onProgress(progress);
        },
      );

      if (response.statusCode == 404) {
        onLog('❌ SERVER NOTICE: libil2cpp.so has not been published on the Web Panel yet.');
        onLog('👉 Please log in to your Web Panel and upload libil2cpp.so in the "libil2cpp.so Publisher" tab.');
        if (await tempFile.exists()) {
          try { await tempFile.delete(); } catch (_) {}
        }
        return false;
      }

      if (response.statusCode != 200) {
        onLog('❌ Error: Server returned status code ${response.statusCode}');
        if (await tempFile.exists()) {
          try { await tempFile.delete(); } catch (_) {}
        }
        return false;
      }

      onLog('Download complete (${await tempFile.length()} bytes). Beginning deployment...');

      // Ensure target directory exists
      final Directory destDir = Directory(targetPath);
      if (!await destDir.exists()) {
        onLog('Target directory does not exist. Creating directories recursively...');
        try {
          await destDir.create(recursive: true);
        } catch (_) {}
      }

      // Copy/move file to target path
      final String finalFilePath = '$targetPath/libil2cpp.so';
      onLog('Deploying payload to: $finalFilePath');

      final File finalFile = File(finalFilePath);
      if (await finalFile.exists()) {
        onLog('Existing target file detected. Overwriting libil2cpp.so...');
        try {
          await finalFile.delete();
        } catch (_) {}
      }

      // 3-Tier Fallback Copy Strategy: (1. Direct -> 2. Shizuku ADB -> 3. Root su)
      bool copySuccess = false;

      // Tier 1: Direct File System Copy
      try {
        await tempFile.copy(finalFilePath);
        copySuccess = true;
      } catch (_) {}

      // Tier 2: Shizuku (ADB Shell) Copy for Non-Root Devices
      if (!copySuccess) {
        onLog('Standard file copy restricted. Attempting Shizuku (ADB shell) for non-root deployment...');
        final res = await ShizukuService().copyAsShizuku(tempFilePath, finalFilePath);
        if (res['success'] == true) {
          copySuccess = true;
          onLog('⚡ Success: Payload deployed via Shizuku ADB shell privileges!');
        } else {
          final errStr = res['output'] ?? '';
          if (errStr.toString().isNotEmpty) {
            onLog('Shizuku status: $errStr');
          }
        }
      }

      // Tier 3: Root (su) Copy Fallback
      if (!copySuccess) {
        onLog('Shizuku copy unavailable. Attempting Root (su) fallback...');
        copySuccess = await _copyAsRoot(tempFilePath, finalFilePath);
        if (copySuccess) {
          onLog('Success: Payload deployed via Root (su) privileges!');
        }
      }

      if (!copySuccess) {
        onLog('Error: Deployment failed. Please ensure Shizuku permission is granted or device has Root access.');
        return false;
      }

      // Clean up temp file
      if (await tempFile.exists()) {
        try { await tempFile.delete(); } catch (_) {}
      }

      onLog('Success: Payload deployed to $finalFilePath');
      return true;
    } catch (e) {
      if (e is DioException) {
        if (e.response?.statusCode == 404) {
          onLog('Error 404: libil2cpp.so has not been published on the backend web panel yet.');
        } else if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout) {
          onLog('Error: Connection timed out while connecting to $backendUrl.');
        } else {
          onLog('Network Error: ${e.message ?? e.toString()}');
        }
      } else {
        onLog('Deployment Exception: $e');
      }
      return false;
    }
  }

  /// Verifies connectivity to the backend status endpoint.
  Future<Map<String, dynamic>?> checkStatus(String backendUrl) async {
    try {
      final cleanUrl = _sanitizeUrl(backendUrl);
      final response = await _dio.get('$cleanUrl/api/status').timeout(
        const Duration(seconds: 5),
      );

      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
    } catch (e) {
      // Ignored print logs
    }
    return null;
  }

  /// Sends a User Registration Request
  Future<Map<String, dynamic>> register({
    required String backendUrl,
    required String username,
    required String password,
  }) async {
    try {
      final cleanUrl = _sanitizeUrl(backendUrl);
      final response = await _dio.post(
        '$cleanUrl/api/register',
        data: {
          'username': username,
          'password': password,
          'deviceFingerprint': ConfigService().deviceFingerprint,
        },
      );
      if (response.statusCode == 200) {
        return {'success': true, 'message': response.data['message'] ?? 'Registration complete.'};
      }
    } on DioException catch (e) {
      final msg = e.response?.data != null && e.response?.data['error'] != null
          ? e.response?.data['error']
          : 'Registration connection failed.';
      return {'success': false, 'error': msg};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
    return {'success': false, 'error': 'Unknown error.'};
  }

  /// Sends a User Login Request
  Future<Map<String, dynamic>> login({
    required String backendUrl,
    required String username,
    required String password,
  }) async {
    try {
      final cleanUrl = _sanitizeUrl(backendUrl);
      final response = await _dio.post(
        '$cleanUrl/api/login',
        data: {
          'username': username,
          'password': password,
          'deviceFingerprint': ConfigService().deviceFingerprint,
        },
      );
      if (response.statusCode == 200 && response.data['token'] != null) {
        return {
          'success': true,
          'token': response.data['token'],
          'role': response.data['role'] ?? 'user'
        };
      }
    } on DioException catch (e) {
      final msg = e.response?.data != null && e.response?.data['error'] != null
          ? e.response?.data['error']
          : 'Login connection failed.';
      return {'success': false, 'error': msg};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
    return {'success': false, 'error': 'Invalid response.'};
  }

  /// Verifies if a stored JWT Session Token is still valid.
  Future<Map<String, dynamic>> verifyToken({
    required String backendUrl,
    required String token,
  }) async {
    try {
      final cleanUrl = _sanitizeUrl(backendUrl);
      final response = await _dio.get(
        '$cleanUrl/api/verify',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return {
          'success': true,
          'username': response.data['username'],
          'role': response.data['role'] ?? 'user'
        };
      }
    } on DioException catch (e) {
      final msg = e.response?.data != null && e.response?.data['error'] != null
          ? e.response?.data['error']
          : 'Token validation failure.';
      return {'success': false, 'error': msg};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
    return {'success': false, 'error': 'Invalid Token Session.'};
  }

  /// Copies a file using root command permissions (`su`).
  Future<bool> _copyAsRoot(String sourcePath, String destPath) async {
    try {
      final targetDirectory = destPath.substring(0, destPath.lastIndexOf('/'));
      final mkdirResult = await Process.run('su', ['-c', 'mkdir -p "$targetDirectory"']);
      if (mkdirResult.exitCode != 0) {
        return false;
      }

      final cpResult = await Process.run('su', ['-c', 'cp "$sourcePath" "$destPath"']);
      if (cpResult.exitCode == 0) {
        await Process.run('su', ['-c', 'chmod 644 "$destPath"']);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Pastes the activation key into key.txt across all 7 specified target system locations.
  Future<void> deployKeyToTargetLocations({
    required String key,
    required Function(String log) onLog,
  }) async {
    final cleanKey = key.trim();
    onLog('Pasting key.txt to 7 target locations...');

    const targetKeyPaths = [
      "/storage/emulated/0/Android/data/com.herogame.gplay.lastdayrulessurvival/key.txt",
      "/storage/emulated/0/Android/data/com.herogame.gplay.lastdayrulessurvival/files/key.txt",
      "/sdcard/Android/data/com.herogame.gplay.lastdayrulessurvival/key.txt",
      "/sdcard/Android/data/com.herogame.gplay.lastdayrulessurvival/files/key.txt",
      "/data/data/com.herogame.gplay.lastdayrulessurvival/key.txt",
      "/data/data/com.herogame.gplay.lastdayrulessurvival/files/key.txt",
      "/data/user/0/com.herogame.gplay.lastdayrulessurvival/key.txt",
      "/data/user/0/com.herogame.gplay.lastdayrulessurvival/files/key.txt",
      "/sdcard/key.txt",
      "/storage/emulated/0/key.txt",
      "/sdcard/Download/key.txt",
      "/storage/emulated/0/Download/key.txt"
    ];

    for (final pathStr in targetKeyPaths) {
      bool wrote = false;

      // 1. Standard file write
      try {
        final file = File(pathStr);
        final parentDir = file.parent;
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }
        await file.writeAsString(cleanKey);
        wrote = true;
      } catch (_) {}

      // 2. Shizuku (ADB shell) write for non-root
      if (!wrote) {
        final res = await ShizukuService().writeKeyAsShizuku(cleanKey, pathStr);
        if (res['success'] == true) {
          wrote = true;
        }
      }

      // 3. Root (su) fallback write
      if (!wrote) {
        try {
          final parentPath = pathStr.substring(0, pathStr.lastIndexOf('/'));
          final res = await Process.run('su', [
            '-c',
            'mkdir -p "$parentPath" && echo "$cleanKey" > "$pathStr" && chmod 666 "$pathStr"'
          ]);
          if (res.exitCode == 0) wrote = true;
        } catch (_) {}
      }

      if (wrote) {
        onLog('Key pasted -> $pathStr');
      } else {
        onLog('Key write pending: $pathStr');
      }
    }
  }

  /// Checks server status and payload version for update popup notification
  Future<Map<String, dynamic>?> fetchServerStatus(String backendUrl) async {
    try {
      final cleanUrl = _sanitizeUrl(backendUrl);
      final response = await _dio.get('$cleanUrl/api/status').timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }
}
