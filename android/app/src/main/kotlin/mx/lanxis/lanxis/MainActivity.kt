package mx.lanxis.lanxis

import android.app.Activity
import android.Manifest
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.net.wifi.SoftApConfiguration
import android.net.wifi.rtt.RangingRequest
import android.net.wifi.rtt.RangingResult
import android.net.wifi.rtt.RangingResultCallback
import android.net.wifi.rtt.WifiRttManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.provider.Settings
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterFragmentActivity() {
    private data class PendingExport(val file: File, val result: MethodChannel.Result)
    private var pendingExport: PendingExport? = null
    private val exportLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { outcome ->
        val pending = pendingExport ?: return@registerForActivityResult
        pendingExport = null
        val uri = if (outcome.resultCode == Activity.RESULT_OK) outcome.data?.data else null
        if (uri == null) {
            pending.file.delete()
            pending.result.success(null)
        } else {
            Thread {
                try {
                    val output = contentResolver.openOutputStream(uri, "w")
                        ?: throw IllegalStateException("No se pudo abrir el documento seleccionado.")
                    output.use { destination -> pending.file.inputStream().use { it.copyTo(destination) } }
                    runOnUiThread { pending.result.success(uri.toString()) }
                } catch (error: Exception) {
                    runOnUiThread {
                        pending.result.error("save_failed", error.message, null)
                    }
                } finally {
                    pending.file.delete()
                }
            }.start()
        }
    }
    private var reservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var pendingStart: MethodChannel.Result? = null
    private var pendingDistance: Pair<String, MethodChannel.Result>? = null
    private data class PendingBle(
        val host: String,
        val token: ByteArray,
        val result: MethodChannel.Result
    )
    private var pendingBle: PendingBle? = null
    private var activeBleCancel: (() -> Unit)? = null
    private var beaconAdvertiser: BluetoothLeAdvertiser? = null
    private var beaconCallback: AdvertiseCallback? = null
    private var pendingBeaconStart: Pair<ByteArray, MethodChannel.Result>? = null
    private var beaconGeneration = 0
    private val permissionRequest = 9127
    private val distancePermissionRequest = 9128
    private val blePermissionRequest = 9129
    private val beaconPermissionRequest = 9130
    private val notificationPermissionRequest = 9131
    private var pendingNotificationPermission: MethodChannel.Result? = null
    private val beaconUuid = ParcelUuid.fromString("a7f58c20-ff3b-4f92-b11a-17f855bc6049")
    private val wifi: WifiManager by lazy {
        applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ParticipantControl.installChannel(applicationContext, flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mx.lanxis/notifications")
            .setMethodCallHandler { call, result ->
                if (call.method != "request") {
                    result.notImplemented()
                } else if (pendingNotificationPermission != null) {
                    result.error("busy", "Ya hay una solicitud de notificaciones en curso.", null)
                } else {
                    val missing = mutableListOf<String>()
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        missing.add(Manifest.permission.POST_NOTIFICATIONS)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                        packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)) {
                        for (permission in arrayOf(
                            Manifest.permission.BLUETOOTH_ADVERTISE,
                            Manifest.permission.BLUETOOTH_CONNECT
                        )) {
                            if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) {
                                missing.add(permission)
                            }
                        }
                    }
                    if (missing.isEmpty()) {
                        result.success(true)
                    } else {
                        pendingNotificationPermission = result
                        requestPermissions(missing.toTypedArray(), notificationPermissionRequest)
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mx.lanxis/hotspot")
            .setMethodCallHandler { call, result -> handle(call, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mx.lanxis/distance")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "measureToServer" -> measureDistance(
                        call.argument<String>("host") ?: "",
                        call.argument<String>("beaconToken"), result
                    )
                    "startBeacon" -> startBeacon(call.argument<String>("token"), result)
                    "stopBeacon" -> stopBeacon(result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mx.lanxis/export")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveDocument") {
                    result.notImplemented()
                } else if (pendingExport != null) {
                    result.error("busy", "Ya hay una exportación abierta.", null)
                } else {
                    val name = call.argument<String>("name")
                    val mime = call.argument<String>("mime")
                    val path = call.argument<String>("path")
                    val file = path?.let { File(it) }
                    val trustedFile = file != null && file.isFile &&
                        file.canonicalPath.startsWith(cacheDir.canonicalPath + File.separator)
                    if (name.isNullOrBlank() || mime.isNullOrBlank() || !trustedFile) {
                        result.error("invalid_export", "Faltan datos de exportación.", null)
                    } else {
                        pendingExport = PendingExport(file!!, result)
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = mime
                            putExtra(Intent.EXTRA_TITLE, name)
                        }
                        try {
                            exportLauncher.launch(intent)
                        } catch (error: Exception) {
                            pendingExport = null
                            file?.delete()
                            result.error("picker_failed", error.message, null)
                        }
                    }
                }
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
        val security: String
        if (active && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val config = reservation!!.softApConfiguration
            ssid = config.ssid
            passphrase = config.passphrase
            security = when (config.securityType) {
                SoftApConfiguration.SECURITY_TYPE_WPA3_SAE -> "SAE"
                SoftApConfiguration.SECURITY_TYPE_OPEN,
                SoftApConfiguration.SECURITY_TYPE_WPA3_OWE,
                SoftApConfiguration.SECURITY_TYPE_WPA3_OWE_TRANSITION -> "nopass"
                else -> "WPA"
            }
        } else if (active) {
            @Suppress("DEPRECATION")
            val config = reservation!!.wifiConfiguration
            ssid = config?.SSID
            passphrase = config?.preSharedKey
            security = "WPA"
        } else {
            ssid = null
            passphrase = null
            security = "WPA"
        }
        return mapOf(
            "supported" to supported,
            "active" to active,
            "ssid" to ssid,
            "passphrase" to passphrase,
            "security" to security,
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

    private fun decodeToken(value: String?): ByteArray? {
        if (value == null || !Regex("^[0-9a-fA-F]{12}$").matches(value)) return null
        return ByteArray(6) { index ->
            value.substring(index * 2, index * 2 + 2).toInt(16).toByte()
        }
    }

    private fun startBeacon(value: String?, result: MethodChannel.Result) {
        val token = decodeToken(value)
        if (token == null) {
            result.error("invalid_token", "Identificador BLE inválido.", null)
            return
        }
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)) {
            result.error("ble_unavailable", "Este teléfono no admite Bluetooth LE.", null)
            return
        }
        if (beaconCallback != null) {
            result.success(null)
            return
        }
        beaconGeneration++
        val missing = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            for (permission in arrayOf(
                Manifest.permission.BLUETOOTH_ADVERTISE,
                Manifest.permission.BLUETOOTH_CONNECT
            )) {
                if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) {
                    missing.add(permission)
                }
            }
        }
        if (missing.isNotEmpty()) {
            if (pendingBeaconStart != null) {
                result.error("busy", "Ya hay una solicitud de baliza BLE en curso.", null)
                return
            }
            pendingBeaconStart = Pair(token, result)
            requestPermissions(missing.toTypedArray(), beaconPermissionRequest)
        } else {
            beginBeacon(token, result)
        }
    }

    private fun beginBeacon(token: ByteArray, result: MethodChannel.Result) {
        try {
            val generation = beaconGeneration
            val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)
                ?.adapter
            val advertiser = adapter?.bluetoothLeAdvertiser
            if (advertiser == null) {
                result.error("ble_unavailable", "Activa Bluetooth; este teléfono no puede anunciar una baliza BLE.", null)
                return
            }
            val data = AdvertiseData.Builder()
                .addServiceData(beaconUuid, token)
                .setIncludeDeviceName(false)
                .build()
            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
                .setConnectable(false)
                .build()
            val callback = object : AdvertiseCallback() {
                override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                    if (generation != beaconGeneration) {
                        advertiser.stopAdvertising(this)
                        result.error("cancelled", "Baliza BLE cancelada.", null)
                        return
                    }
                    beaconAdvertiser = advertiser
                    beaconCallback = this
                    result.success(null)
                }
                override fun onStartFailure(errorCode: Int) {
                    beaconAdvertiser = null
                    beaconCallback = null
                    result.error("ble_advertise_failed",
                        "Android rechazó la baliza BLE (código $errorCode).", null)
                }
            }
            advertiser.startAdvertising(settings, data, callback)
        } catch (error: Exception) {
            result.error("ble_advertise_failed", error.message, null)
        }
    }

    private fun stopBeacon(result: MethodChannel.Result) {
        beaconGeneration++
        pendingBeaconStart?.second?.error("cancelled", "Baliza BLE cancelada.", null)
        pendingBeaconStart = null
        val callback = beaconCallback
        if (callback != null) {
            try { beaconAdvertiser?.stopAdvertising(callback) } catch (_: Exception) { }
        }
        beaconAdvertiser = null
        beaconCallback = null
        result.success(null)
    }

    private fun measureDistance(
        host: String,
        beaconToken: String?,
        result: MethodChannel.Result
    ) {
        val token = decodeToken(beaconToken)
        if (token == null ||
            !packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)) {
            measureToServer(host, result)
            return
        }
        val missing = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            for (permission in arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT
            )) {
                if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) {
                    missing.add(permission)
                }
            }
        }
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) !=
            PackageManager.PERMISSION_GRANTED) {
            missing.add(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        val request = PendingBle(host, token, result)
        if (missing.isNotEmpty()) {
            if (pendingBle != null) {
                unavailable(result, "Ya hay una medición Bluetooth en curso.")
                return
            }
            pendingBle = request
            requestPermissions(missing.toTypedArray(), blePermissionRequest)
        } else {
            scanBeacon(request)
        }
    }

    private fun scanBeacon(request: PendingBle) {
        try {
            val manager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val scanner = manager?.adapter?.bluetoothLeScanner
            if (scanner == null) {
                unavailable(request.result, "Activa Bluetooth para estimar la distancia al servidor.")
                return
            }
            val handler = Handler(Looper.getMainLooper())
            val done = AtomicBoolean(false)
            val samples = mutableListOf<Int>()
            lateinit var callback: ScanCallback
            val settings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build()
            var unfilteredStarted = false
            fun finish(reason: String?) {
                if (!done.compareAndSet(false, true)) return
                activeBleCancel = null
                try { scanner.stopScan(callback) } catch (_: Exception) { }
                if (samples.isEmpty()) {
                    if (packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_RTT)) {
                        measureToServer(request.host, request.result)
                    } else {
                        unavailable(request.result, reason ?:
                            "No se detectó la baliza Bluetooth del servidor. Acerca ambos equipos y comprueba Bluetooth.")
                    }
                    return
                }
                request.result.success(mapOf(
                    "source" to "ble_rssi_samples",
                    "rssi_samples_dbm" to samples.toList()
                ))
            }
            fun scanUnfiltered() {
                if (done.get() || unfilteredStarted) return
                unfilteredStarted = true
                try {
                    scanner.stopScan(callback)
                    scanner.startScan(null, settings, callback)
                    handler.postDelayed({ finish(null) }, 5000)
                } catch (error: Exception) {
                    finish("Bluetooth no pudo repetir la búsqueda: ${error.message}")
                }
            }
            callback = object : ScanCallback() {
                override fun onScanResult(callbackType: Int, result: ScanResult) {
                    val data = result.scanRecord?.getServiceData(beaconUuid)
                    if (data?.contentEquals(request.token) == true && result.rssi in -110..-20) {
                        handler.post {
                            if (!done.get()) {
                                samples.add(result.rssi)
                                if (samples.size >= 12) finish(null)
                            }
                        }
                    }
                }
                override fun onScanFailed(errorCode: Int) {
                    handler.post {
                        if (unfilteredStarted) {
                            finish("Bluetooth no pudo buscar balizas (código $errorCode).")
                        } else {
                            scanUnfiltered()
                        }
                    }
                }
            }
            val filter = ScanFilter.Builder()
                .setServiceData(beaconUuid, request.token)
                .build()
            scanner.startScan(listOf(filter), settings, callback)
            activeBleCancel = { finish("Medición Bluetooth interrumpida.") }
            handler.postDelayed({
                if (samples.size < 3) scanUnfiltered() else finish(null)
            }, 5000)
        } catch (error: SecurityException) {
            unavailable(request.result, "Sin permiso para buscar balizas Bluetooth: ${error.message}")
        } catch (error: Exception) {
            unavailable(request.result, "Bluetooth no pudo medir: ${error.message}")
        }
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
        if (requestCode == notificationPermissionRequest) {
            pendingNotificationPermission?.success(
                Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
            pendingNotificationPermission = null
            return
        }
        if (requestCode == beaconPermissionRequest) {
            val pending = pendingBeaconStart ?: return
            pendingBeaconStart = null
            if (grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
                beginBeacon(pending.first, pending.second)
            } else {
                pending.second.error("permission_denied",
                    "Permiso Bluetooth denegado para anunciar distancia.", null)
            }
            return
        }
        if (requestCode == blePermissionRequest) {
            val pending = pendingBle ?: return
            pendingBle = null
            if (grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
                scanBeacon(pending)
            } else {
                unavailable(pending.result,
                    "Permisos Bluetooth y ubicación precisa necesarios para estimar distancia.")
            }
            return
        }
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
        activeBleCancel?.invoke()
        activeBleCancel = null
        val callback = beaconCallback
        if (callback != null) {
            try { beaconAdvertiser?.stopAdvertising(callback) } catch (_: Exception) { }
        }
        beaconAdvertiser = null
        beaconCallback = null
        reservation?.close()
        reservation = null
        super.onDestroy()
    }
}
