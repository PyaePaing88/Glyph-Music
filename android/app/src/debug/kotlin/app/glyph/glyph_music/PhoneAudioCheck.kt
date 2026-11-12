package app.glyph.glyph_music

import android.app.Activity
import android.app.Instrumentation
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Bundle

/** Read-only verification against the phone's real MediaStore and content URIs. */
class PhoneAudioCheck : Instrumentation() {
    override fun onCreate(arguments: Bundle?) { super.onCreate(arguments); start() }
    override fun onStart() {
        val report = Bundle()
        var activity: Activity? = null
        var library: PhoneAudioLibrary? = null
        try {
            activity = startActivitySync(android.content.Intent(targetContext, MainActivity::class.java)
                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
            library = PhoneAudioLibrary(activity)
            check(library.access() == "granted") { "Audio permission must be granted before the device check." }
            val tracks = library.query()
            check(tracks.isNotEmpty()) { "No indexed shared audio exists on this phone." }
            check(tracks.map { it["uri"] }.toSet().size == tracks.size) { "Duplicate media URIs" }
            val sample = Uri.parse(tracks.first()["uri"] as String)
            targetContext.contentResolver.openInputStream(sample).use {
                check(it != null && it.read() >= 0) { "Scanned content URI is unreadable" }
            }
            val probe = MediaMetadataRetriever()
            val duration = try {
                probe.setDataSource(targetContext, sample)
                probe.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0
            } finally { probe.release() }
            check(duration > 0) { "Scanned audio has no decodable duration" }
            report.putString("stream", "PASS: ${tracks.size} phone audio files indexed with unique content URIs; sample readable and decodable ($duration ms). Originals unchanged.\n")
            finish(-1, report)
        } catch (error: Throwable) {
            report.putString("stream", "FAIL: ${error.stackTraceToString()}\n")
            finish(0, report)
        } finally { library?.close() }
    }
}
