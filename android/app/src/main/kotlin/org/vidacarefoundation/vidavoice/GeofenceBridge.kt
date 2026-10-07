package org.vidacarefoundation.vidavoice

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import org.json.JSONArray
import org.json.JSONObject

/// Native half of the Dart GeofencePlatform contract (channel
/// `vidavoice/geofence`).
///
/// Division of labor: Dart owns the family state (which zones exist,
/// whether they are enabled); native owns ONLY the OS registrations
/// and a durable spill queue. The region set is mirrored into native
/// SharedPreferences so [GeofenceBootReceiver] can re-register after a
/// reboot before Flutter ever starts, and transitions observed while
/// no engine is alive are persisted for Dart to drain on next launch.
/// Payloads here are strictly opaque zone ids + enter/exit + ts.
object GeofenceNative {
    const val PREFS = "vidavoice_geofence"
    private const val KEY_REGIONS = "regions"
    private const val KEY_PENDING = "pending"

    data class Region(val id: String, val lat: Double, val lng: Double, val radiusM: Double)

    fun saveRegions(context: Context, regions: List<Region>) {
        val arr = JSONArray()
        for (r in regions) {
            arr.put(JSONObject().apply {
                put("id", r.id)
                put("lat", r.lat)
                put("lng", r.lng)
                put("radiusM", r.radiusM)
            })
        }
        prefs(context).edit().putString(KEY_REGIONS, arr.toString()).apply()
    }

    fun loadRegions(context: Context): List<Region> {
        val raw = prefs(context).getString(KEY_REGIONS, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            val out = ArrayList<Region>()
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                out.add(
                    Region(
                        o.getString("id"),
                        o.getDouble("lat"),
                        o.getDouble("lng"),
                        o.getDouble("radiusM"),
                    ),
                )
            }
            out
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun appendPending(context: Context, zoneId: String, enter: Boolean, tsMs: Long) {
        val entry = JSONObject().apply {
            put("zoneId", zoneId)
            put("transition", if (enter) "enter" else "exit")
            put("ts", tsMs)
        }
        synchronized(this) {
            val arr = try {
                JSONArray(prefs(context).getString(KEY_PENDING, "[]"))
            } catch (_: Exception) {
                JSONArray()
            }
            arr.put(entry)
            // Cap the spill queue: a device offline from Flutter for a
            // very long time must not grow native prefs without bound.
            val trimmed = JSONArray()
            val start = maxOf(0, arr.length() - 200)
            for (i in start until arr.length()) trimmed.put(arr.get(i))
            prefs(context).edit().putString(KEY_PENDING, trimmed.toString()).apply()
        }
    }

    fun drainPending(context: Context): List<Map<String, Any>> {
        synchronized(this) {
            val raw = prefs(context).getString(KEY_PENDING, null) ?: return emptyList()
            prefs(context).edit().remove(KEY_PENDING).apply()
            return try {
                val arr = JSONArray(raw)
                val out = ArrayList<Map<String, Any>>()
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    out.add(
                        mapOf(
                            "zoneId" to o.getString("zoneId"),
                            "transition" to o.getString("transition"),
                            "ts" to o.getLong("ts"),
                        ),
                    )
                }
                out
            } catch (_: Exception) {
                emptyList()
            }
        }
    }

    /// Replaces the OS geofence set with [regions]. Needs fine location
    /// permission; returns false (Dart falls back to in-app evaluation)
    /// when permission or Play services is unavailable.
    fun registerWithOs(context: Context, regions: List<Region>): Boolean {
        if (ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.ACCESS_FINE_LOCATION,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        val client = LocationServices.getGeofencingClient(context)
        return try {
            client.removeGeofences(geofenceIntent(context))
            if (regions.isEmpty()) return true
            val fences = regions.take(100).map { r ->
                Geofence.Builder()
                    .setRequestId(r.id)
                    .setCircularRegion(r.lat, r.lng, r.radiusM.toFloat())
                    .setExpirationDuration(Geofence.NEVER_EXPIRE)
                    .setTransitionTypes(
                        Geofence.GEOFENCE_TRANSITION_ENTER or
                            Geofence.GEOFENCE_TRANSITION_EXIT,
                    )
                    .build()
            }
            val request = GeofencingRequest.Builder()
                .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
                .addGeofences(fences)
                .build()
            var ok = true
            val latch = java.util.concurrent.CountDownLatch(1)
            client.addGeofences(request, geofenceIntent(context))
                .addOnSuccessListener { latch.countDown() }
                .addOnFailureListener { ok = false; latch.countDown() }
            latch.await(5, java.util.concurrent.TimeUnit.SECONDS)
            ok
        } catch (_: SecurityException) {
            false
        } catch (_: Exception) {
            false
        }
    }

    private fun geofenceIntent(context: Context): PendingIntent {
        val intent = Intent(context, GeofenceBroadcastReceiver::class.java)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_MUTABLE
            } else {
                0
            }
        return PendingIntent.getBroadcast(context, 0, intent, flags)
    }

    fun permissionStatus(context: Context): String {
        val fine = ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        if (!fine) return "denied"
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return "always"
        val background = ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.ACCESS_BACKGROUND_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        return if (background) "always" else "whenInUse"
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}

/// Receives geofence transitions from the OS (including when the app
/// was dead). Transitions are persisted to the spill queue; Dart
/// drains them on launch and while running.
class GeofenceBroadcastReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val event = com.google.android.gms.location.GeofencingEvent.fromIntent(intent)
            ?: return
        if (event.hasError()) return
        val enter = when (event.geofenceTransition) {
            Geofence.GEOFENCE_TRANSITION_ENTER -> true
            Geofence.GEOFENCE_TRANSITION_EXIT -> false
            else -> return
        }
        val ts = System.currentTimeMillis()
        for (fence in event.triggeringGeofences ?: emptyList()) {
            GeofenceNative.appendPending(context, fence.requestId, enter, ts)
            // Best-effort live delivery while the engine runs; the
            // spill queue entry stays until Dart drains it, and the
            // Dart tracker ignores a transition that matches its
            // current state, so a drained duplicate can't re-alert.
            try {
                GeofenceLive.channel?.invokeMethod(
                    "onTransition",
                    mapOf(
                        "zoneId" to fence.requestId,
                        "transition" to if (enter) "enter" else "exit",
                        "ts" to ts,
                    ),
                )
            } catch (_: Exception) {
                // Engine gone — the queued entry is the delivery path.
            }
        }
    }
}

/// Re-registers the persisted region set after a device reboot
/// (Android drops all geofences at shutdown). Runs without Flutter.
class GeofenceBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val regions = GeofenceNative.loadRegions(context)
        if (regions.isNotEmpty()) {
            GeofenceNative.registerWithOs(context, regions)
        }
    }
}
