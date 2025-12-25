package com.example.dispenserapp // <-- KENDİ PAKET İSMİNİZ!

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.dispenserapp/lock_check"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // İlk açılışta kilit ekranı ayarlarını yap
        configureLockScreen()
    }

    // Uygulama arka plandayken alarm çalarsa burası çalışır
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // TEKRAR ÇAĞIRMAMIZ LAZIM: "Ben hala kilit ekranı üzerinde görünmek istiyorum"
        configureLockScreen()
    }

    private fun configureLockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            // SADECE GÖSTER VE EKRANI AÇ. (KİLİDİ AÇMA EMRİ VERME!)
            setShowWhenLocked(true)
            setTurnScreenOn(true)

            // KeyguardManager.requestDismissKeyguard() BURADA ASLA ÇAĞRILMAMALI
            // Eğer çağrılırsa direkt şifre ekranı gelir.
        } else {
            // Eski cihazlar için
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "isDeviceLocked") {
                val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                result.success(keyguardManager.isKeyguardLocked)
            }
            else if (call.method == "bringToFront") {
                val intent = Intent(this, MainActivity::class.java)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                startActivity(intent)
                result.success(null)
            }
            else {
                result.notImplemented()
            }
        }
    }
}