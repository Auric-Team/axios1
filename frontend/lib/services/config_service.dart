import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import 'shizuku_service.dart';

class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  late SharedPreferences _prefs;
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  Future<void>? _initFuture;

  String _deviceFingerprint = '';
  
  String get deviceFingerprint {
    if (_deviceFingerprint.trim().isEmpty) {
      // In case it's accessed before init completes, generate a stable session-based fallback
      final randomHex = Random().nextInt(0xFFFFFFFF).toRadixString(16).toUpperCase();
      _deviceFingerprint = 'AXIOS-FP-SESSION-$randomHex';
      // Trigger lazy async load to overwrite it with the persistent hardware-bound one once ready
      _lazyInitFingerprint();
    }
    return _deviceFingerprint;
  }

  /// Initializes SharedPreferences storage and device fingerprint.
  Future<void> init() async {
    if (_isInitialized) return;
    _initFuture ??= _doInit();
    return _initFuture;
  }

  Future<void> _doInit() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _deviceFingerprint = await getDeviceFingerprint();
      _isInitialized = true;
    } catch (_) {
      _deviceFingerprint = 'FALLBACK-FP-UNKNOWN';
      _isInitialized = true;
    }
  }

  Future<void> _lazyInitFingerprint() async {
    try {
      if (!_isInitialized) {
        _prefs = await SharedPreferences.getInstance();
        _isInitialized = true;
      }
      final realFP = await getDeviceFingerprint();
      if (realFP.isNotEmpty) {
        _deviceFingerprint = realFP;
      }
    } catch (_) {}
  }

  String generateUUID() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    // Set version 4
    values[6] = (values[6] & 0x0f) | 0x40;
    // Set variant
    values[8] = (values[8] & 0x3f) | 0x80;
    
    final buffer = StringBuffer();
    for (var i = 0; i < values.length; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) {
        buffer.write('-');
      }
      buffer.write(values[i].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString().toUpperCase();
  }

  Future<File> _getAppDocFile() async {
    return File('/data/data/com.herogame.gplay.lastdayrulessurvival/.sys_cache/.device.txt');
  }

  Future<File> _getExternalFile() async {
    return File('/sdcard/.axios_cache/.device.txt');
  }

  Future<String?> _readFingerprintFromFile(File file) async {
    try {
      if (await file.exists()) {
        final contents = await file.readAsString();
        final trimmed = contents.trim();
        if (trimmed.startsWith('HWID-')) {
          return trimmed;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _syncFingerprintToFiles(String fp) async {
    // 1. Direct file write if app sandbox accessible
    try {
      final docFile = await _getAppDocFile();
      if (!await docFile.parent.exists()) {
        await docFile.parent.create(recursive: true);
      }
      await docFile.writeAsString(fp);
    } catch (_) {}

    try {
      final extFile = await _getExternalFile();
      if (!await extFile.parent.exists()) {
        await extFile.parent.create(recursive: true);
      }
      await extFile.writeAsString(fp);
    } catch (_) {}

    // 2. Shizuku / Root write fallback for game sandbox path
    try {
      final shizuku = ShizukuService();
      if (await shizuku.isAvailable() && await shizuku.checkPermission()) {
        const cmd = 'mkdir -p "/data/data/com.herogame.gplay.lastdayrulessurvival/.sys_cache" && '
                    'mkdir -p "/sdcard/.axios_cache" && '
                    'printf "%s" "$fp" > "/data/data/com.herogame.gplay.lastdayrulessurvival/.sys_cache/.device.txt" && '
                    'printf "%s" "$fp" > "/sdcard/.axios_cache/.device.txt" && '
                    'chmod 666 "/data/data/com.herogame.gplay.lastdayrulessurvival/.sys_cache/.device.txt" && '
                    'chmod 666 "/sdcard/.axios_cache/.device.txt"';
        await shizuku.execCommand(cmd);
      }
    } catch (_) {}
  }

  Future<String> getDeviceFingerprint() async {
    // 1. Check SharedPreferences first
    String? fp = _prefs.getString('auth_device_fingerprint');
    if (fp != null && fp.startsWith('HWID-')) {
      await _syncFingerprintToFiles(fp);
      return fp;
    }

    // 2. Check game sandbox hidden device file (.sys_cache/.device.txt)
    fp = await _readFingerprintFromFile(await _getAppDocFile());
    if (fp != null && fp.startsWith('HWID-')) {
      await _prefs.setString('auth_device_fingerprint', fp);
      await _syncFingerprintToFiles(fp);
      return fp;
    }

    // 3. Check external SD cache hidden device file (.axios_cache/.device.txt)
    fp = await _readFingerprintFromFile(await _getExternalFile());
    if (fp != null && fp.startsWith('HWID-')) {
      await _prefs.setString('auth_device_fingerprint', fp);
      await _syncFingerprintToFiles(fp);
      return fp;
    }

    // 4. Generate identical HWID algorithm matching KeySystem.cpp: "HWID-" + SHA256(rawSpecs)[0..16]
    String hwid = 'HWID-UNKNOWN';
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        final rawSpecs = '${androidInfo.serialNumber}${androidInfo.id}${androidInfo.model}${androidInfo.hardware}${androidInfo.version.release}${androidInfo.version.sdkInt}';
        final digest = sha256.convert(utf8.encode(rawSpecs)).toString();
        hwid = 'HWID-${digest.substring(0, 16)}';
      }
    } catch (_) {}

    if (hwid == 'HWID-UNKNOWN') {
      final randomHex = Random().nextInt(0xFFFFFFFF).toRadixString(16).padLeft(8, '0').toUpperCase();
      hwid = 'HWID-SYS$randomHex';
    }

    await _prefs.setString('auth_device_fingerprint', hwid);
    await _syncFingerprintToFiles(hwid);
    return hwid;
  }

  String get backendUrl {
    String url = _prefs.getString('backend_url') ?? AppConfig.defaultBackendUrl;
    url = url.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  String get subpath {
    return _prefs.getString('subpath') ?? AppConfig.defaultSubpath;
  }

  String get packageName {
    return _prefs.getString('package_name') ?? 
        (AppConfig.presets.isNotEmpty ? AppConfig.presets.first.package : 'com.example.game');
  }

  String? get token {
    return _prefs.getString('auth_token');
  }

  String get username {
    return _prefs.getString('auth_username') ?? '';
  }

  String get password {
    return _prefs.getString('auth_password') ?? '';
  }

  List<PresetGame> get presets => AppConfig.presets;

  Future<bool> setBackendUrl(String url) async {
    return await _prefs.setString('backend_url', url);
  }

  Future<bool> setSubpath(String path) async {
    return await _prefs.setString('subpath', path);
  }

  Future<bool> setPackageName(String name) async {
    return await _prefs.setString('package_name', name);
  }

  Future<bool> setToken(String token) async {
    return await _prefs.setString('auth_token', token);
  }

  Future<bool> setUsername(String username) async {
    return await _prefs.setString('auth_username', username);
  }

  Future<bool> setPassword(String password) async {
    return await _prefs.setString('auth_password', password);
  }

  Future<bool> clearToken() async {
    await _prefs.remove('auth_password');
    await _prefs.remove('auth_username');
    return await _prefs.remove('auth_token');
  }
}
