package mx.lanxis.lanxis

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.Manifest
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.ParcelUuid
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/** Owns a user-started participant session after its Activity is removed. */
class ParticipantForegroundService : Service() {
    companion object {
        @Volatile var isRunning = false
            private set
    }
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var workerEngine: FlutterEngine? = null
    private var beaconAdvertiser: BluetoothLeAdvertiser? = null
    private var beaconCallback: AdvertiseCallback? = null
    private val beaconUuid = ParcelUuid.fromString("a7f58c20-ff3b-4f92-b11a-17f855bc6049")

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val base = intent?.getStringExtra(ParticipantControl.extraBase)
        val code = intent?.getStringExtra(ParticipantControl.extraCode)
        if (!base.isNullOrBlank() && !code.isNullOrBlank()) {
            ParticipantControl.save(this, base, code)
        }
        val session = ParticipantControl.state(this)
        if (session == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        val channelId = "lanxis_participant"
        val notifications = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notifications.createNotificationChannel(NotificationChannel(
                channelId, "Cliente LANXIS", NotificationManager.IMPORTANCE_LOW
            ))
        }
        val openApp = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, channelId) else Notification.Builder(this)
        val notification = builder
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle("LANXIS · cliente conectado")
            .setContentText("Conexión activa · esperando ensayos del servidor")
            .setSubText(session[ParticipantControl.extraBase])
            .setContentIntent(openApp)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(8040, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(8040, notification)
        }
        isRunning = true
        if (wakeLock == null) {
            wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "LANXIS:participant").apply {
                    setReferenceCounted(false)
                    acquire()
                }
        }
        if (wifiLock == null) {
            @Suppress("DEPRECATION")
            wifiLock = (applicationContext.getSystemService(WIFI_SERVICE) as WifiManager)
                .createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "LANXIS:participant").apply {
                    setReferenceCounted(false)
                    acquire()
                }
        }
        // This engine belongs solely to the foreground service. Closing or
        // reopening MainActivity cannot detach or destroy its network loop.
        if (workerEngine == null) startWorker()
        return START_REDELIVER_INTENT
    }

    private fun startWorker() {
        val engine = FlutterEngine(applicationContext)
        MethodChannel(engine.dartExecutor.binaryMessenger, "mx.lanxis/participant_worker")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "state" -> result.success(ParticipantControl.state(this))
                    else -> result.notImplemented()
                }
            }
        MethodChannel(engine.dartExecutor.binaryMessenger, "mx.lanxis/distance")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startBeacon" -> startBeacon(call.argument<String>("token"), result)
                    "stopBeacon" -> {
                        stopBeacon()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        workerEngine = engine
        val bundle = FlutterInjector.instance().flutterLoader().findAppBundlePath()
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(bundle, "participantBackgroundMain")
        )
    }

    private fun startBeacon(value: String?, result: MethodChannel.Result) {
        if (value == null || !Regex("^[0-9a-fA-F]{12}$").matches(value)) {
            result.error("invalid_token", "Identificador BLE inválido.", null)
            return
        }
        if (beaconCallback != null) {
            result.success(null)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            (checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE) != PackageManager.PERMISSION_GRANTED ||
             checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED)) {
            result.error("permission_denied", "Permisos Bluetooth necesarios para la baliza.", null)
            return
        }
        try {
            val adapter = (getSystemService(BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
            val advertiser = adapter?.bluetoothLeAdvertiser
            if (advertiser == null) {
                result.error("ble_unavailable", "Activa Bluetooth para estimar distancia.", null)
                return
            }
            val token = ByteArray(6) { index ->
                value.substring(index * 2, index * 2 + 2).toInt(16).toByte()
            }
            val data = AdvertiseData.Builder().addServiceData(beaconUuid, token)
                .setIncludeDeviceName(false).build()
            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
                .setConnectable(false).build()
            val callback = object : AdvertiseCallback() {
                override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                    beaconAdvertiser = advertiser
                    beaconCallback = this
                    result.success(null)
                }
                override fun onStartFailure(errorCode: Int) {
                    result.error("ble_advertise_failed",
                        "Android rechazó la baliza BLE (código $errorCode).", null)
                }
            }
            advertiser.startAdvertising(settings, data, callback)
        } catch (error: Exception) {
            result.error("ble_advertise_failed", error.message, null)
        }
    }

    private fun stopBeacon() {
        beaconCallback?.let { callback ->
            try { beaconAdvertiser?.stopAdvertising(callback) } catch (_: Exception) { }
        }
        beaconAdvertiser = null
        beaconCallback = null
    }

    override fun onDestroy() {
        isRunning = false
        stopBeacon()
        workerEngine?.destroy()
        workerEngine = null
        wifiLock?.let { if (it.isHeld) it.release() }
        wakeLock?.let { if (it.isHeld) it.release() }
        wifiLock = null
        wakeLock = null
        super.onDestroy()
    }
}
