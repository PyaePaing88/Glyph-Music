package app.glyph.glyph_music

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import com.ryanheise.audioservice.AudioServicePlugin
import io.flutter.plugin.common.MethodChannel

/** Holds widget commands until Dart has restored the saved playback queue. */
class WidgetPlaybackService : Service() {
    private val pendingActions = mutableListOf<String>()
    private val handler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private val timeout = Runnable { stopSelf() }

    override fun onCreate() {
        super.onCreate()
        val channelId = "app.glyph.music.playback"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(channelId, "Glyph playback", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val open = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        // A widget tap may start us with no process or activity. Meet the foreground
        // deadline before loading Flutter, then let AudioService own playback.
        startForeground(1125, NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Glyph Music")
            .setContentText("Preparing playback")
            .setContentIntent(open)
            .setOngoing(true)
            .setSilent(true)
            .build())
        val engine = AudioServicePlugin.getFlutterEngine(this)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "glyph/widget_background").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeActions" -> {
                        val actions = pendingActions.toList()
                        pendingActions.clear()
                        result.success(actions)
                    }
                    "actionsComplete" -> {
                        result.success(null)
                        if (pendingActions.isEmpty()) stopSelf()
                    }
                    else -> result.notImplemented()
                }
            }
        }
        handler.postDelayed(timeout, 45000)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.getStringExtra("glyph_widget_action")
        if (action in listOf("play_pause", "previous", "next")) {
            pendingActions.add(action!!)
            channel?.invokeMethod("available", null)
        } else {
            stopSelf(startId)
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacks(timeout)
        channel?.setMethodCallHandler(null)
        channel = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}
