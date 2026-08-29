package com.miaogo.miaogo

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 暴露可执行的原生库目录（jniLibs 里的 libkatago.so 在此，目录可执行，
        // 而应用私有 files/ 目录被 SELinux/noexec 禁止 exec，见 AGENTS.md §8）。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "miaogo/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "nativeLibraryDir" -> result.success(applicationInfo.nativeLibraryDir)
                    else -> result.notImplemented()
                }
            }
    }
}
