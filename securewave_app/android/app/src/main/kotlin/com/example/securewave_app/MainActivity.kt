package com.example.securewave_app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private val channelName = "securewave/vpn"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
      when (call.method) {
        "connect" -> {
          val config = call.argument<String>("config").orEmpty()
          if (config.isEmpty()) {
            result.error("invalid_config", "Missing WireGuard configuration.", null)
            return@setMethodCallHandler
          }
          val intent = Intent(this, vpn.SecureWaveVpnService::class.java).apply {
            action = vpn.SecureWaveVpnService.ACTION_CONNECT
            putExtra(vpn.SecureWaveVpnService.EXTRA_CONFIG, config)
          }
          startService(intent)
          result.success(null)
        }
        "disconnect" -> {
          val intent = Intent(this, vpn.SecureWaveVpnService::class.java).apply {
            action = vpn.SecureWaveVpnService.ACTION_DISCONNECT
          }
          startService(intent)
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }
  }
}
