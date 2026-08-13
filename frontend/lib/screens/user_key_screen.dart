import 'dart:async';
import 'package:flutter/material.dart';
import '../services/config_service.dart';
import '../services/download_service.dart';
import '../services/key_service.dart';
import '../services/detection_service.dart';
import '../services/launcher_service.dart';
import '../services/shizuku_service.dart';
import '../widgets/cyber_card.dart';
import '../widgets/cyber_button.dart';
import '../widgets/cyber_text_field.dart';
import '../widgets/cyber_console.dart';
import 'auth_screen.dart';

class UserKeyScreen extends StatefulWidget {
  const UserKeyScreen({super.key});

  @override
  State<UserKeyScreen> createState() => _UserKeyScreenState();
}

class _UserKeyScreenState extends State<UserKeyScreen> {
  final TextEditingController _keyController = TextEditingController();
  final KeyService _keyService = KeyService();
  final DownloadService _downloadService = DownloadService();
  final DetectionService _detectionService = DetectionService();
  final LauncherService _launcherService = LauncherService();
  final ShizukuService _shizukuService = ShizukuService();

  bool _isValidating = false;
  bool _isDeploying = false;
  bool _isCheckingUpdate = false;
  double _deployProgress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  double _downloadSpeedBps = 0.0;
  int _etaSeconds = 0;
  String _errorMessage = '';
  final List<String> _consoleLogs = [];

  bool _isShizukuRunning = false;
  bool _hasShizukuPermission = false;
  Timer? _shizukuPollTimer;

  Map<String, dynamic>? _updateInfo;
  String _serverVersion = '1.0.0';

