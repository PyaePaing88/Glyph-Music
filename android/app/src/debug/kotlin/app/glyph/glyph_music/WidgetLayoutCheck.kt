package app.glyph.glyph_music

import android.app.Instrumentation
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.os.Bundle
import android.view.View
import android.widget.FrameLayout
import android.widget.RemoteViews
import android.widget.TextView
import java.io.File

/** Debug-only device check: inflate actual RemoteViews and render each size. */
class WidgetLayoutCheck : Instrumentation() {
    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        start()
    }

    override fun onStart() {
        val report = Bundle()
        var failure: Throwable? = null
        runOnMainSync {
            try {
                val context = targetContext
                val density = context.resources.displayMetrics.density
                val cases = listOf(
                    Triple("square", R.layout.glyph_widget_preview, Pair(140, 140)),
                    Triple("square-narrow", R.layout.glyph_widget_preview, Pair(120, 140)),
                    Triple("wide", R.layout.glyph_compact_preview, Pair(270, 140)),
                    Triple("tall", R.layout.glyph_tall_preview, Pair(140, 300))
                )
                for ((name, layout, size) in cases) {
                    val width = (size.first * density).toInt()
                    val height = (size.second * density).toInt()
                    val parent = FrameLayout(context)
                    val view = RemoteViews(context.packageName, layout).apply(context, parent)
                    parent.addView(view, FrameLayout.LayoutParams(width, height))
                    parent.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
                    parent.layout(0, 0, width, height)
                    check(view.findViewById<TextView>(R.id.track_title).text.toString() == "First Light")
                    for (id in listOf(R.id.widget_record, R.id.track_title, R.id.track_artist, R.id.play_pause, R.id.next_track, R.id.previous_track)) {
                        val child = view.findViewById<View>(id)
                        check(child.width > 0 && child.height > 0) { "$name contains an empty view: $id" }
                        var y = child.top
                        var x = child.left
                        var ancestor = child.parent
                        while (ancestor is View && ancestor !== parent) {
                            y += ancestor.top
                            x += ancestor.left
                            ancestor = ancestor.parent
                        }
                        check(y >= 0 && y + child.height <= height && x >= 0 && x + child.width <= width) { "$name has clipped content: $id" }
                    }
                    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    val canvas = Canvas(bitmap)
                    val wallpaper = Paint().apply {
                        shader = LinearGradient(0f, 0f, width.toFloat(), height.toFloat(), Color.rgb(75, 100, 140), Color.rgb(160, 95, 80), Shader.TileMode.CLAMP)
                    }
                    canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), wallpaper)
                    parent.draw(canvas)
                    File(context.externalCacheDir, "widget-$name.png").outputStream().use {
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
                    }
                    bitmap.recycle()
                }
                report.putString("stream", "PASS: four native RemoteViews sizes, populated text, artwork and controls; no clipped bounds.\n")
            } catch (error: Throwable) {
                failure = error
                report.putString("stream", "FAIL: ${error.stackTraceToString()}\n")
            }
        }
        finish(if (failure == null) -1 else 0, report)
    }
}
