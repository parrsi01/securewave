package com.example.securewave_app.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.ResultReceiver
import androidx.core.app.NotificationCompat
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import java.io.StringReader
import java.util.concurrent.Executors

class SecureWaveVpnService : VpnService() {
  private val executor = Executors.newSingleThreadExecutor()
  private lateinit var backend: GoBackend
  private val tunnel = object : Tunnel {
    override fun getName(): String = "SecureWave"

    override fun onStateChange(newState: Tunnel.State) {
      currentState = newState
    }
  }
  @Volatile private var currentState = Tunnel.State.DOWN

  override fun onCreate() {
    super.onCreate()
    backend = GoBackend(this)
  }

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onDestroy() {
    executor.shutdown()
    super.onDestroy()
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    val action = intent?.action ?: return Service.START_NOT_STICKY
    val receiver = intent.getParcelableExtra<ResultReceiver>(EXTRA_RESULT_RECEIVER)
    when (action) {
      ACTION_CONNECT -> handleConnect(intent, receiver)
      ACTION_DISCONNECT -> handleDisconnect(receiver)
    }
    return Service.START_NOT_STICKY
  }

  private fun handleConnect(intent: Intent, receiver: ResultReceiver?) {
    val configText = intent.getStringExtra(EXTRA_CONFIG).orEmpty()
    if (configText.isBlank()) {
      sendError(receiver, "invalid_config", "Missing WireGuard configuration.")
      stopSelf()
      return
    }
    startForeground(NOTIFICATION_ID, buildNotification("SecureWave VPN", "Connecting..."))
    executor.execute {
      try {
        val config = Config.parse(StringReader(configText))
        backend.setState(tunnel, Tunnel.State.UP, config)
        currentState = Tunnel.State.UP
        updateNotification("SecureWave VPN", "Connected")
        sendSuccess(receiver)
      } catch (error: Exception) {
        sendError(
          receiver,
          "vpn_connect_failed",
          "WireGuard tunnel failed to start: ${error.message ?: "unknown error"}"
        )
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
      }
    }
  }

  private fun handleDisconnect(receiver: ResultReceiver?) {
    executor.execute {
      try {
        if (currentState != Tunnel.State.DOWN) {
          backend.setState(tunnel, Tunnel.State.DOWN, null)
          currentState = Tunnel.State.DOWN
        }
        sendSuccess(receiver)
      } catch (error: Exception) {
        sendError(
          receiver,
          "vpn_disconnect_failed",
          "WireGuard tunnel failed to stop: ${error.message ?: "unknown error"}"
        )
      } finally {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
      }
    }
  }

  private fun updateNotification(title: String, message: String) {
    val manager = getSystemService(NotificationManager::class.java)
    manager.notify(NOTIFICATION_ID, buildNotification(title, message))
  }

  private fun sendSuccess(receiver: ResultReceiver?) {
    receiver?.send(RESULT_SUCCESS, Bundle())
  }

  private fun sendError(receiver: ResultReceiver?, code: String, message: String) {
    val data = Bundle().apply {
      putString("code", code)
      putString("message", message)
    }
    receiver?.send(RESULT_ERROR, data)
  }

  private fun buildNotification(title: String, message: String): Notification {
    val channelId = "securewave_vpn"
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val channel = NotificationChannel(
        channelId,
        "SecureWave VPN",
        NotificationManager.IMPORTANCE_LOW
      )
      val manager = getSystemService(NotificationManager::class.java)
      manager.createNotificationChannel(channel)
    }
    return NotificationCompat.Builder(this, channelId)
      .setContentTitle(title)
      .setContentText(message)
      .setSmallIcon(android.R.drawable.presence_online)
      .setOngoing(true)
      .build()
  }

  companion object {
    const val ACTION_CONNECT = "com.example.securewave_app.vpn.CONNECT"
    const val ACTION_DISCONNECT = "com.example.securewave_app.vpn.DISCONNECT"
    const val EXTRA_CONFIG = "wireguard_config"
    const val EXTRA_RESULT_RECEIVER = "vpn_result_receiver"
    private const val NOTIFICATION_ID = 4201
    private const val RESULT_SUCCESS = 0
    private const val RESULT_ERROR = 1
  }
}
