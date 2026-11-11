package com.theo.syncbox

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var bytes: ByteArray? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "syncbox/links").setMethodCallHandler { call, result ->
            if (call.method != "open") { result.notImplemented(); return@setMethodCallHandler }
            try {
                val uri = Uri.parse(call.arguments as? String ?: "")
                if (uri.scheme?.lowercase() !in listOf("http", "https") || uri.host.isNullOrEmpty()) {
                    result.error("invalid", "无效链接", null)
                } else {
                    startActivity(Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE))
                    result.success(true)
                }
            } catch (e: Exception) { result.error("open", "无法打开链接", null) }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "syncbox/files").setMethodCallHandler { call, result ->
            if (call.method != "save") { result.notImplemented(); return@setMethodCallHandler }
            if (pending != null) { result.error("busy", "请先完成上次保存", null); return@setMethodCallHandler }
            val data = call.argument<ByteArray>("bytes")
            if (data == null) { result.error("invalid", "文件内容无效", null); return@setMethodCallHandler }
            pending = result; bytes = data
            try {
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/octet-stream"
                    putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "attachment")
                }
                startActivityForResult(intent, 7301)
            } catch (e: Exception) { pending = null; bytes = null; result.error("save", e.message, null) }
        }
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 7301) return
        val result = pending ?: return
        val payload = bytes
        pending = null; bytes = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || payload == null) { result.success(false); return }
        Thread {
            try {
                val output = contentResolver.openOutputStream(uri) ?: throw Exception("无法写入文件")
                output.use { it.write(payload) }
                runOnUiThread { result.success(true) }
            } catch (e: Exception) { runOnUiThread { result.error("save", e.message, null) } }
        }.start()
    }
}
