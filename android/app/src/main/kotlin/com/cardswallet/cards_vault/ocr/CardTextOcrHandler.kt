package com.cardswallet.cards_vault.ocr

import android.content.Context
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Small still-image OCR bridge. Camera frames never cross this channel.
 *
 * The Flutter layer owns orientation, card cropping and preprocessing. Native
 * code only decodes the prepared JPEG and runs one serialized Tesseract pass.
 */
class CardTextOcrHandler(
    private val context: Context,
    private val diagnostic: (String, String?, String?) -> Unit = { _, _, _ -> },
) :
    MethodChannel.MethodCallHandler,
    AutoCloseable {
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val closed = AtomicBoolean(false)
    private var channel: MethodChannel? = null
    private var tesseract: TessBaseAPI? = null

    fun register(flutterEngine: FlutterEngine) {
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).also { it.setMethodCallHandler(this) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "recognizeImage") {
            result.notImplemented()
            return
        }
        if (closed.get()) {
            diagnostic("Native OCR rejected", null, "ocr_unavailable")
            result.error("ocr_unavailable", "OCR is shutting down.", null)
            return
        }

        val path = call.argument<String>("path")
        val profile = call.argument<String>("profile") ?: "general"
        if (path.isNullOrBlank()) {
            diagnostic("Native OCR rejected", null, "invalid_args")
            result.error("invalid_args", "Missing image path.", null)
            return
        }

        try {
            diagnostic("Native OCR requested", "started", profile)
            executor.execute {
                try {
                    val bitmap = BitmapFactory.decodeFile(path)
                        ?: error("The prepared OCR image could not be decoded.")
                    val payload = try {
                        val api = ensureTesseract()
                        configure(api, profile)
                        api.setImage(bitmap)
                        val text = api.getUTF8Text().orEmpty()
                        val confidence = api.meanConfidence().coerceIn(0, 100) / 100.0
                        api.clear()
                        mapOf(
                            "text" to text,
                            "confidence" to confidence,
                        )
                    } finally {
                        bitmap.recycle()
                    }
                    mainHandler.post {
                        if (!closed.get()) {
                            diagnostic("Native OCR completed", "success", profile)
                            result.success(payload)
                        }
                    }
                } catch (error: Exception) {
                    mainHandler.post {
                        if (!closed.get()) {
                            diagnostic(
                                "Native OCR failed",
                                null,
                                error.javaClass.simpleName,
                            )
                            result.error(
                                "ocr_failed",
                                "The prepared card image could not be read.",
                                null,
                            )
                        }
                    }
                }
            }
        } catch (_: RejectedExecutionException) {
            diagnostic("Native OCR rejected", null, "executor_closed")
            result.error("ocr_unavailable", "OCR is shutting down.", null)
        }
    }

    private fun ensureTesseract(): TessBaseAPI {
        tesseract?.let { return it }
        val dataRoot = File(context.filesDir, "card_text_ocr")
        val tessdata = File(dataRoot, "tessdata")
        val languageFile = File(tessdata, "eng.traineddata")
        if (!languageFile.exists()) {
            tessdata.mkdirs()
            context.assets.open(FLUTTER_TESSDATA_ASSET).use { input ->
                languageFile.outputStream().use { output -> input.copyTo(output) }
            }
        }

        return TessBaseAPI().also { api ->
            check(api.init(dataRoot.absolutePath, "eng", TessBaseAPI.OEM_LSTM_ONLY))
            api.setVariable("user_defined_dpi", "300")
            tesseract = api
        }
    }

    private fun configure(api: TessBaseAPI, profile: String) {
        api.setVariable("preserve_interword_spaces", "1")
        when (profile) {
            "digits", "expiry" -> {
                api.setPageSegMode(TessBaseAPI.PageSegMode.PSM_SPARSE_TEXT)
                api.setVariable("tessedit_char_whitelist", "0123456789 /-")
                api.setVariable("classify_bln_numeric_mode", "1")
            }
            "name" -> {
                api.setPageSegMode(TessBaseAPI.PageSegMode.PSM_SPARSE_TEXT)
                api.setVariable(
                    "tessedit_char_whitelist",
                    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz .'-",
                )
                api.setVariable("classify_bln_numeric_mode", "0")
            }
            else -> {
                api.setPageSegMode(TessBaseAPI.PageSegMode.PSM_SPARSE_TEXT)
                api.setVariable("tessedit_char_whitelist", "")
                api.setVariable("classify_bln_numeric_mode", "0")
            }
        }
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        channel?.setMethodCallHandler(null)
        channel = null
        try {
            executor.execute {
                tesseract?.recycle()
                tesseract = null
            }
            executor.shutdown()
        } catch (_: RejectedExecutionException) {
            tesseract?.recycle()
            tesseract = null
        }
    }

    companion object {
        const val CHANNEL = "cards_wallet/card_text_ocr"
        private const val FLUTTER_TESSDATA_ASSET = "tessdata/eng.traineddata"
    }
}
