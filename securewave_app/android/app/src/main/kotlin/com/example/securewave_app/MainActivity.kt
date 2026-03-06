package com.example.securewave_app

import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ResultReceiver
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private val channelName = "securewave/vpn"
  private val trafficChannelName = "securewave/traffic_stats"
  private val tunnelStatusChannelName = "securewave/tunnel_status"
  private var pendingResult: MethodChannel.Result? = null
  private var pendingConfig: String? = null
  private var pendingAction: String? = null

  private val vpnPermissionLauncher = registerForActivityResult(
    ActivityResultContracts.StartActivityForResult()
  ) { activityResult ->
    val result = pendingResult
    val action = pendingAction
    val config = pendingConfig
    pendingResult = null
    pendingAction = null
    pendingConfig = null
    if (activityResult.resultCode == RESULT_OK && action != null) {
      startVpnService(action, config, result)
    } else {
      result?.error("missing_vpn_permission", "VPN permission was denied.", null)
    }
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
      when (call.method) {
        "isAvailable" -> {
          result.success(true)
        }
        "connect" -> {
          val config = call.argument<String>("config").orEmpty()
          if (config.isEmpty()) {
            result.error("invalid_config", "Missing WireGuard configuration.", null)
            return@setMethodCallHandler
          }
          val prepareIntent = VpnService.prepare(this)
          if (prepareIntent != null) {
            if (pendingResult != null) {
              result.error("vpn_request_in_progress", "Another VPN request is in progress.", null)
              return@setMethodCallHandler
            }
            pendingResult = result
            pendingAction = vpn.SecureWaveVpnService.ACTION_CONNECT
            pendingConfig = config
            vpnPermissionLauncher.launch(prepareIntent)
            return@setMethodCallHandler
          }
          val intent = Intent(this, vpn.SecureWaveVpnService::class.java).apply {
            action = vpn.SecureWaveVpnService.ACTION_CONNECT
            putExtra(vpn.SecureWaveVpnService.EXTRA_CONFIG, config)
            putExtra(vpn.SecureWaveVpnService.EXTRA_RESULT_RECEIVER, buildResultReceiver(result))
          }
          startVpnServiceIntent(intent)
        }
        "disconnect" -> {
          val intent = Intent(this, vpn.SecureWaveVpnService::class.java).apply {
            action = vpn.SecureWaveVpnService.ACTION_DISCONNECT
            putExtra(vpn.SecureWaveVpnService.EXTRA_RESULT_RECEIVER, buildResultReceiver(result))
          }
          startVpnServiceIntent(intent)
        }
        else -> result.notImplemented()
      }
    }

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, trafficChannelName)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "getTrafficStats" -> result.success(vpn.SecureWaveVpnService.trafficStats())
          else -> result.notImplemented()
        }
      }

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, tunnelStatusChannelName)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "getTunnelStatus" -> result.success(vpn.SecureWaveVpnService.tunnelStatus())
          else -> result.notImplemented()
        }
      }
  }

  private fun startVpnService(action: String, config: String?, result: MethodChannel.Result?) {
    val intent = Intent(this, vpn.SecureWaveVpnService::class.java).apply {
      this.action = action
      if (!config.isNullOrBlank()) {
        putExtra(vpn.SecureWaveVpnService.EXTRA_CONFIG, config)
      }
      if (result != null) {
        putExtra(vpn.SecureWaveVpnService.EXTRA_RESULT_RECEIVER, buildResultReceiver(result))
      }
    }
    startVpnServiceIntent(intent)
  }

  private fun startVpnServiceIntent(intent: Intent) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      ContextCompat.startForegroundService(this, intent)
    } else {
      startService(intent)
    }
  }

  private fun buildResultReceiver(result: MethodChannel.Result): ResultReceiver {
    return object : ResultReceiver(Handler(Looper.getMainLooper())) {
      override fun onReceiveResult(resultCode: Int, resultData: Bundle?) {
        if (resultCode == 0) {
          result.success(null)
          return
        }
        val code = resultData?.getString("code") ?: "vpn_error"
        val message = resultData?.getString("message") ?: "VPN request failed."
        result.error(code, message, null)
      }
    }
  }
}
