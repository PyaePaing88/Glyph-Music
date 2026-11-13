package app.glyph.glyph_music

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.media.audiofx.Visualizer
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.nothing.ketchum.Common
import com.nothing.ketchum.Glyph
import com.nothing.ketchum.GlyphManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlin.math.sqrt

/** Engine-owned so background playback does not depend on an Activity instance. */
class GlyphVisualizerPlugin : FlutterPlugin, ActivityAware, PluginRegistry.RequestPermissionsResultListener {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private var activityBinding: ActivityPluginBinding? = null
    private var permissionReply: MethodChannel.Result? = null
    private var manager: GlyphManager? = null
    private var connected = false
    private var registered = false
    private var sessionOpen = false
    private var enabled = false
    private var playing = false
    private var audioSession = 0
    private var visualizer: Visualizer? = null
    private var activeSession = 0
    private var smoothed = 0.0
    private var status = "off"
    private var connectionGeneration = 0
    private val handler = Handler(Looper.getMainLooper())
    private val connectionTimeout = Runnable {
        if (enabled && !connected) report("unavailable")
    }
    private val device: Pair<String, Int>?
        get() = when {
            Build.VERSION.SDK_INT < 34 -> null
            Common.is20111() -> Glyph.DEVICE_20111 to 15
            Common.is22111() -> Glyph.DEVICE_22111 to 33
            Common.is23111() -> Glyph.DEVICE_23111 to 26
            Common.is23113() -> Glyph.DEVICE_23113 to 26
            Common.is24111() -> Glyph.DEVICE_24111 to 36
            Common.is25111() -> Glyph.DEVICE_25111 to 6
            Common.is25131() -> Glyph.DEVICE_25131 to 4
            else -> null
        }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "glyph/visualizer")
        channel.setMethodCallHandler(::handle)
    }

    private fun report(value: String) {
        if (status == value) return
        status = value
        channel.invokeMethod("status", value)
    }

    private fun hasPermission() = context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setEnabled" -> {
                val requested = call.argument<Boolean>("enabled") == true
                if (!requested) {
                    enabled = false
                    stopLights()
                    handler.removeCallbacks(connectionTimeout)
                    report("off")
                    result.success(true)
                } else if (device == null) {
                    report("unsupported")
                    result.success(false)
                } else if (!hasPermission()) {
                    val activity = activityBinding?.activity
                    if (call.argument<Boolean>("requestPermission") == true && activity != null && permissionReply == null) {
                        permissionReply = result
                        activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 8431)
                    } else {
                        report("permission_required")
                        result.success(false)
                    }
                } else {
                    if (manager != null && !connected) {
                        connectionGeneration++
                        try { manager?.unInit() } catch (_: Exception) { }
                        manager = null
                    }
                    enabled = true
                    reconcile()
                    result.success(true)
                }
            }
            "updatePlayback" -> {
                // Never use session 0: that would capture other apps' audio.
                audioSession = call.argument<Int>("sessionId") ?: 0
                playing = call.argument<Boolean>("playing") == true
                reconcile()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun reconcile() {
        if (!enabled || !playing || audioSession <= 0) {
            stopLights()
            report(if (enabled) "ready" else "off")
            return
        }
        if (!hasPermission()) {
            stopLights()
            report("permission_required")
            return
        }
        if (manager == null) {
            report("connecting")
            val generation = ++connectionGeneration
            handler.removeCallbacks(connectionTimeout)
            handler.postDelayed(connectionTimeout, 5000)
            try {
                manager = GlyphManager.getInstance(context)
                manager?.init(object : GlyphManager.Callback {
                    override fun onServiceConnected(name: ComponentName) {
                        handler.post {
                            if (generation != connectionGeneration) return@post
                            handler.removeCallbacks(connectionTimeout)
                            connected = true
                            registered = try { manager?.register(device!!.first) == true } catch (_: Exception) { false }
                            if (!registered) report("authorization_required") else reconcile()
                        }
                    }
                    override fun onServiceDisconnected(name: ComponentName) {
                        handler.post {
                            if (generation != connectionGeneration) return@post
                            connected = false
                            registered = false
                            stopLights()
                            if (enabled) report("unavailable")
                        }
                    }
                })
            } catch (_: Exception) {
                report("unavailable")
            }
            return
        }
        if (!connected) return
        if (!registered) {
            registered = try { manager?.register(device!!.first) == true } catch (_: Exception) { false }
            if (!registered) { report("authorization_required"); return }
        }
        if (visualizer != null && activeSession == audioSession) return
        stopLights()
        try {
            manager?.openSession()
            sessionOpen = true
            val capture = Visualizer(audioSession)
            visualizer = capture
            capture.captureSize = 256
            capture.scalingMode = Visualizer.SCALING_MODE_AS_PLAYED
            capture.enabled = true
            activeSession = audioSession
            report("active")
            handler.post(frame)
        } catch (_: Exception) {
            stopLights()
            report("unavailable")
        }
    }

    private val samples = ByteArray(256)
    private val frame = object : Runnable {
        override fun run() {
            val capture = visualizer ?: return
            try {
                if (capture.getWaveForm(samples) != Visualizer.SUCCESS) throw IllegalStateException("Audio capture unavailable")
                val rms = sqrt(samples.sumOf { sample ->
                    val amplitude = ((sample.toInt() and 255) - 128) / 128.0
                    amplitude * amplitude
                } / samples.size)
                val level = ((rms - 0.015) * 4).coerceIn(0.0, 1.0)
                smoothed = if (level > smoothed) level else smoothed * 0.65
                val count = (smoothed * device!!.second).toInt()
                if (count == 0) manager?.turnOff() else {
                    val builder = manager!!.glyphFrameBuilder
                    for (index in 0 until count) builder.buildChannel(index)
                    manager?.toggle(builder.build())
                }
                handler.postDelayed(this, 40)
            } catch (_: Exception) {
                stopLights()
                report("unavailable")
            }
        }
    }

    private fun stopLights() {
        handler.removeCallbacks(frame)
        try { visualizer?.release() } catch (_: Exception) { }
        visualizer = null
        activeSession = 0
        smoothed = 0.0
        if (sessionOpen) {
            try { manager?.turnOff() } catch (_: Exception) { }
            try { manager?.closeSession() } catch (_: Exception) { }
            sessionOpen = false
        }
    }

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, grants: IntArray): Boolean {
        if (code != 8431) return false
        if (permissionReply == null) return true
        val granted = hasPermission()
        enabled = granted
        if (granted) reconcile() else report("permission_required")
        permissionReply?.success(granted)
        permissionReply = null
        return true
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }
    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        permissionReply?.success(false)
        permissionReply = null
    }
    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
    }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        connectionGeneration++
        enabled = false
        stopLights()
        try { manager?.unInit() } catch (_: Exception) { }
        handler.removeCallbacksAndMessages(null)
        channel.setMethodCallHandler(null)
        manager = null
    }
}
