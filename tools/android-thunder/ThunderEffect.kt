package poc.ringclick

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.media.AudioAttributes
import android.media.SoundPool
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.view.ViewGroup

/** Activity-only, non-interactive lightning overlay. BLE stays on its normal event loop. */
class ThunderEffect(context: Context, parent: ViewGroup) {
    private val handler = Handler(Looper.getMainLooper())
    private val view = BoltView(context)
    private val sound = SoundPool.Builder().setMaxStreams(1).setAudioAttributes(
        AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()).build()
    private var ready = false
    private val soundId: Int
    private var streamId = 0
    private var generation = 0
    init {
        parent.addView(view, ViewGroup.LayoutParams(-1, -1))
        view.visibility = View.GONE
        view.isClickable = false
        view.isFocusable = false
        view.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        sound.setOnLoadCompleteListener { _, _, status -> ready = status == 0 }
        soundId = sound.load(context, R.raw.thunder, 1)
    }
    fun whiteFlash() {
        val current = ++generation
        view.white = true
        view.bringToFront()
        view.alpha = 1f
        view.visibility = View.VISIBLE
        Log.i("PebbleWave", "receive-start white-flash")
        handler.postDelayed({ if (current == generation) view.visibility = View.GONE }, 100)
    }
    fun flash() {
        view.white = false
        val current = ++generation
        view.bringToFront()
        view.alpha = 1f
        view.visibility = View.VISIBLE
        if (ready) {
            sound.stop(streamId)
            streamId = sound.play(soundId, 1f, 1f, 1, 0, 1f)
        }
        Log.i("PebbleThunder", "flash pulses=2 sound=${streamId != 0}")
        floatArrayOf(0f, 1f, .35f, 0f).forEachIndexed { index, value ->
            handler.postDelayed({
                if (current == generation) {
                    view.alpha = value
                    if (index == 3) {
                        view.visibility = View.GONE
                        Log.i("PebbleThunder", "flash complete pulses=2")
                    }
                }
            }, (index + 1) * 55L)
        }
    }
    fun close() {
        generation++
        handler.removeCallbacksAndMessages(null)
        view.visibility = View.GONE
        sound.release()
        (view.parent as? ViewGroup)?.removeView(view)
    }
    private class BoltView(context: Context) : View(context) {
        var white = false
        private val paint = Paint().apply { color = Color.rgb(255, 245, 0) }
        private val points = arrayOf(.465f to .465f, 0f to .07f, 0f to .31f,
            .195f to .395f, .195f to .31f)
        override fun onDraw(canvas: Canvas) {
            if (white) { canvas.drawColor(Color.WHITE); return }
            canvas.drawColor(Color.argb(31, 255, 184, 0))
            for (mx in listOf(false, true)) for (my in listOf(false, true)) {
                val path = Path()
                points.forEachIndexed { i, (px, py) ->
                    val x = (if (mx) 1-px else px) * width
                    val y = (if (my) 1-py else py) * height
                    if (i == 0) path.moveTo(x,y) else path.lineTo(x,y)
                }
                path.close()
                canvas.drawPath(path, paint)
            }
        }
    }
}