  String _formatSpeed(double bps) {
    if (bps >= 1024 * 1024) {
      return '${(bps / (1024 * 1024)).toStringAsFixed(2)} MB/s';
    }
    if (bps >= 1024) {
      return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${bps.round()} B/s';
  }

  String _formatEta(int seconds) {
    if (seconds <= 0) return 'Calculating...';
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    if (mins > 0) {
      return '${mins}m ${secs}s';
    }
    return '${secs}s';
  }

  @override
  void initState() {
    super.initState();
    _checkForUpdates();
    _initShizukuMonitoring();
  }

  @override
  void dispose() {
    _shizukuPollTimer?.cancel();
    _keyController.dispose();
    super.dispose();
  }

  void _initShizukuMonitoring() {
    _checkShizukuStatus();
    // Keep asking / polling Shizuku permission automatically every 3 seconds until granted
    _shizukuPollTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) return;
      _checkShizukuStatus();
    });
  }

  Future<void> _checkShizukuStatus() async {
    final available = await _shizukuService.isAvailable();
    if (!available) {
      if (mounted && _isShizukuRunning) {
        setState(() {
          _isShizukuRunning = false;
          _hasShizukuPermission = false;
        });
      }
      return;
    }

    final hasPerm = await _shizukuService.checkPermission();
    if (mounted) {
      setState(() {
        _isShizukuRunning = true;
        _hasShizukuPermission = hasPerm;
      });
    }

    // Automatically prompt for Shizuku permission if available but not granted
    if (!hasPerm) {
      await _shizukuService.requestPermission();
    }
  }

  void _addLog(String msg) {
    if (!mounted) return;
    setState(() {
      _consoleLogs.add('[${DateTime.now().toLocal().toString().substring(11, 19)}] $msg');
    });
  }

  Future<void> _checkForUpdates() async {
    setState(() => _isCheckingUpdate = true);
    final config = ConfigService();
    final status = await _downloadService.fetchServerStatus(config.backendUrl);
    if (!mounted) return;
    setState(() => _isCheckingUpdate = false);

    if (status != null && status['version'] != null) {
      final version = status['version'].toString();
      setState(() {
        _serverVersion = version;
        _updateInfo = status;
      });

      _showUpdateDialog(status);
    }
  }

  void _showUpdateDialog(Map<String, dynamic> status) {
    final version = status['version'] ?? 'Latest';
    final changelog = status['changelog'] ?? 'Performance and anti-cheat engine improvements.';
    final size = status['binarySize'] != null ? '${((status['binarySize'] as int) / (1024 * 1024)).toStringAsFixed(2)} MB' : 'Full Binary';

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF00FFCC), width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0x2200FFCC),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF00FFCC)),
                    ),
                    child: const Icon(Icons.system_update_alt, color: Color(0xFF00FFCC), size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'VERSION $version AVAILABLE',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF00FFCC),
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Payload Size: $size',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF03060D),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1E293B)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'RELEASE CHANGELOG NOTES:',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF64748B),
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      changelog,
                      style: const TextStyle(fontSize: 13, color: Color(0xFFE2E8F0), height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF94A3B8),
                        side: const BorderSide(color: Color(0xFF334155)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('DISMISS'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00FFCC),
                        foregroundColor: const Color(0xFF0F172A),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 4,
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        if (_keyController.text.trim().isNotEmpty) {
                          _activateAndDeploy();
                        } else {
                          _addLog('Please enter your license key to download and activate libil2cpp.so $version');
                        }
                      },
                      child: const Text(
                        'GET LATEST UPDATE',
                        style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await ConfigService().clearToken();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (ctx) => const AuthScreen()),
    );
  }

  Future<void> _activateAndDeploy() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _errorMessage = 'Activation key cannot be empty.';
      });
      return;
    }

    setState(() {
      _isValidating = true;
      _isDeploying = false;
      _errorMessage = '';
      _consoleLogs.clear();
    });

    _addLog('Connecting to AXIOS Cloud Engine...');
    final config = ConfigService();
    final res = await _keyService.verifyKey(
      backendUrl: config.backendUrl,
      key: key,
      username: config.username,
    );

    if (!mounted) return;

    if (res['success'] != true) {
      setState(() {
        _isValidating = false;
        _errorMessage = res['error'] ?? 'Invalid access key.';
      });
      _addLog('Error: Key authentication failed.');
      return;
    }

    final targetPackage = (res['targetGame'] as String?) ?? 'com.herogame.gplay.lastdayrulessurvival';
    _addLog('Access key authorized for target: $targetPackage');

    setState(() {
      _isValidating = false;
      _isDeploying = true;
    });

    // 1. Request Storage Permission
    _addLog('Requesting storage management permissions...');
    final hasPerm = await _detectionService.requestStoragePermission();
    if (!hasPerm) {
      _addLog('Warning: Standard storage permission restricted.');
    } else {
      _addLog('Storage permissions active.');
    }

    // 2. Check Shizuku status for non-root fallback
    if (_isShizukuRunning) {
      if (_hasShizukuPermission) {
        _addLog('⚡ Shizuku ADB Environment Active (Non-Root Privileges Engaged)');
      } else {
        _addLog('⚡ Shizuku Detected. Requesting Shizuku ADB permission...');
        await _shizukuService.requestPermission();
      }
    }

    // 3. Paste key.txt to ALL 7 specified locations (using Direct -> Root -> Shizuku)
    await _downloadService.deployKeyToTargetLocations(
      key: key,
      onLog: (log) => _addLog(log),
    );

    // 4. Scan Target Game Directory
    _addLog('Scanning device storage for target $targetPackage...');
    final gamePath = await _detectionService.detectGameDirectory(targetPackage);
    if (gamePath == null) {
      setState(() {
        _isDeploying = false;
        _errorMessage = 'Target game directory not found on device.';
      });
      _addLog('Error: Game folders not found. Please install the game first.');
      return;
    }
    _addLog('Target directory resolved: $gamePath');

    // 5. Resolve Destination Subpath
    final destPath = '$gamePath/${config.subpath}';
    _addLog('Resolved installation path: $destPath');

    // 6. Download and Deploy libil2cpp.so
    _addLog('Downloading latest libil2cpp.so binary payload from server...');
    final downloadSuccess = await _downloadService.downloadAndDeploy(
      backendUrl: config.backendUrl,
      targetPath: destPath,
      onProgress: (prog) {
        setState(() {
          _deployProgress = prog;
        });
      },
      onProgressDetail: ({
        required double progress,
        required int receivedBytes,
        required int totalBytes,
        required double speedBps,
        required int etaSeconds,
      }) {
        if (!mounted) return;
        setState(() {
          _deployProgress = progress;
          _receivedBytes = receivedBytes;
          _totalBytes = totalBytes;
          _downloadSpeedBps = speedBps;
          _etaSeconds = etaSeconds;
        });
      },
      onLog: (log) => _addLog(log),
    );

    if (!mounted) return;

    if (!downloadSuccess) {
      setState(() {
        _isDeploying = false;
        _errorMessage = 'Binary download/deployment failed.';
      });
      return;
    }

    _addLog('Deployment completed successfully! Launching target game...');
    await Future.delayed(const Duration(milliseconds: 1200));

    final launchSuccess = await _launcherService.launchApp(targetPackage);
    if (!launchSuccess) {
      _addLog('Warning: Could not auto-launch $targetPackage. Please launch the game manually.');
    }

    setState(() {
      _isDeploying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.security, color: Color(0xFF00FFCC), size: 20),
            const SizedBox(width: 8),
            const Text(
              'AXIOS TERMINAL',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0x2200FFCC),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x6600FFCC)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF00FFCC),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'PAYLOAD v$_serverVersion',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Color(0xFF00FFCC),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF94A3B8)),
            onPressed: _checkForUpdates,
            tooltip: 'Check Update',
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFFFF2A6D)),
            onPressed: _logout,
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 6),

              // Brand Icon Header
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00FFCC), Color(0xFFBD00FF)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00FFCC).withAlpha((255 * 0.4).round()),
                        blurRadius: 25,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.memory, color: Colors.black, size: 42),
                ),
              ),
              const SizedBox(height: 16),

              // Shizuku Environment Status Badge
              if (_isShizukuRunning) ...[
                GestureDetector(
                  onTap: () {
                    if (!_hasShizukuPermission) {
                      _shizukuService.requestPermission();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _hasShizukuPermission ? const Color(0x2200FFCC) : const Color(0x22FFB800),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _hasShizukuPermission ? const Color(0xFF00FFCC) : const Color(0xFFFFB800),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _hasShizukuPermission ? Icons.bolt : Icons.warning_amber_rounded,
                          color: _hasShizukuPermission ? const Color(0xFF00FFCC) : const Color(0xFFFFB800),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _hasShizukuPermission
                                ? '⚡ SHIZUKU ADB ENVIRONMENT: ACTIVE (NON-ROOT DEPLOYMENT)'
                                : '⚡ SHIZUKU DETECTED: TAP TO GRANT ADB PERMISSION',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: _hasShizukuPermission ? const Color(0xFF00FFCC) : const Color(0xFFFFB800),
                            ),
                          ),
                        ),
                        if (!_hasShizukuPermission)
                          const Text(
                            'GRANT',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Key Input Card
              CyberCard(
                borderGlowColors: const [Color(0x3300FFCC), Color(0x33BD00FF)],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'LICENSE KEY DEPLOYMENT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 14),

                    CyberTextField(
                      controller: _keyController,
                      label: 'ENTER ENGINE LICENSE KEY',
                      prefixIcon: Icons.vpn_key_outlined,
                      obscureText: false,
                    ),

                    if (_errorMessage.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0x22FF2A6D),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFF2A6D)),
                        ),
                        child: Text(
                          _errorMessage,
                          style: const TextStyle(
                            color: Color(0xFFFF2A6D),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Action Button
                    _isValidating
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(12.0),
                              child: CircularProgressIndicator(color: Color(0xFF00FFCC)),
                            ),
                          )
                        : _isDeploying
                            ? Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF03060D),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFF00FFCC).withAlpha((255 * 0.4).round()),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF00FFCC).withAlpha((255 * 0.15).round()),
                                      blurRadius: 16,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Color(0xFF00FFCC),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'DOWNLOADING: ${(_deployProgress * 100).toStringAsFixed(1)}%',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 1.2,
                                                color: Color(0xFF00FFCC),
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          _totalBytes > 0
                                              ? '${(_receivedBytes / (1024 * 1024)).toStringAsFixed(2)} MB / ${(_totalBytes / (1024 * 1024)).toStringAsFixed(2)} MB'
                                              : 'Syncing...',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF94A3B8),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),

                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                        value: _deployProgress.clamp(0.0, 1.0),
                                        minHeight: 10,
                                        color: const Color(0xFF00FFCC),
                                        backgroundColor: const Color(0xFF1E293B),
                                      ),
                                    ),
                                    const SizedBox(height: 14),

                                    Row(
                                      children: [
                                        Expanded(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF090D16),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: const Color(0xFF1E293B)),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.bolt, color: Color(0xFFFFB800), size: 16),
                                                const SizedBox(width: 6),
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    const Text(
                                                      'SPEED',
                                                      style: TextStyle(
                                                        color: Color(0xFF64748B),
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.bold,
                                                        letterSpacing: 0.8,
                                                      ),
                                                    ),
                                                    Text(
                                                      _formatSpeed(_downloadSpeedBps),
                                                      style: const TextStyle(
                                                        color: Color(0xFFFFB800),
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w900,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF090D16),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: const Color(0xFF1E293B)),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.timer_outlined, color: Color(0xFF00FFCC), size: 16),
                                                const SizedBox(width: 6),
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    const Text(
                                                      'ESTIMATED TIME',
                                                      style: TextStyle(
                                                        color: Color(0xFF64748B),
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.bold,
                                                        letterSpacing: 0.8,
                                                      ),
                                                    ),
                                                    Text(
                                                      _formatEta(_etaSeconds),
                                                      style: const TextStyle(
                                                        color: Color(0xFF00FFCC),
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w900,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              )
                            : CyberButton(
                                text: 'AUTHENTICATE & DEPLOY',
                                onPressed: _activateAndDeploy,
                                gradientColors: const [Color(0xFF00FFCC), Color(0xFFBD00FF)],
                              ),
                  ],
                ),
              ),

              if (_consoleLogs.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text(
                  'LIVE ENGINE TERMINAL LOGS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 10),
                CyberConsole(logs: _consoleLogs),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
