package poc.ringclick

class DoubleTapDetector(private val intervalMs: Long = 450L) {
    private var pending: Long? = null
    fun reset() { pending = null }
    fun consume(clicks: Int, timeMs: Long): Boolean {
        if (clicks <= 0) return false
        if (clicks >= 2) { pending = null; return true }
        val previous = pending
        if (previous != null && timeMs >= previous && timeMs - previous <= intervalMs) {
            pending = null
            return true
        }
        pending = timeMs
        return false
    }
    companion object {
        fun selfTest() {
            val d = DoubleTapDetector()
            check(!d.consume(1, 1000))
            check(!d.consume(0, 1100))
            check(d.consume(1, 1300))
            check(!d.consume(1, 1400))
            check(!d.consume(1, 2000))
            check(d.consume(1, 2450))
            check(!d.consume(1, 3000))
            d.reset()
            check(!d.consume(1, 3100))
            check(d.consume(2, 4000))
            check(!d.consume(1, 4100))
        }
    }
}
