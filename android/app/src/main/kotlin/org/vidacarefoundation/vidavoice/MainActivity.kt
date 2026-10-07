package org.vidacarefoundation.vidavoice

import android.os.Build
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerGeofenceChannel(flutterEngine)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (GeofenceLive.channel != null) GeofenceLive.channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /// Dart bridge for native safe-zone monitoring (see GeofenceBridge).
    /// Contract shared with the iOS implementation:
    /// - "syncRegions" {regions: [{id, lat, lng, radiusM}]} -> bool
    ///   (true when the OS monitor accepted the set)
    /// - "drainPending" -> [{zoneId, transition, ts}] observed while no
    ///   Dart engine was alive
    /// - "permissionStatus" -> "always"|"whenInUse"|"denied"|"unsupported"
    /// - "requestBackgroundPermission" -> status after the request
    /// Incoming "onTransition" calls push live transitions while the
    /// engine runs; every transition also lands in the native spill
    /// queue so nothing is lost across engine restarts. Never throws.
    private fun registerGeofenceChannel(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "vidavoice/geofence",
        )
        GeofenceLive.channel = channel
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "syncRegions" -> {
                        val raw = call.argument<List<Map<String, Any>>>("regions")
                            ?: emptyList()
                        val regions = raw.mapNotNull { m ->
                            val id = m["id"] as? String ?: return@mapNotNull null
                            val lat = (m["lat"] as? Number)?.toDouble()
                                ?: return@mapNotNull null
                            val lng = (m["lng"] as? Number)?.toDouble()
                                ?: return@mapNotNull null
                            val radius = (m["radiusM"] as? Number)?.toDouble()
                                ?: return@mapNotNull null
                            GeofenceNative.Region(id, lat, lng, radius)
                        }
                        GeofenceNative.saveRegions(this, regions)
                        result.success(
                            GeofenceNative.registerWithOs(this, regions),
                        )
                    }

                    "drainPending" ->
                        result.success(GeofenceNative.drainPending(this))

                    "permissionStatus" ->
                        result.success(GeofenceNative.permissionStatus(this))

                    "requestBackgroundPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(
                                    android.Manifest.permission.ACCESS_FINE_LOCATION,
                                    android.Manifest.permission.ACCESS_BACKGROUND_LOCATION,
                                ),
                                4207,
                            )
                        }
                        result.success(GeofenceNative.permissionStatus(this))
                    }

                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                // The Dart side treats any failure as "unsupported" and
                // falls back to in-app evaluation; never crash the bridge.
                result.success(false)
            }
        }
    }
}

/// Holds the live channel so the broadcast receiver can push
/// transitions while the engine runs. Process death clears it; the
/// native spill queue remains the durable delivery path.
object GeofenceLive {
    @Volatile
    var channel: MethodChannel? = null
}
