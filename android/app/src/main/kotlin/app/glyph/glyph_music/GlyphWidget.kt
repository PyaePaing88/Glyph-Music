package app.glyph.glyph_music

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.ComponentName
import android.content.ComponentCallbacks
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.BitmapFactory
import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Shader
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

open class GlyphWidget : HomeWidgetProvider() {
    companion object {
        private var observingConfiguration = false

        private fun observeConfiguration(context: Context) {
            if (observingConfiguration) return
            observingConfiguration = true
            val application = context.applicationContext
            application.registerComponentCallbacks(object : ComponentCallbacks {
                override fun onConfigurationChanged(newConfig: Configuration) {
                    val manager = AppWidgetManager.getInstance(application)
                    val data = HomeWidgetPlugin.getData(application)
                    for (provider in listOf(GlyphCompactWidget(), GlyphMediumWidget(), GlyphLargeWidget())) {
                        val ids = manager.getAppWidgetIds(ComponentName(application, provider.javaClass))
                        if (ids.isNotEmpty()) provider.onUpdate(application, manager, ids, data)
                    }
                }

                override fun onLowMemory() {}
            })
        }

        fun publishPreviews(context: Context) {
            if (Build.VERSION.SDK_INT < 35) return
            val preferences = context.getSharedPreferences("glyph_widget_previews", Context.MODE_PRIVATE)
            if (preferences.getInt("revision", 0) == 7) return
            val manager = AppWidgetManager.getInstance(context)
            try {
                var accepted = true
                for ((provider, layout) in listOf(
                    GlyphCompactWidget::class.java to R.layout.glyph_compact_preview,
                    GlyphMediumWidget::class.java to R.layout.glyph_widget_preview,
                    GlyphLargeWidget::class.java to R.layout.glyph_tall_preview
                )) {
                    accepted = manager.setWidgetPreview(
                        ComponentName(context, provider),
                        AppWidgetProviderInfo.WIDGET_CATEGORY_HOME_SCREEN,
                        RemoteViews(context.packageName, layout)
                    ) && accepted
                }
                if (accepted) preferences.edit().putInt("revision", 7).apply()
            } catch (_: RuntimeException) {
                // Launcher quotas/support vary; XML and PNG previews remain available.
            }
        }
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        super.onAppWidgetOptionsChanged(context, manager, id, options)
        onUpdate(context, manager, intArrayOf(id), HomeWidgetPlugin.getData(context))
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray, data: SharedPreferences) {
        observeConfiguration(context)
        val mode = data.getString("themeMode", "system")
        // Decode once per broadcast; size variants share one bounded bitmap.
        val artwork = data.getString("artwork", "")
        val bitmap = if (!artwork.isNullOrEmpty()) {
            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(artwork, options)
            var sample = 1
            while (options.outWidth / sample > 256 || options.outHeight / sample > 256) sample *= 2
            options.inSampleSize = sample
            options.inJustDecodeBounds = false
            BitmapFactory.decodeFile(artwork, options)?.let { source ->
                val size = minOf(source.width, source.height)
                val circle = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
                val shader = BitmapShader(source, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
                shader.setLocalMatrix(Matrix().apply {
                    setTranslate((size - source.width) / 2f, (size - source.height) / 2f)
                })
                Canvas(circle).drawCircle(size / 2f, size / 2f, size / 2f,
                    Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply { this.shader = shader })
                source.recycle()
                circle
            }
        } else null

        val playing = data.getBoolean("playing", false)
        val density = context.resources.displayMetrics.density
        val buttonSize = (48 * density).toInt().coerceAtLeast(1)
        val playButton = Bitmap.createBitmap(buttonSize, buttonSize, Bitmap.Config.ARGB_8888)
        Canvas(playButton).apply buttonCanvas@ {
            scale(buttonSize / 48f, buttonSize / 48f)
            drawCircle(24f, 24f, 24f, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = data.getLong("accentColour", 0xffd71920L).toInt()
            })
            save()
            translate(12f, 12f)
            context.getDrawable(if (playing) R.drawable.widget_pause else R.drawable.widget_play)?.mutate()?.apply {
                setTint(data.getLong("accentForeground", 0xffffffffL).toInt())
                setBounds(0, 0, 24, 24)
                draw(this@buttonCanvas)
            }
            restore()
        }

        fun content(layout: Int): RemoteViews {
            val resolvedLayout = if (mode == "light" || mode == "dark") {
                when (layout) {
                    R.layout.glyph_compact -> R.layout.glyph_compact_explicit
                    R.layout.glyph_tall -> R.layout.glyph_tall_explicit
                    else -> R.layout.glyph_widget_explicit
                }
            } else layout
            val views = RemoteViews(context.packageName, resolvedLayout)
            // System colours remain resource references so the launcher can
            // resolve values-night even when the app process is not running.
            views.setImageViewResource(R.id.widget_surface, android.R.color.transparent)
            if (mode == "light" || mode == "dark") {
                val dark = mode == "dark"
                val primary = Color.parseColor(if (dark) "#F5F5F2" else "#181818")
                val secondary = Color.parseColor(if (dark) "#CECECC" else "#505050")
                views.setInt(R.id.widget_root, "setBackgroundResource",
                    if (dark) R.drawable.widget_background_dark else R.drawable.widget_background_light)
                views.setTextColor(R.id.track_title, primary)
                views.setTextColor(R.id.track_artist, secondary)
                views.setInt(R.id.previous_track, "setColorFilter", primary)
                views.setInt(R.id.next_track, "setColorFilter", primary)
                if (layout != R.layout.glyph_widget) views.setInt(R.id.widget_brand, "setColorFilter", secondary)
                if (layout == R.layout.glyph_tall) {
                    views.setTextColor(R.id.queue_shortcut, primary)
                    views.setTextColor(R.id.playlists_shortcut, primary)
                }
            }
            views.setTextViewText(R.id.track_title, data.getString("title", "Your music. Your space."))
            views.setTextViewText(R.id.track_artist, data.getString("artist", "Open Glyph Music to import music"))
            val playing = data.getBoolean("playing", false)
            views.setImageViewBitmap(R.id.play_pause, playButton)
            views.setInt(R.id.play_pause, "setBackgroundResource", android.R.color.transparent)
            views.setViewPadding(R.id.play_pause, 0, 0, 0, 0)
            views.setContentDescription(R.id.play_pause, if (playing) "Pause" else "Play")
            views.setOnClickPendingIntent(R.id.play_pause, playback(context, "play_pause", 100))
            views.setOnClickPendingIntent(R.id.next_track, playback(context, "next", 101))
            views.setOnClickPendingIntent(R.id.previous_track, playback(context, "previous", 102))
            fun open(route: String?, code: Int): PendingIntent {
                val intent = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    route?.let { putExtra("glyph_route", it) }
                }
                return PendingIntent.getActivity(context, code, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            }
            views.setOnClickPendingIntent(R.id.widget_root, open(null, 0))
            if (layout == R.layout.glyph_tall) {
                views.setOnClickPendingIntent(R.id.queue_shortcut, open("/queue", 1))
                views.setOnClickPendingIntent(R.id.playlists_shortcut, open("/playlists", 2))
            }
            views.setImageViewResource(R.id.widget_record, R.drawable.widget_album_placeholder)
            bitmap?.let { views.setImageViewBitmap(R.id.widget_record, it) }
            return views
        }

        for (id in ids) {
            val views = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                RemoteViews(mapOf(
                    SizeF(110f, 130f) to content(R.layout.glyph_widget),
                    SizeF(240f, 130f) to content(R.layout.glyph_compact),
                    SizeF(110f, 260f) to content(R.layout.glyph_tall)
                ))
            } else {
                val options = manager.getAppWidgetOptions(id)
                val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, if (this is GlyphCompactWidget) 270 else 140)
                val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, if (this is GlyphLargeWidget) 300 else 140)
                content(when {
                    width >= 240 -> R.layout.glyph_compact
                    height >= 260 -> R.layout.glyph_tall
                    else -> R.layout.glyph_widget
                })
            }
            manager.updateAppWidget(id, views)
        }
    }

    internal fun playback(context: Context, actionName: String, code: Int): PendingIntent {
        val intent = Intent(context, WidgetPlaybackService::class.java).apply {
            action = "app.glyph.glyph_music.widget.$actionName"
            putExtra("glyph_widget_action", actionName)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(context, code, intent, flags)
        } else {
            PendingIntent.getService(context, code, intent, flags)
        }
    }
}

// Keep receiver names stable so installed widgets survive an app update.
class GlyphCompactWidget : GlyphWidget()
class GlyphMediumWidget : GlyphWidget()
class GlyphLargeWidget : GlyphWidget()
