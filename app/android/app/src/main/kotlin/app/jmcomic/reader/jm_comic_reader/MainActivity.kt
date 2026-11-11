package app.jmcomic.reader.jm_comic_reader

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

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
                    "reveal" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        try {
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(Uri.fromFile(File(path)), "resource/folder")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (err: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
