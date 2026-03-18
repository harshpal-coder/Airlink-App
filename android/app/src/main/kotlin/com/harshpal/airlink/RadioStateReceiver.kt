package com.harshpal.airlink

import android.bluetooth.BluetoothAdapter
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.WifiManager
import io.flutter.plugin.common.MethodChannel

/**
 * Native BroadcastReceiver that detects Bluetooth and WiFi state changes
 * and forwards events to Flutter via MethodChannel.
 */
class RadioStateReceiver(private val channel: MethodChannel) : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        when (intent?.action) {
            BluetoothAdapter.ACTION_STATE_CHANGED -> {
                val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
                when (state) {
                    BluetoothAdapter.STATE_ON -> channel.invokeMethod("onRadioStateChanged", mapOf("type" to "bluetooth", "enabled" to true))
                    BluetoothAdapter.STATE_OFF -> channel.invokeMethod("onRadioStateChanged", mapOf("type" to "bluetooth", "enabled" to false))
                }
            }
            WifiManager.WIFI_STATE_CHANGED_ACTION -> {
                val state = intent.getIntExtra(WifiManager.EXTRA_WIFI_STATE, WifiManager.WIFI_STATE_UNKNOWN)
                when (state) {
                    WifiManager.WIFI_STATE_ENABLED -> channel.invokeMethod("onRadioStateChanged", mapOf("type" to "wifi", "enabled" to true))
                    WifiManager.WIFI_STATE_DISABLED -> channel.invokeMethod("onRadioStateChanged", mapOf("type" to "wifi", "enabled" to false))
                }
            }
        }
    }

    companion object {
        fun createIntentFilter(): IntentFilter {
            return IntentFilter().apply {
                addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
                addAction(WifiManager.WIFI_STATE_CHANGED_ACTION)
            }
        }
    }
}
