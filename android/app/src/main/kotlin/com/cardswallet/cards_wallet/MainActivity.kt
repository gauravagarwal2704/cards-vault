package com.cardswallet.cards_wallet

import android.content.Context
import android.content.ComponentName
import android.content.pm.PackageManager
import android.content.pm.PackageManager.NameNotFoundException
import android.content.res.Configuration
import android.content.Intent
import android.view.WindowManager
import com.cardswallet.cards_wallet.cardscan.CardScanHandler
import com.cardswallet.cards_wallet.ocr.CardTextOcrHandler
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "cards_wallet/security"
    private val ICON_CHANNEL = "cards_wallet/app_icon"
    private var cardTextOcrHandler: CardTextOcrHandler? = null
    private var cardScanHandler: CardScanHandler? = null
    private val iconAliases = mapOf(
        "three_d" to "MainActivityThreeD",
        "purple" to "MainActivityPurple",
        "multicolor" to "MainActivityMulticolor",
        "ocean" to "MainActivityOcean",
        "emerald" to "MainActivityEmerald",
        "sunset" to "MainActivitySunset",
        "red" to "MainActivityRed"
    )

    override fun attachBaseContext(newBase: Context) {
        val preferences = newBase.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE
        )
        val savedMode = preferences.getString(
            "flutter.appearance_brightness_mode",
            "system"
        )
        val nightMode = when (savedMode) {
            "light" -> Configuration.UI_MODE_NIGHT_NO
            "dark", "amoled" -> Configuration.UI_MODE_NIGHT_YES
            else -> null
        }

        if (nightMode == null) {
            super.attachBaseContext(newBase)
            return
        }

        val configuration = Configuration(newBase.resources.configuration)
        configuration.uiMode =
            (configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or nightMode
        super.attachBaseContext(newBase.createConfigurationContext(configuration))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableScreenshotPrevention" -> {
                    window.setFlags(
                        WindowManager.LayoutParams.FLAG_SECURE,
                        WindowManager.LayoutParams.FLAG_SECURE
                    )
                    result.success(true)
                }
                "disableScreenshotPrevention" -> {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ICON_CHANNEL
        ).setMethodCallHandler { call, result ->
            if (call.method != "setAppIcon") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val iconId = call.argument<String>("iconId")
            if (iconId == null || !iconAliases.containsKey(iconId)) {
                result.error("invalid_icon", "Unknown app icon: $iconId", null)
                return@setMethodCallHandler
            }

            val aliasComponents = iconAliases.mapValues { (_, alias) ->
                ComponentName.createRelative(packageName, ".$alias")
            }

            try {
                aliasComponents.values.forEach { component ->
                    packageManager.getActivityInfo(
                        component,
                        PackageManager.MATCH_DISABLED_COMPONENTS
                    )
                }

                packageManager.setComponentEnabledSetting(
                    aliasComponents.getValue(iconId),
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                    PackageManager.DONT_KILL_APP
                )
                aliasComponents.forEach { (id, component) ->
                    if (id == iconId) return@forEach
                    packageManager.setComponentEnabledSetting(
                        component,
                        PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                        PackageManager.DONT_KILL_APP
                    )
                }
                result.success(true)
            } catch (_: NameNotFoundException) {
                result.error(
                    "icon_components_missing",
                    "App icon resources are not installed. Reinstall CardVault and try again.",
                    null
                )
            } catch (error: Exception) {
                result.error(
                    "icon_change_failed",
                    error.message ?: "Could not change the app icon.",
                    null
                )
            }
        }

        cardTextOcrHandler?.close()
        cardTextOcrHandler = CardTextOcrHandler(applicationContext).also {
            it.register(flutterEngine)
        }
        cardScanHandler?.close()
        cardScanHandler = CardScanHandler(this).also {
            it.register(flutterEngine)
        }
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (cardScanHandler?.onActivityResult(requestCode, resultCode, data) == true) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        cardScanHandler?.close()
        cardScanHandler = null
        cardTextOcrHandler?.close()
        cardTextOcrHandler = null
        super.onDestroy()
    }
}
