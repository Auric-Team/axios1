import 'package:flutter/material.dart';
import '../services/config_service.dart';
import '../services/download_service.dart';
import '../services/key_service.dart';
import '../services/detection_service.dart';
import '../services/launcher_service.dart';
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

  bool _isValidating = false;
  bool _isDeploying = false;
  bool _isCheckingUpdate = false;
  double _deployProgress = 0.0;
  String _errorMessage = '';
  final List<String> _consoleLogs = [];

  Map<String, dynamic>? _updateInfo;
  String _serverVersion = '1.0.0';

  @override
  void initState() {
    super.initState();
    _checkForUpdates();
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

      // Show update popup dialog automatically when version is available
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
                        const Text(
                          'NEW UPDATE AVAILABLE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.black,
                            letterSpacing: 1.5,
                            color: Color(0xFF00FFCC),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'libil2cpp.so Payload $version',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
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
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x3364748B)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'CHANGELOG / RELEASE NOTES',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                        ),
                        Text(
                          'Size: $size',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF00FFCC)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
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
      setState(() {
        _isDeploying = false;
        _errorMessage = 'Storage permission denied. Deployment aborted.';
      });
      _addLog('Error: Permission request rejected.');
      return;
    }
    _addLog('Storage permissions granted.');

    // 2. Paste key.txt to ALL 7 specified locations
    await _downloadService.deployKeyToTargetLocations(
      key: key,
      onLog: (log) => _addLog(log),
    );

    // 3. Scan Target Game Directory
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
    _addLog('Target directory detected: $gamePath');

    // 4. Resolve Destination Subpath
    final destPath = '$gamePath/${config.subpath}';
    _addLog('Resolved installation path: $destPath');

    // 5. Download and Deploy libil2cpp.so
    _addLog('Downloading latest libil2cpp.so binary payload from server...');
    final downloadSuccess = await _downloadService.downloadAndDeploy(
      backendUrl: config.backendUrl,
      targetPath: destPath,
      onProgress: (prog) {
        setState(() {
          _deployProgress = prog;
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

    _addLog('SUCCESS: libil2cpp.so & key.txt deployed cleanly!');
    _addLog('Booting target application...');

    // 6. Launch Target Game App
    final launched = await _launcherService.launchApp(targetPackage);
    if (!launched) {
      _addLog('Notice: Game launch initialized. You can also start it manually.');
    } else {
      _addLog('Game launched successfully!');
    }

    setState(() {
      _isDeploying = false;
      _keyController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x4400FFCC),
                        blurRadius: 24,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Color(0xFF090D16),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      size: 38,
                      color: Color(0xFF00FFCC),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'AXIOS INJECTOR CONTROL',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.black,
                    letterSpacing: 2.5,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Center(
                child: Text(
                  'Ultra-Smooth Automated libil2cpp.so & Key Deployment',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Main Activation Card
              CyberCard(
                borderGlowColors: const [Color(0x4400FFCC), Color(0x44BD00FF)],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'ENTER LICENSE KEY',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        if (_updateInfo != null)
                          GestureDetector(
                            onTap: () => _showUpdateDialog(_updateInfo!),
                            child: const Text(
                              'Update info',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00FFCC),
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Access Key Text Field
                    CyberTextField(
                      controller: _keyController,
                      label: 'AXIOS ACCESS KEY',
                      prefixIcon: Icons.vpn_key_outlined,
                      focusColor: const Color(0xFF00FFCC),
                      enabled: !_isValidating && !_isDeploying,
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
                            ? Column(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: _deployProgress,
                                      minHeight: 10,
                                      color: const Color(0xFF00FFCC),
                                      backgroundColor: const Color(0xFF1E293B),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'DEPLOYING PAYLOAD & KEYS: ${(_deployProgress * 100).toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                      color: Color(0xFF00FFCC),
                                    ),
                                  ),
                                ],
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
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 8),
                CyberConsole(
                  logs: _consoleLogs,
                  height: 180,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
