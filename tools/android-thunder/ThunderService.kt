package poc.ringclick

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.os.IBinder
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import android.widget.FrameLayout
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

class ThunderService : Service() {
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private lateinit var scanner: RingScanner
    private var overlay: FrameLayout? = null
    private var thunder: ThunderEffect? = null
    private var lastClicks = 0
    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel("pebble-thunder", "Pebble ring listener", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, ThunderService::class.java).setAction("STOP"), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(this, "pebble-thunder")
            .setSmallIcon(R.drawable.ic_ring).setContentTitle("Pebble Thunder — 常駐中")
            .setContentText("リングのクリックで雷を表示").setOngoing(true).setContentIntent(open)
            .addAction(Notification.Action.Builder(null, "停止", stop).build()).build()
        startForeground(41, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        scanner = RingScanner(this) { Log.i("PebbleThunderService", it) }
        scope.launch {
            scanner.state.collect { ring ->
                state.value = ring
                if (ring.kind == RingKind.CFW && ring.totalClicks > lastClicks) {
                    ensureOverlay()
                    if (thunder != null) {
                        Log.i("PebbleThunderService", "background click → system overlay")
                        thunder?.flash()
                    } else Log.i("PebbleThunderService", "click received; overlay permission required")
                }
                lastClicks = ring.totalClicks
            }
        }
        scanner.start(scope)
        ensureOverlay()
        Log.i("PebbleThunderService", "foreground BLE listener started")
    }
    private fun ensureOverlay() {
        if (!Settings.canDrawOverlays(this)) {
            if (overlay != null) removeOverlay()
            return
        }
        if (overlay != null) return
        val root = FrameLayout(this)
        val params = WindowManager.LayoutParams(-1, -1, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT).apply { alpha = .75f; title = "Pebble Thunder overlay" }
        try {
            getSystemService(WindowManager::class.java).addView(root, params)
            overlay = root
            thunder = ThunderEffect(this, root)
            Log.i("PebbleThunderService", "system overlay attached")
        } catch (e: Exception) { Log.w("PebbleThunderService", "overlay unavailable: ${e.javaClass.simpleName}") }
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP") {
            getSharedPreferences("thunder", 0).edit().putBoolean("enabled", false).apply()
            stopSelf(); return START_NOT_STICKY
        }
        getSharedPreferences("thunder", 0).edit().putBoolean("enabled", true).apply()
        ensureOverlay()
        if (intent?.action == "TEST") thunder?.flash()
        return START_STICKY
    }
    private fun removeOverlay() {
        thunder?.close(); thunder = null
        overlay?.let { try { getSystemService(WindowManager::class.java).removeView(it) } catch (_: Exception) {} }
        overlay = null
    }
    override fun onDestroy() {
        scanner.stop(); scope.cancel(); removeOverlay()
        state.value = RingState()
        Log.i("PebbleThunderService", "listener stopped")
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
    companion object {
        val state = MutableStateFlow(RingState())
        fun start(context: Context) {
            if (context.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED ||
                context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) return
            context.startForegroundService(Intent(context, ThunderService::class.java))
        }
    }
}

class ThunderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED &&
            context.getSharedPreferences("thunder", 0).getBoolean("enabled", false)) {
            try { ThunderService.start(context) }
            catch (e: Exception) { Log.w("PebbleThunderService", "Open app to resume after boot: ${e.javaClass.simpleName}") }
        }
    }
}
