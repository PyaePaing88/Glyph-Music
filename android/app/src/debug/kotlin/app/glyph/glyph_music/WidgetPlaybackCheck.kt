package app.glyph.glyph_music

import android.app.Instrumentation
import android.os.Bundle
import android.os.ParcelFileDescriptor

/** Exercises the real widget PendingIntent and verifies the system media session. */
class WidgetPlaybackCheck : Instrumentation() {
    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        start()
    }

    private fun isPlaying(): Boolean {
        val descriptor = uiAutomation.executeShellCommand("dumpsys media_session")
        val lines = ParcelFileDescriptor.AutoCloseInputStream(descriptor).bufferedReader().use { it.readLines() }
        val start = lines.indexOfFirst { it.trim() == "package=app.glyph.glyph_music" }
        if (start < 0) return false
        val state = lines.drop(start + 1).takeWhile { !it.trim().startsWith("package=") }
            .firstOrNull { it.contains("state=PlaybackState") } ?: return false
        return state.contains("state=PLAYING(3)") || state.contains("state=3,")
    }

    override fun onStart() {
        val report = Bundle()
        try {
            runOnMainSync { GlyphWidget().playback(targetContext, "play_pause", 100).send() }
            val deadline = System.currentTimeMillis() + 45000
            while (System.currentTimeMillis() < deadline && !isPlaying()) Thread.sleep(250)
            check(isPlaying()) { "Widget playback did not start. A valid local track is required." }
            runOnMainSync { GlyphWidget().playback(targetContext, "play_pause", 100).send() }
            report.putString("stream", "PASS: actual widget PendingIntent started a playing Glyph Music system media session from a fresh process. Sent pause after checking.\n")
            finish(-1, report)
        } catch (error: Throwable) {
            report.putString("stream", "FAIL: ${error.stackTraceToString()}\n")
            finish(0, report)
        }
    }
}
