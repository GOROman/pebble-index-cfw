package poc.ringclick

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.view.View
import android.util.Log
import kotlin.math.abs

class AudioWaveView(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var samples = ShortArray(0)
    private var label = "RECEIVING AUDIO…"
    fun receiving() {
        samples = ShortArray(0)
        label = "RECEIVING AUDIO…"
        visibility = VISIBLE
        invalidate()
    }
    fun showWav(wav: ByteArray) {
        // ClipDownload emits canonical mono PCM16 with a 44-byte header.
        require(wav.size >= 44 && String(wav.copyOfRange(0,4)) == "RIFF")
        samples = ShortArray((wav.size-44)/2) { i ->
            ((wav[44+i*2].toInt() and 255) or (wav[45+i*2].toInt() shl 8)).toShort()
        }
        label = "AUDIO  %.2f s  ·  8 kHz".format(samples.size/8000.0)
        visibility = VISIBLE
        invalidate()
        Log.i("PebbleWave", "waveform samples=${samples.size}")
    }
    override fun onDraw(c: Canvas) {
        c.drawColor(Color.rgb(3, 15, 12))
        paint.strokeWidth = 1f
        paint.color = Color.rgb(18, 60, 42)
        for (i in 0..8) c.drawLine(width*i/8f, 0f, width*i/8f, height.toFloat(), paint)
        for (i in 0..4) c.drawLine(0f, height*i/4f, width.toFloat(), height*i/4f, paint)
        paint.color = Color.rgb(95, 255, 155)
        paint.textSize = 13f * resources.displayMetrics.scaledDensity
        c.drawText(label, 12f, 24f * resources.displayMetrics.density, paint)
        val center = height*.58f
        paint.strokeWidth = 1.5f * resources.displayMetrics.density
        if (samples.isEmpty()) { c.drawLine(0f, center, width.toFloat(), center, paint); return }
        val peak = samples.maxOf { abs(it.toInt()) }.coerceAtLeast(2048)
        val amplitude = height*.29f/peak
        // Min/max per pixel preserves short transients when showing a complete clip.
        for (x in 0 until width) {
            val start = x.toLong()*samples.size/width
            val end = ((x+1L)*samples.size/width).coerceAtLeast(start+1).coerceAtMost(samples.size.toLong())
            var lo = 32767; var hi = -32768
            for (i in start.toInt() until end.toInt()) {
                val v = samples[i].toInt(); lo = minOf(lo,v); hi = maxOf(hi,v)
            }
            c.drawLine(x.toFloat(), center-hi*amplitude, x.toFloat(), center-lo*amplitude, paint)
        }
    }
}
