package com.dantech.pdf_utils

import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "pdf_utils/content",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "readContentUri" -> {
                    val uriString = call.argument<String>("uri")
                    if (uriString == null) {
                        result.error("BAD_ARGS", "uri missing", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = Uri.parse(uriString)
                        val input = contentResolver.openInputStream(uri)
                        if (input == null) {
                            result.error("OPEN_FAILED", "cannot open uri", null)
                            return@setMethodCallHandler
                        }
                        val out = File(
                            cacheDir,
                            "scan_${System.currentTimeMillis()}.pdf",
                        )
                        input.use { ins ->
                            out.outputStream().use { outs -> ins.copyTo(outs) }
                        }
                        result.success(out.absolutePath)
                    } catch (e: Exception) {
                        result.error("READ_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
