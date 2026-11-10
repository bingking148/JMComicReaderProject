package app.jmcomic.reader.jm_comic_reader

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jmcomic/engine")
            .setMethodCallHandler { call, result ->
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
                    else -> result.notImplemented()
                }
            }
    }
}
