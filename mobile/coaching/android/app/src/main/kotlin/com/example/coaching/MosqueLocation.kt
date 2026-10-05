package com.example.coaching

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** One-shot foreground location, explicit permission and bounded timeout. Never stores homes. */
class MosqueLocation(private val activity: Activity, messenger: BinaryMessenger) {
    private val manager = activity.getSystemService(Activity.LOCATION_SERVICE) as LocationManager
    private val handler = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private val listener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            finish(mapOf("lat" to location.latitude, "lng" to location.longitude, "accuracy" to location.accuracy.toDouble()))
        }
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
    }
    init {
        MethodChannel(messenger, "iqtadi/mosque_location").setMethodCallHandler { call, result ->
            when (call.method) {
                "current" -> {
                    if (pending != null) result.error("BUSY", "Location pending", null)
                    else {
                        pending = result
                        if (activity.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                            activity.requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), 714)
                        } else locate()
                    }
                }
                "navigate" -> {
                    val lat = call.argument<Number>("lat")?.toDouble()
                    val lng = call.argument<Number>("lng")?.toDouble()
                    if (lat == null || lng == null) result.error("POINT", "Invalid point", null)
                    else try {
                        activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$lat,$lng")))
                        result.success(null)
                    } catch (e: Exception) { result.error("MAPS", "No maps app available", null) }
                }
                else -> result.notImplemented()
            }
        }
    }
    fun permissionResult(code: Int): Boolean {
        if (code != 714) return false
        if (activity.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED) locate()
        else finish(null)
        return true
    }
    @Suppress("MissingPermission")
    private fun locate() {
        var requested = false
        try {
            for (provider in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
                if (provider == LocationManager.GPS_PROVIDER && activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) continue
                if (manager.isProviderEnabled(provider)) {
                    manager.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper())
                    requested = true
                }
            }
            if (!requested) finish(null)
            else handler.postDelayed({ finish(null) }, 10000)
        } catch (e: SecurityException) { finish(null) }
    }
    private fun finish(point: Map<String, Double>?) {
        val result = pending ?: return
        pending = null
        handler.removeCallbacksAndMessages(null)
        manager.removeUpdates(listener)
        if (point != null) result.success(point) else result.error("LOCATION", "Location unavailable; use manual point", null)
    }
    fun close() { finish(null) }
}
