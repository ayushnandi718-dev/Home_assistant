package com.ayushnandi.aura_hub

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

private const val STORAGE_CHANNEL = "aura_hub/storage"

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAppDataDirectory" -> {
                        val directory = File(applicationContext.noBackupFilesDir, "aura_hub")
                        if (directory.exists() || directory.mkdirs()) {
                            result.success(directory.absolutePath)
                        } else {
                            result.error(
                                "APP_DATA_UNAVAILABLE",
                                "Could not create the AURA app data directory.",
                                null,
                            )
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
