package mx.lanxis.lanxis

import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** The service owns the participant session; Activities may come and go. */
object ParticipantControl {
    const val extraBase = "base"
    const val extraCode = "code"
    private const val preferences = "lanxis_participant"
    private const val keyBase = "base"
    private const val keyCode = "code"

    fun save(context: Context, base: String, code: String) {
        context.getSharedPreferences(preferences, Context.MODE_PRIVATE).edit()
            .putString(keyBase, base).putString(keyCode, code).apply()
    }

    fun clear(context: Context) {
        context.getSharedPreferences(preferences, Context.MODE_PRIVATE).edit().clear().apply()
    }

    fun state(context: Context): Map<String, String>? {
        val prefs = context.getSharedPreferences(preferences, Context.MODE_PRIVATE)
        val base = prefs.getString(keyBase, null) ?: return null
        val code = prefs.getString(keyCode, null) ?: return null
        return mapOf(extraBase to base, extraCode to code)
    }

    fun start(context: Context, base: String, code: String) {
        require(base.startsWith("http://") && code.matches(Regex("^[0-9]{6}$"))) {
            "Dirección o código de servidor inválido."
        }
        val intent = Intent(context, ParticipantForegroundService::class.java).apply {
            putExtra(extraBase, base)
            putExtra(extraCode, code)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
        else context.startService(intent)
    }

    fun stop(context: Context) {
        clear(context)
        context.stopService(Intent(context, ParticipantForegroundService::class.java))
    }

    fun installChannel(context: Context, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "mx.lanxis/participant")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "start" -> {
                            start(context, call.argument<String>(extraBase) ?: "",
                                call.argument<String>(extraCode) ?: "")
                            result.success(null)
                        }
                        "stop" -> {
                            stop(context)
                            result.success(null)
                        }
                        "state" -> result.success(
                            if (ParticipantForegroundService.isRunning) state(context) else null
                        )
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("participant_service", error.message, null)
                }
            }
    }
}
