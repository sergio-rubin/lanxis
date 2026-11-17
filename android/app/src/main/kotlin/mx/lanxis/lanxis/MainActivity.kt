package mx.lanxis.lanxis

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.net.wifi.rtt.RangingRequest
import android.net.wifi.rtt.RangingResult
import android.net.wifi.rtt.RangingResultCallback
import android.net.wifi.rtt.WifiRttManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var reservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var pendingStart: MethodChannel.Result? = null
    private var pendingDistance: Pair<String, MethodChannel.Result>? = null
    private val permissionRequest = 9127
    private val distancePermissionRequest = 9128
    private val wifi: WifiManager by lazy {
        applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mx.lanxis/hotspot")
            .setMethodCallHandler { call, result -> handle(call, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mx.lanxis/distance")
            .setMethodCallHandler { call, result ->
                if (call.method == "measureToServer") {
                    measureToServer(call.argument<String>("host") ?: "", result)
                } else result.notImplemented()
            }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(state())
            "start" -> start(result)
            "stop" -> {
                reservation?.close()
                reservation = null
                result.success(state())
            }
            "openWifiSettings" -> {
                startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun state(): Map<String, Any?> {
        val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI)
        val active = reservation != null
        val ssid: String?
        val passphrase: String?
        if (active && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val config = reservation!!.softApConfiguration
            ssid = config.ssid
            passphrase = config.passphrase
        } else if (active) {
            @Suppress("DEPRECATION")
            val config = reservation!!.wifiConfiguration
            ssid = config?.SSID
            passphrase = config?.preSharedKey
        } else {
            ssid = null
            passphrase = null
        }
        return mapOf(
            "supported" to supported,
            "active" to active,
            "ssid" to ssid,
            "passphrase" to passphrase,
            "reason" to if (supported) null else "El dispositivo no admite hotspot local desde aplicaciones."
        )
    }

    private fun start(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            !packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI)) {
            result.success(state())
            return
        }
        if (reservation != null) {
            result.success(state())
            return
        }
        if (pendingStart != null) {
            result.error("busy", "Ya existe una solicitud de hotspot en curso.", null)
            return
        }
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
            Manifest.permission.NEARBY_WIFI_DEVICES else Manifest.permission.ACCESS_FINE_LOCATION
        if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) {
            pendingStart = result
            requestPermissions(arrayOf(permission), permissionRequest)
            return
        }
        startWithPermission(result)
    }

    private fun startWithPermission(result: MethodChannel.Result) {
        try {
            wifi.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(newReservation: WifiManager.LocalOnlyHotspotReservation) {
                    reservation = newReservation
                    result.success(state())
                }
                override fun onStopped() {
                    reservation = null
                }
                override fun onFailed(reason: Int) {
                    result.error("hotspot_failed", "Android rechazó el hotspot local (código $reason).", reason)
                }
            }, Handler(Looper.getMainLooper()))
        } catch (error: SecurityException) {
            result.error("permission_denied", error.message, null)
        } catch (error: Exception) {
            result.error("hotspot_failed", error.message, null)
        }
    }

    private fun unavailable(result: MethodChannel.Result, reason: String) {
        result.success(mapOf("reason" to reason))
    }

    private fun measureToServer(host: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P ||
            !packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_RTT)) {
            unavailable(result, "Este teléfono no admite Wi-Fi RTT.")
            return
        }
        @Suppress("DEPRECATION")
        val gateway = wifi.dhcpInfo?.gateway ?: 0
        val gatewayIp = "${gateway and 255}.${gateway ushr 8 and 255}." +
            "${gateway ushr 16 and 255}.${gateway ushr 24 and 255}"
        if (gateway == 0 || host != gatewayIp) {
            unavailable(result, "El servidor no es el punto de acceso Wi-Fi; medir el router no daría la distancia al servidor.")
            return
        }
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) !=
            PackageManager.PERMISSION_GRANTED) {
            if (pendingDistance != null) {
                unavailable(result, "Ya hay una medición de distancia en curso.")
                return
            }
            pendingDistance = Pair(host, result)
            requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
                distancePermissionRequest)
            return
        }
        rangeAccessPoint(result)
    }

    private fun rangeAccessPoint(result: MethodChannel.Result) {
        try {
            val rtt = getSystemService(Context.WIFI_RTT_RANGING_SERVICE) as? WifiRttManager
            if (rtt == null || !rtt.isAvailable) {
                unavailable(result, "Wi-Fi RTT no está disponible; activa ubicación y Wi-Fi.")
                return
            }
            @Suppress("DEPRECATION")
            val bssid = wifi.connectionInfo?.bssid
            val ap = wifi.scanResults.firstOrNull {
                it.BSSID.equals(bssid, ignoreCase = true) && it.is80211mcResponder
            }
            if (ap == null) {
                unavailable(result, "El punto de acceso conectado no anuncia Wi-Fi RTT (802.11mc).")
                return
            }
            val request = RangingRequest.Builder().addAccessPoint(ap).build()
            rtt.startRanging(request, mainExecutor, object : RangingResultCallback() {
                override fun onRangingFailure(code: Int) {
                    unavailable(result, "Wi-Fi RTT no pudo medir (código $code).")
                }
                override fun onRangingResults(results: MutableList<RangingResult>) {
                    val sample = results.firstOrNull {
                        it.status == RangingResult.STATUS_SUCCESS
                    }
                    if (sample == null) {
                        unavailable(result, "El punto de acceso no devolvió una distancia válida.")
                    } else {
                        result.success(mapOf(
                            "distance_m" to sample.distanceMm / 1000.0,
                            "uncertainty_m" to sample.distanceStdDevMm / 1000.0,
                            "source" to "wifi_rtt_ap"
                        ))
                    }
                }
            })
        } catch (error: SecurityException) {
            unavailable(result, "Sin permiso de ubicación precisa para Wi-Fi RTT.")
        } catch (error: Exception) {
            unavailable(result, error.message ?: "Wi-Fi RTT no disponible.")
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == distancePermissionRequest) {
            val pending = pendingDistance ?: return
            pendingDistance = null
            if (grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                rangeAccessPoint(pending.second)
            } else {
                unavailable(pending.second, "Permiso de ubicación precisa denegado.")
            }
            return
        }
        if (requestCode != permissionRequest) return
        val result = pendingStart ?: return
        pendingStart = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            startWithPermission(result)
        } else {
            result.error("permission_denied", "Permiso Wi-Fi denegado. Usa la configuración del sistema.", null)
        }
    }

    override fun onDestroy() {
        reservation?.close()
        reservation = null
        super.onDestroy()
    }
}
