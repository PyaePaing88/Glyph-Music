package app.glyph.glyph_music

import android.os.StatFs
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private lateinit var phoneAudio: PhoneAudioLibrary
    private val pendingPlayback = mutableListOf<String>()
    private var playbackChannel: MethodChannel? = null

    private fun collectPlayback(source: Intent?) {
        val action = source?.getStringExtra("glyph_widget_action") ?: return
        source.removeExtra("glyph_widget_action")
        if (action in listOf("play_pause", "previous", "next")) pendingPlayback.add(action)
    }

    override fun getInitialRoute(): String = intent?.getStringExtra("glyph_route") ?: "/"
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        collectPlayback(intent)
        playbackChannel?.invokeMethod("available", null)
        intent.getStringExtra("glyph_route")?.let { route ->
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, "glyph/navigation").invokeMethod("open", route)
            }
        }
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "glyph/background_playback")
            .setMethodCallHandler { call, result ->
                if (call.method == "openAppSettings") {
                    try {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName")))
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("settings_unavailable", "Could not open app settings", null)
                    }
                } else result.notImplemented()
            }
        phoneAudio = PhoneAudioLibrary(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "glyph/phone_audio")
            .setMethodCallHandler(phoneAudio::handle)
        GlyphWidget.publishPreviews(this)
        collectPlayback(intent)
        playbackChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "glyph/widget_playback").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "takeActions") {
                    collectPlayback(intent)
                    val actions = pendingPlayback.toList()
                    pendingPlayback.clear()
                    result.success(actions)
                } else result.notImplemented()
            }
        }
        playbackChannel?.invokeMethod("available", null)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "glyph/storage")
            .setMethodCallHandler { call, result ->
                if (call.method == "availableBytes") result.success(StatFs(filesDir.absolutePath).availableBytes)
                else result.notImplemented()
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (::phoneAudio.isInitialized) phoneAudio.onPermissionsResult(requestCode)
    }

    override fun onDestroy() {
        if (::phoneAudio.isInitialized) phoneAudio.close()
        super.onDestroy()
    }
}
