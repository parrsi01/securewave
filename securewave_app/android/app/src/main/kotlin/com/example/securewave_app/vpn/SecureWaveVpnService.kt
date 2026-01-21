package com.example.securewave_app.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class SecureWaveVpnService : VpnService() {
  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    when (intent?.action) {
      ACTION_CONNECT -> {
        startForeground(NOTIFICATION_ID, buildNotification("SecureWave VPN", "Provisioning tunnel..."))
        stopSelf()
      }
      ACTION_DISCONNECT -> {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
      }
    }
    return Service.START_NOT_STICKY
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
    private const val NOTIFICATION_ID = 4201
  }
}
