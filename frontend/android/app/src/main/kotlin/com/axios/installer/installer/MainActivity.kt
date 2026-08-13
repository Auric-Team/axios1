package com.axios.installer.installer

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.content.pm.PackageManager
import rikka.shizuku.Shizuku
import java.io.BufferedReader
import java.io.InputStreamReader

class MainActivity : FlutterActivity() {
    private val LAUNCHER_CHANNEL = "com.axios.installer/launcher"
    private val SHIZUKU_CHANNEL = "com.axios.installer/shizuku"
    private val SHIZUKU_PERMISSION_CODE = 1001

    private val permissionListener = Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
        // Handle permission updates
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        try {
            Shizuku.addRequestPermissionResultListener(permissionListener)
        } catch (_: Exception) {}

        // 1. App Launcher Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LAUNCHER_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "launchApp") {
                val packageName = call.argument<String>("packageName")
                if (packageName != null) {
                    val intent = packageManager.getLaunchIntentForPackage(packageName)
                    if (intent != null) {
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } else {
                        result.error("UNAVAILABLE", "App not installed: $packageName", null)
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "Package name was null", null)
                }
            } else {
                result.notImplemented()
            }
        }

        // 2. Shizuku Channel for Non-Root Elevated ADB Operations
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHIZUKU_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isShizukuAvailable" -> {
                    try {
                        val available = Shizuku.pingBinder()
                        result.success(available)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "checkPermission" -> {
                    try {
                        if (!Shizuku.pingBinder()) {
                            result.success(false)
                        } else {
                            val isGranted = Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
                            result.success(isGranted)
                        }
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "requestPermission" -> {
                    try {
                        if (!Shizuku.pingBinder()) {
                            result.success(false)
                        } else if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) {
                            result.success(true)
                        } else {
                            Shizuku.requestPermission(SHIZUKU_PERMISSION_CODE)
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("SHIZUKU_ERROR", e.message, null)
                    }
                }
                "execCommand" -> {
                    val command = call.argument<String>("command")
                    if (command == null) {
                        result.error("INVALID_ARGUMENT", "Command parameter missing", null)
                        return@setMethodCallHandler
                    }

                    try {
                        if (!Shizuku.pingBinder()) {
                            result.error("NOT_AVAILABLE", "Shizuku service is not running on device.", null)
                            return@setMethodCallHandler
                        }
                        if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) {
                            result.error("PERMISSION_DENIED", "Shizuku permission has not been granted yet.", null)
                            return@setMethodCallHandler
                        }

                        val process = Shizuku.newProcess(arrayOf("sh", "-c", command), null, null)
                        val reader = BufferedReader(InputStreamReader(process.inputStream))
                        val errReader = BufferedReader(InputStreamReader(process.errorStream))

                        val output = StringBuilder()
                        var line: String?
                        while (reader.readLine().also { line = it } != null) {
                            output.append(line).append("\n")
                        }
                        while (errReader.readLine().also { line = it } != null) {
                            output.append(line).append("\n")
                        }

                        val exitCode = process.waitFor()
                        result.success(mapOf(
                            "exitCode" to exitCode,
                            "output" to output.toString().trim()
                        ))
                    } catch (e: Exception) {
                        result.error("EXEC_ERROR", "Failed to execute Shizuku command: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            Shizuku.removeRequestPermissionResultListener(permissionListener)
        } catch (_: Exception) {}
    }
}
