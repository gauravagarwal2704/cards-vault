package com.cardswallet.cards_wallet.cardscan

import android.app.Activity
import android.content.Intent
import com.stripe.android.stripecardscan.cardscan.CARD_SCAN_RESULT_IMAGE_PATH
import com.stripe.android.stripecardscan.cardscan.CARD_SCAN_RESULT_PAN
import com.stripe.android.stripecardscan.cardscan.CARD_SCAN_RESULT_REASON
import com.stripe.android.stripecardscan.cardscan.CARD_SCAN_RESULT_SOURCE
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Launches the telemetry-free local CardScan activity for Flutter. */
class CardScanHandler(private val activity: Activity) :
    MethodChannel.MethodCallHandler,
    AutoCloseable {
    private var channel: MethodChannel? = null
    private var pendingResult: MethodChannel.Result? = null

    fun register(flutterEngine: FlutterEngine) {
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).also { it.setMethodCallHandler(this) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "scanCard") {
            result.notImplemented()
            return
        }
        if (pendingResult != null) {
            result.error("scan_in_progress", "A card scan is already running.", null)
            return
        }

        pendingResult = result
        try {
            activity.startActivityForResult(
                Intent().setClassName(activity, CARD_SCAN_ACTIVITY),
                REQUEST_CODE,
            )
        } catch (_: Exception) {
            pendingResult = null
            result.error("scan_unavailable", "The local card scanner could not start.", null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pendingResult ?: return true
        pendingResult = null

        val pan = data?.getStringExtra(CARD_SCAN_RESULT_PAN)
        val imagePath = data?.getStringExtra(CARD_SCAN_RESULT_IMAGE_PATH)
        if (resultCode == Activity.RESULT_OK &&
            (!pan.isNullOrBlank() || !imagePath.isNullOrBlank())
        ) {
            result.success(
                mapOf(
                    "status" to "completed",
                    "pan" to pan,
                    "imagePath" to imagePath,
                    "source" to data?.getStringExtra(CARD_SCAN_RESULT_SOURCE),
                ),
            )
        } else {
            result.success(
                mapOf(
                    "status" to "canceled",
                    "reason" to (data?.getStringExtra(CARD_SCAN_RESULT_REASON) ?: "closed"),
                ),
            )
        }
        return true
    }

    override fun close() {
        channel?.setMethodCallHandler(null)
        channel = null
        pendingResult?.error("scan_closed", "The card scanner was closed.", null)
        pendingResult = null
    }

    private companion object {
        const val CHANNEL = "cards_wallet/card_scan"
        const val REQUEST_CODE = 7301
        const val CARD_SCAN_ACTIVITY =
            "com.stripe.android.stripecardscan.cardscan.CardScanActivity"
    }
}
