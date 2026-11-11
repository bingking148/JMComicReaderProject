package app.jmcomic.reader.jm_comic_reader

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var volumeTurns = false
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jmcomic/engine")
        channel = messenger
        messenger.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val dir = call.argument<String>("dataDir")
                    if (dir.isNullOrEmpty()) {
                        result.error("engine", "缺少数据目录", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val port = jmengine.Jmengine.start(dir)
                        result.success(port.toInt())
                    } catch (err: Exception) {
                        result.error("engine", err.message, null)
                    }
                }
                "volumeTurns" -> {
                    volumeTurns = call.argument<Boolean>("enabled") == true
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (volumeTurns && event.action == KeyEvent.ACTION_DOWN) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_VOLUME_UP -> {
                    channel?.invokeMethod("volume", "prev")
                    return true
                }
                KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    channel?.invokeMethod("volume", "next")
                    return true
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }
}
