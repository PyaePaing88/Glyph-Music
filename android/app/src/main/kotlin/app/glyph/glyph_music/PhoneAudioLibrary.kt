package app.glyph.glyph_music

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.Settings
import android.util.Size
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Reads Android's shared audio index. Original files are never copied or changed. */
class PhoneAudioLibrary(private val activity: Activity) {
    private val worker = Executors.newSingleThreadExecutor()
    private var permissionReply: MethodChannel.Result? = null
    private val preferences = activity.getSharedPreferences("glyph_audio_access", 0)
    private val permission: String
        get() = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO
                else Manifest.permission.READ_EXTERNAL_STORAGE

    fun access(): String {
        if (activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) return "granted"
        return if (preferences.getBoolean("requested", false) &&
            !activity.shouldShowRequestPermissionRationale(permission)) "blocked" else "denied"
    }

    fun handle(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "access" -> result.success(access())
            "requestAccess" -> {
                if (access() == "granted") result.success("granted")
                else if (permissionReply != null) result.error("busy", "Audio permission is already being requested.", null)
                else {
                    permissionReply = result
                    preferences.edit().putBoolean("requested", true).apply()
                    activity.requestPermissions(arrayOf(permission), REQUEST_AUDIO)
                }
            }
            "openSettings" -> {
                activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:${activity.packageName}")))
                result.success(null)
            }
            "scan" -> {
                if (access() != "granted") {
                    result.error("audio_permission", "Allow audio access to scan phone storage.", null)
                    return
                }
                worker.execute {
                    try {
                        val tracks = query()
                        activity.runOnUiThread { result.success(tracks) }
                    } catch (error: Exception) {
                        activity.runOnUiThread { result.error("audio_scan", "Phone audio could not be scanned. Check audio access and retry.", null) }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    fun onPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_AUDIO) return false
        permissionReply?.success(access())
        permissionReply = null
        return true
    }

    fun close() { worker.shutdown() }

    internal fun query(): List<Map<String, Any?>> {
        val resolver = activity.contentResolver
        // The merged external volume also includes removable SD card audio.
        val collection = if (Build.VERSION.SDK_INT >= 29)
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
            else MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val columns = arrayOf("_id", "title", "_display_name", "artist", "album", "album_id",
            "duration", "_size", "date_added", "date_modified", "mime_type")
        val tracks = mutableListOf<Map<String, Any?>>()
        val covers = mutableMapOf<Long, String?>()
        // No IS_MUSIC or minimum-duration filter: include recordings and short audio too.
        val cursor = resolver.query(collection, columns, "_size > 0", null, "_id ASC")
            ?: throw IllegalStateException("Audio index unavailable")
        cursor.use {
            fun string(key: String) = it.getString(it.getColumnIndexOrThrow(key)) ?: ""
            fun number(key: String) = it.getLong(it.getColumnIndexOrThrow(key))
            while (it.moveToNext()) {
                val uri = ContentUris.withAppendedId(collection, number("_id"))
                val albumId = number("album_id")
                val modified = number("date_modified")
                val cover = if (covers.containsKey(albumId)) covers[albumId] else {
                    artwork(uri, albumId).also { path -> covers[albumId] = path }
                }
                fun tag(key: String, fallback: String): String = string(key).trim()
                    .takeIf { value -> value.isNotEmpty() && value != "<unknown>" } ?: fallback
                tracks.add(mapOf(
                    "uri" to uri.toString(),
                    "title" to tag("title", string("_display_name").substringBeforeLast('.')),
                    "artist" to tag("artist", "Unknown artist"),
                    "album" to tag("album", ""),
                    "durationMs" to number("duration"),
                    "bytes" to number("_size"),
                    "modified" to modified,
                    "added" to number("date_added"),
                    "mimeType" to string("mime_type"),
                    "artwork" to cover
                ))
            }
        }
        return tracks
    }

    private fun artwork(uri: Uri, albumId: Long): String? {
        if (albumId <= 0) return null
        val directory = File(activity.cacheDir, "phone_audio_art").apply { mkdirs() }
        val target = File(directory, "$albumId.jpg")
        if (target.exists() && target.length() > 0) return target.absolutePath
        return try {
            if (Build.VERSION.SDK_INT >= 29) {
                val image = activity.contentResolver.loadThumbnail(uri, Size(320, 320), null)
                try { target.outputStream().use { image.compress(Bitmap.CompressFormat.JPEG, 85, it) } }
                finally { image.recycle() }
            } else {
                val art = ContentUris.withAppendedId(Uri.parse("content://media/external/audio/albumart"), albumId)
                activity.contentResolver.openInputStream(art)?.use { input ->
                    target.outputStream().use { output -> input.copyTo(output) }
                }
            }
            target.takeIf { it.exists() && it.length() > 0 }?.absolutePath
        } catch (_: Exception) { target.delete(); null }
    }

    companion object { const val REQUEST_AUDIO = 7341 }
}
