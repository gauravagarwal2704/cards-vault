package com.cardswallet.cards_vault

import android.Manifest
import android.app.ActivityManager
import android.content.Context
import android.content.ComponentName
import android.content.pm.PackageManager
import android.content.pm.PackageManager.NameNotFoundException
import android.content.res.Configuration
import android.content.Intent
import android.content.ClipData
import android.net.Uri
import android.os.Build
import android.os.StatFs
import android.os.SystemClock
import android.view.WindowManager
import androidx.core.content.FileProvider
import com.cardswallet.cards_vault.cardscan.CardScanHandler
import com.cardswallet.cards_vault.ocr.CardTextOcrHandler
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "cards_wallet/security"
    private val ICON_CHANNEL = "cards_wallet/app_icon"
    private val SUPPORT_CHANNEL = "cards_wallet/support"
    private val DIAGNOSTICS_CHANNEL = "cards_wallet/diagnostics"
    private var diagnosticsChannel: MethodChannel? = null
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
        diagnosticsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DIAGNOSTICS_CHANNEL
        )
        emitDiagnostic("Native engine configured", status = "success")
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableScreenshotPrevention" -> {
                    window.setFlags(
                        WindowManager.LayoutParams.FLAG_SECURE,
                        WindowManager.LayoutParams.FLAG_SECURE
                    )
                    emitDiagnostic("Screenshot prevention changed", status = "enabled")
                    result.success(true)
                }
                "disableScreenshotPrevention" -> {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    emitDiagnostic("Screenshot prevention changed", status = "disabled")
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
                emitDiagnostic("App icon changed", status = "success")
            } catch (_: NameNotFoundException) {
                emitDiagnostic("App icon change failed", code = "icon_components_missing")
                result.error(
                    "icon_components_missing",
                    "App icon resources are not installed. Reinstall CardVault and try again.",
                    null
                )
            } catch (error: Exception) {
                emitDiagnostic("App icon change failed", code = error.javaClass.simpleName)
                result.error(
                    "icon_change_failed",
                    error.message ?: "Could not change the app icon.",
                    null
                )
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SUPPORT_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceDetails" -> {
                    try {
                        val stat = StatFs(filesDir.path)
                        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        result.success(
                            mapOf(
                                "platform" to "Android",
                                "manufacturer" to Build.MANUFACTURER,
                                "model" to Build.MODEL,
                                "device" to Build.DEVICE,
                                "product" to Build.PRODUCT,
                                "osVersion" to Build.VERSION.RELEASE,
                                "sdkInt" to Build.VERSION.SDK_INT.toString(),
                                "supportedAbis" to Build.SUPPORTED_ABIS.joinToString(","),
                                "availableStorageBytes" to stat.availableBytes.toString(),
                                "lowRamDevice" to activityManager.isLowRamDevice.toString(),
                                "cameraPermission" to if (
                                    checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
                                ) "granted" else "not_granted",
                                "processUptimeMs" to SystemClock.elapsedRealtime().toString()
                            )
                        )
                        emitDiagnostic("Device details requested", status = "success")
                    } catch (error: Exception) {
                        emitDiagnostic("Device details request failed", code = error.javaClass.simpleName)
                        result.error(
                            "device_details_failed",
                            "Could not read device details.",
                            null
                        )
                    }
                }
                "composeEmail" -> composeSupportEmail(
                    recipient = call.argument<String>("recipient"),
                    subject = call.argument<String>("subject"),
                    body = call.argument<String>("body"),
                    attachmentPath = call.argument<String>("attachmentPath"),
                    result = result
                )
                else -> result.notImplemented()
            }
        }

        cardTextOcrHandler?.close()
        cardTextOcrHandler = CardTextOcrHandler(applicationContext) { event, status, code ->
            emitDiagnostic(event, status, code)
        }.also {
            it.register(flutterEngine)
        }
        cardScanHandler?.close()
        cardScanHandler = CardScanHandler(this) { event, status, code ->
            emitDiagnostic(event, status, code)
        }.also {
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
        emitDiagnostic("Native activity destroyed")
        cardScanHandler?.close()
        cardScanHandler = null
        cardTextOcrHandler?.close()
        cardTextOcrHandler = null
        diagnosticsChannel = null
        super.onDestroy()
    }

    private fun composeSupportEmail(
        recipient: String?,
        subject: String?,
        body: String?,
        attachmentPath: String?,
        result: MethodChannel.Result
    ) {
        emitDiagnostic("Support email composition started")
        if (recipient.isNullOrBlank()) {
            emitDiagnostic("Support email composition failed", code = "invalid_email")
            result.error("invalid_email", "Email recipient is missing.", null)
            return
        }

        val attachment = attachmentPath?.takeIf { it.isNotBlank() }?.let(::File)
        if (attachment != null && !attachment.exists()) {
            emitDiagnostic("Support email composition failed", code = "missing_attachment")
            result.error("missing_attachment", "The diagnostic log file was not found.", null)
            return
        }

        try {
            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_EMAIL, arrayOf(recipient))
                putExtra(Intent.EXTRA_SUBJECT, subject.orEmpty())
                putExtra(Intent.EXTRA_TEXT, body.orEmpty())
                if (attachment != null) {
                    val contentUri = FileProvider.getUriForFile(
                        this@MainActivity,
                        "$packageName.fileprovider",
                        attachment
                    )
                    putExtra(Intent.EXTRA_STREAM, contentUri)
                    clipData = ClipData.newRawUri("CardVault diagnostic logs", contentUri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            }

            val mailtoIntent = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:$recipient"))
            val defaultEmailPackage = packageManager.resolveActivity(
                mailtoIntent,
                PackageManager.MATCH_DEFAULT_ONLY
            )?.activityInfo?.packageName

            if (defaultEmailPackage != null) {
                sendIntent.setPackage(defaultEmailPackage)
            }

            if (sendIntent.resolveActivity(packageManager) != null) {
                startActivity(sendIntent)
            } else {
                sendIntent.setPackage(null)
                if (sendIntent.resolveActivity(packageManager) == null) {
                    emitDiagnostic("Support email composition failed", code = "email_unavailable")
                    result.error("email_unavailable", "No email app is installed.", null)
                    return
                }
                startActivity(Intent.createChooser(sendIntent, "Share CardVault logs"))
            }
            emitDiagnostic("Support email client opened", status = "success")
            result.success(true)
        } catch (error: Exception) {
            emitDiagnostic("Support email composition failed", code = error.javaClass.simpleName)
            result.error(
                "email_failed",
                error.message ?: "Could not open an email app.",
                null
            )
        }
    }

    private fun emitDiagnostic(
        event: String,
        status: String? = null,
        code: String? = null
    ) {
        diagnosticsChannel?.invokeMethod(
            "event",
            mapOf(
                "event" to event,
                "status" to status,
                "code" to code
            ).filterValues { it != null }
        )
    }
}
