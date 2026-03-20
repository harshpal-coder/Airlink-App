package com.harshpal.airlink

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Bundle
import android.content.Intent
import android.view.WindowManager
import android.os.Build

class MainActivity : FlutterActivity() {
    private var radioStateReceiver: RadioStateReceiver? = null
    private val CHANNEL = "com.airlink/radio_state"
    private val FOREGROUND_CHANNEL = "com.airlink/foreground"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        
        // Register BroadcastReceiver for Bluetooth & WiFi state changes
        radioStateReceiver = RadioStateReceiver(channel)
        registerReceiver(radioStateReceiver, RadioStateReceiver.createIntentFilter())

        val foregroundChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FOREGROUND_CHANNEL)
        foregroundChannel.setMethodCallHandler { call, result ->
            if (call.method == "bringToForeground") {
                try {
                    val intent = Intent(this, MainActivity::class.java).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                    }
                    startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("FAILED", "Could not bring to foreground: ${e.message}", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        radioStateReceiver?.let {
            try { unregisterReceiver(it) } catch (_: Exception) {}
        }
        super.onDestroy()
    }
}
