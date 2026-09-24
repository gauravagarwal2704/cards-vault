package com.stripe.android.stripecardscan.cardscan

import android.annotation.SuppressLint
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.graphics.PointF
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Size
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.Toast
import androidx.activity.addCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.RestrictTo
import androidx.lifecycle.lifecycleScope
import com.stripe.android.camera.CameraPreviewImage
import com.stripe.android.camera.scanui.ScanErrorListener
import com.stripe.android.camera.scanui.ScanState
import com.stripe.android.camera.scanui.SimpleScanStateful
import com.stripe.android.camera.scanui.ViewFinderBackground
import com.stripe.android.camera.scanui.util.asRect
import com.stripe.android.camera.scanui.util.setDrawable
import com.stripe.android.camera.scanui.util.startAnimation
import com.stripe.android.stripecardscan.R
import com.stripe.android.stripecardscan.camera.getScanCameraAdapter
import com.stripe.android.stripecardscan.cardscan.result.MainLoopAggregator
import com.stripe.android.stripecardscan.cardscan.result.MainLoopState
import com.stripe.android.stripecardscan.databinding.StripeActivityCardscanBinding
import com.stripe.android.stripecardscan.payment.ml.SSDOcr
import com.stripe.android.stripecardscan.payment.ml.SSDOcrModelManager
import com.stripe.android.stripecardscan.scanui.CancellationReason
import com.stripe.android.stripecardscan.scanui.ScanActivity
import com.stripe.android.stripecardscan.scanui.ScanResultListener
import com.stripe.android.stripecardscan.scanui.util.getColorByRes
import com.stripe.android.stripecardscan.scanui.util.hide
import com.stripe.android.stripecardscan.scanui.util.setVisible
import com.stripe.android.stripecardscan.scanui.util.show
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max
import kotlin.math.roundToInt

const val CARD_SCAN_RESULT_PAN = "cards_wallet.cardscan.pan"
const val CARD_SCAN_RESULT_IMAGE_PATH = "cards_wallet.cardscan.image_path"
const val CARD_SCAN_RESULT_REASON = "cards_wallet.cardscan.reason"
const val CARD_SCAN_RESULT_SOURCE = "cards_wallet.cardscan.source"

private val MINIMUM_RESOLUTION = Size(1067, 600) // minimum size of OCR

@RestrictTo(RestrictTo.Scope.LIBRARY_GROUP)
sealed class CardScanState(isFinal: Boolean) : ScanState(isFinal) {
    data object NotFound : CardScanState(isFinal = false)
    data object Found : CardScanState(isFinal = false)
    data object Correct : CardScanState(isFinal = true)
}

internal class CardScanActivity : ScanActivity(), SimpleScanStateful<CardScanState> {

    private var sessionTimeoutJob: Job? = null
    private var galleryImportJob: Job? = null
    private var isGalleryPickerOpen = false
    private var isImportingGallery = false

    private val galleryPicker = registerForActivityResult(
        ActivityResultContracts.GetContent()
    ) { uri ->
        isGalleryPickerOpen = false
        if (uri != null) {
            importGalleryImage(uri)
        } else {
            viewBinding.galleryButton.isEnabled = true
            viewBinding.galleryButton.alpha = 1f
            scanFlow.resetFlow()
            changeScanState(CardScanState.NotFound)
            lifecycleScope.launch {
                onCameraStreamAvailable(cameraAdapter.getImageStream())
            }
        }
    }

    override val minimumAnalysisResolution = MINIMUM_RESOLUTION

    private val viewBinding by lazy {
        StripeActivityCardscanBinding.inflate(layoutInflater)
    }

    override val previewFrame: ViewGroup by lazy {
        viewBinding.cameraView.previewFrame
    }

    private val viewFinderWindow: View by lazy {
        viewBinding.cameraView.viewFinderWindowView
    }

    private val viewFinderBorder: ImageView by lazy {
        viewBinding.cameraView.viewFinderBorderView
    }

    private val viewFinderBackground: ViewFinderBackground by lazy {
        viewBinding.cameraView.viewFinderBackgroundView
    }

    override var scanState: CardScanState? = CardScanState.NotFound

    override var scanStatePrevious: CardScanState? = null

    override val scanErrorListener: ScanErrorListener = ScanErrorListener()

    override val cameraAdapterBuilder = ::getScanCameraAdapter

    /**
     * The listener which handles results from the scan.
     */
    override val resultListener: ScanResultListener =
        object : ScanResultListener {
            override fun userCanceled(reason: CancellationReason) {
                val intent = Intent()
                    .putExtra(CARD_SCAN_RESULT_REASON, reason.javaClass.simpleName)
                setResult(RESULT_CANCELED, intent)
            }

            override fun failed(cause: Throwable?) {
                val intent = Intent()
                    .putExtra(CARD_SCAN_RESULT_REASON, cause?.javaClass?.simpleName ?: "scan_failed")
                setResult(RESULT_CANCELED, intent)
            }
        }

    /**
     * The flow used to scan an item.
     */
    private val scanFlow: CardScanFlow by lazy {
        object : CardScanFlow(scanErrorListener) {
            /**
             * A final result was received from the aggregator. Set the result from this activity.
             */
            override suspend fun onResult(
                result: MainLoopAggregator.FinalResult
            ) {
                try {
                    withContext(Dispatchers.Main) {
                        if (isImportingGallery || isGalleryPickerOpen) {
                            return@withContext
                        }
                        sessionTimeoutJob?.cancel()
                        changeScanState(CardScanState.Correct)
                        cameraAdapter.unbindFromLifecycle(this@CardScanActivity)
                        val imagePath = saveAcceptedFrame(result.acceptedFrame)
                        val intent = Intent()
                            .putExtra(CARD_SCAN_RESULT_PAN, result.pan)
                            .putExtra(CARD_SCAN_RESULT_IMAGE_PATH, imagePath)
                        setResult(RESULT_OK, intent)
                        closeScanner()
                    }
                } finally {
                    // Also runs when Main dispatch is cancelled during teardown.
                    if (!result.acceptedFrame.isRecycled) result.acceptedFrame.recycle()
                }
            }

            /**
             * An interim result was received from the result aggregator.
             */
            override suspend fun onInterimResult(
                result: MainLoopAggregator.InterimResult
            ) = launch(Dispatchers.Main) {
                when (result.state) {
                    is MainLoopState.Initial -> changeScanState(CardScanState.NotFound)
                    is MainLoopState.OcrFound -> changeScanState(CardScanState.Found)
                    is MainLoopState.Finished -> changeScanState(CardScanState.Correct)
                }
            }.let { }

            override suspend fun onReset() = launch(Dispatchers.Main) {
                changeScanState(CardScanState.NotFound)
            }.let { }
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(viewBinding.root)

        onBackPressedDispatcher.addCallback {
            resultListener.userCanceled(CancellationReason.Back)
            closeScanner()
        }

        viewBinding.closeButton.setOnClickListener {
            userClosedScanner()
        }
        viewBinding.torchButton.setOnClickListener {
            toggleFlashlight()
        }
        viewBinding.swapCameraButton.setOnClickListener {
            toggleCamera()
        }
        viewBinding.galleryButton.setOnClickListener {
            if (!isImportingGallery && !isGalleryPickerOpen) {
                sessionTimeoutJob?.cancel()
                isGalleryPickerOpen = true
                viewBinding.galleryButton.isEnabled = false
                viewBinding.galleryButton.alpha = 0.55f
                lifecycleScope.launch {
                    // Stop and drain live inference before the picker appears.
                    // Otherwise a final camera result can close this activity
                    // behind the picker and race the selected gallery image.
                    scanFlow.cancelFlowAndAwait()
                    if (!isFinishing && isGalleryPickerOpen) {
                        galleryPicker.launch("image/*")
                    }
                }
            }
        }
        viewFinderBorder.setOnTouchListener { _, e ->
            setFocus(
                PointF(
                    e.x + viewFinderBorder.left,
                    e.y + viewFinderBorder.top
                )
            )
            true
        }

        displayState(requireNotNull(scanState), scanStatePrevious)
    }

    override fun onResume() {
        super.onResume()
        scanState = CardScanState.NotFound
    }

    override fun onDestroy() {
        sessionTimeoutJob?.cancel()
        galleryImportJob?.cancel()
        scanFlow.cancelFlow()
        cameraAdapter.destroy()
        super.onDestroy()
    }

    override fun onFlashSupported(supported: Boolean) {
        viewBinding.torchButton.setVisible(supported)
    }

    override fun onSupportsMultipleCameras(supported: Boolean) {
        viewBinding.swapCameraButton.setVisible(supported)
    }

    override fun onCameraReady() {
        previewFrame.post {
            viewFinderBackground
                .setViewFinderRect(viewFinderWindow.asRect())
            startCameraAdapter()
        }
    }

    /**
     * Once the camera stream is available, start processing images.
     */
    override suspend fun onCameraStreamAvailable(cameraStream: Flow<CameraPreviewImage<Bitmap>>) {
        startSessionTimeout()
        scanFlow.startFlow(
            context = this,
            imageStream = cameraStream,
            viewFinder = viewBinding.cameraView.viewFinderWindowView.asRect(),
            lifecycleOwner = this,
            coroutineScope = this,
            parameters = null,
            errorHandler = { e ->
                scanErrorListener.onResultFailure(e)
            }
        )
    }

    private fun startSessionTimeout() {
        sessionTimeoutJob?.cancel()
        if (isGalleryPickerOpen || isImportingGallery) return
        sessionTimeoutJob = lifecycleScope.launch {
            delay(SCAN_SESSION_TIMEOUT_MILLIS)
            setResult(
                RESULT_CANCELED,
                Intent().putExtra(CARD_SCAN_RESULT_REASON, "timeout"),
            )
            closeScanner()
        }
    }

    /**
     * Called when the flashlight state has changed.
     */
    override fun onFlashlightStateChanged(flashlightOn: Boolean) {
        if (flashlightOn) {
            viewBinding.torchButton.setDrawable(R.drawable.stripe_flash_on_dark)
        } else {
            viewBinding.torchButton.setDrawable(R.drawable.stripe_flash_off_dark)
        }
    }

    override fun displayState(newState: CardScanState, previousState: CardScanState?) {
        when (newState) {
            is CardScanState.NotFound -> {
                viewFinderBackground
                    .setBackgroundColor(getColorByRes(R.color.stripeNotFoundBackground))
                viewFinderWindow
                    .setBackgroundResource(R.drawable.stripe_card_background_not_found)
                viewFinderBorder.startAnimation(R.drawable.stripe_card_border_not_found)
                viewBinding.instructions.setText(R.string.stripe_card_scan_instructions)
                viewBinding.instructions.show()
                viewBinding.scanHint.setText(R.string.stripe_card_scan_tip)
                viewBinding.scanProgress.hide()
            }
            is CardScanState.Found -> {
                viewFinderBackground
                    .setBackgroundColor(getColorByRes(R.color.stripeFoundBackground))
                viewFinderWindow
                    .setBackgroundResource(R.drawable.stripe_card_background_found)
                viewFinderBorder.startAnimation(R.drawable.stripe_card_border_found)
                viewBinding.instructions.setText(R.string.stripe_card_scan_hold_steady)
                viewBinding.instructions.show()
                viewBinding.scanHint.setText(R.string.stripe_card_scan_checking)
                viewBinding.scanProgress.show()
                if (previousState !is CardScanState.Found) {
                    viewFinderBorder.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                }
            }
            is CardScanState.Correct -> {
                viewFinderBackground
                    .setBackgroundColor(getColorByRes(R.color.stripeCorrectBackground))
                viewFinderWindow
                    .setBackgroundResource(R.drawable.stripe_card_background_correct)
                viewFinderBorder.startAnimation(R.drawable.stripe_card_border_correct)
                viewBinding.instructions.setText(R.string.stripe_card_scan_complete)
                viewBinding.instructions.show()
                viewBinding.scanHint.setText(R.string.stripe_card_scan_finishing)
                viewBinding.scanProgress.hide()
                viewFinderBorder.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
            }
        }
    }

    override fun closeScanner() {
        sessionTimeoutJob?.cancel()
        galleryImportJob?.cancel()
        cameraAdapter.destroy()
        super.closeScanner()
    }

    private fun importGalleryImage(uri: Uri) {
        isImportingGallery = true
        sessionTimeoutJob?.cancel()
        cameraAdapter.unbindFromLifecycle(this)
        viewBinding.galleryButton.isEnabled = false
        viewBinding.galleryButton.alpha = 0.55f
        viewBinding.instructions.setText(R.string.stripe_card_scan_gallery_processing)
        viewBinding.scanHint.setText(R.string.stripe_card_scan_gallery_processing_hint)
        viewBinding.scanProgress.show()

        galleryImportJob?.cancel()
        galleryImportJob = lifecycleScope.launch {
            // A TensorFlow Lite inference already executing in native code does
            // not stop at coroutine cancellation. Wait for the camera workers
            // to exit and close their interpreters before creating the gallery
            // interpreter; overlapping teardown previously caused SIGSEGV.
            scanFlow.cancelFlowAndAwait()

            val imagePath = withContext(Dispatchers.IO) {
                copySelectedImage(uri)
            }
            if (imagePath != null) {
                val analysis = try {
                    withContext(Dispatchers.Default) {
                        analyzeGalleryPan(imagePath)
                    }
                } catch (_: Exception) {
                    null
                }
                val normalizedPath = analysis?.imagePath
                if (normalizedPath != null) {
                    if (normalizedPath != imagePath) File(imagePath).delete()
                    setResult(
                        RESULT_OK,
                        Intent()
                            .putExtra(CARD_SCAN_RESULT_IMAGE_PATH, normalizedPath)
                            .putExtra(CARD_SCAN_RESULT_PAN, analysis.pan)
                            .putExtra(CARD_SCAN_RESULT_SOURCE, RESULT_SOURCE_GALLERY),
                    )
                    closeScanner()
                    return@launch
                }
                File(imagePath).delete()
            }

            isImportingGallery = false
            viewBinding.galleryButton.isEnabled = true
            viewBinding.galleryButton.alpha = 1f
            viewBinding.scanProgress.hide()
            Toast.makeText(
                this@CardScanActivity,
                R.string.stripe_card_scan_gallery_error,
                Toast.LENGTH_LONG,
            ).show()
            scanFlow.resetFlow()
            changeScanState(CardScanState.NotFound)
            startCameraAdapter()
        }
    }

    private fun copySelectedImage(uri: Uri): String? {
        val mimeType = contentResolver.getType(uri)
        if (mimeType != null && !mimeType.startsWith("image/")) return null

        val output = File.createTempFile("selected_card_", ".image", cacheDir)
        return try {
            val input = contentResolver.openInputStream(uri) ?: run {
                output.delete()
                return null
            }
            var totalBytes = 0L
            input.use { source ->
                FileOutputStream(output).use { destination ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val count = source.read(buffer)
                        if (count < 0) break
                        totalBytes += count
                        if (totalBytes > MAX_GALLERY_IMAGE_BYTES) {
                            throw IllegalArgumentException("Selected image is too large")
                        }
                        destination.write(buffer, 0, count)
                    }
                }
            }
            output.takeIf { totalBytes > 0L }?.absolutePath
        } catch (_: Exception) {
            null
        }.also { path ->
            if (path == null) output.delete()
        }
    }

    private suspend fun analyzeGalleryPan(imagePath: String): GalleryAnalysis? {
        val bitmap = decodeGalleryBitmap(File(imagePath)) ?: return null
        val analyzer = SSDOcr.Factory(
            this,
            SSDOcrModelManager.fetchModel(
                this,
                forImmediateUse = true,
                isOptional = false,
            ),
            threads = 1,
        ).newInstance()

        if (analyzer == null) {
            bitmap.recycle()
            return null
        }

        return try {
            var normalizedPath: String? = null
            for (rotation in GALLERY_ROTATIONS) {
                val candidate = if (rotation == 0f) {
                    bitmap
                } else {
                    Bitmap.createBitmap(
                        bitmap,
                        0,
                        0,
                        bitmap.width,
                        bitmap.height,
                        Matrix().apply { postRotate(rotation) },
                        true,
                    )
                }
                try {
                    val input = SSDOcr.galleryBitmapToInput(candidate)
                    try {
                        val candidatePath = saveGalleryCardCrop(input.acceptedFrameCandidate)
                        if (rotation == 0f) normalizedPath = candidatePath
                        val prediction = analyzer.analyze(input, Unit)
                        if (!prediction.pan.isNullOrBlank()) {
                            if (rotation != 0f && candidatePath != null) {
                                normalizedPath?.let { File(it).delete() }
                                normalizedPath = candidatePath
                            } else if (rotation != 0f) {
                                candidatePath?.let { File(it).delete() }
                            }
                            return GalleryAnalysis(prediction.pan, normalizedPath)
                        }
                        if (rotation != 0f) candidatePath?.let { File(it).delete() }
                    } finally {
                        if (!input.acceptedFrameCandidate.isRecycled) {
                            input.acceptedFrameCandidate.recycle()
                        }
                    }
                } finally {
                    if (candidate !== bitmap) candidate.recycle()
                }
            }
            GalleryAnalysis(null, normalizedPath)
        } finally {
            analyzer.close()
            bitmap.recycle()
        }
    }

    private fun saveGalleryCardCrop(bitmap: Bitmap): String? {
        return try {
            val longEdge = max(bitmap.width, bitmap.height)
            val normalized = if (longEdge > MAX_GALLERY_OCR_SIDE) {
                val scale = MAX_GALLERY_OCR_SIDE.toFloat() / longEdge
                Bitmap.createScaledBitmap(
                    bitmap,
                    (bitmap.width * scale).roundToInt().coerceAtLeast(1),
                    (bitmap.height * scale).roundToInt().coerceAtLeast(1),
                    true,
                )
            } else {
                bitmap
            }
            try {
                val output = File.createTempFile("gallery_card_", ".jpg", cacheDir)
                FileOutputStream(output).use { stream ->
                    check(normalized.compress(Bitmap.CompressFormat.JPEG, 94, stream))
                }
                output.absolutePath
            } finally {
                if (normalized !== bitmap) normalized.recycle()
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun decodeGalleryBitmap(file: File): Bitmap? {
        val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            ImageDecoder.decodeBitmap(ImageDecoder.createSource(file)) { decoder, info, _ ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                val largestSide = max(info.size.width, info.size.height)
                if (largestSide > MAX_GALLERY_DECODE_SIDE) {
                    val scale = MAX_GALLERY_DECODE_SIDE.toFloat() / largestSide
                    decoder.setTargetSize(
                        (info.size.width * scale).roundToInt().coerceAtLeast(1),
                        (info.size.height * scale).roundToInt().coerceAtLeast(1),
                    )
                }
            }
        } else {
            BitmapFactory.decodeFile(file.absolutePath)
        } ?: return null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P ||
            max(bitmap.width, bitmap.height) <= MAX_GALLERY_DECODE_SIDE
        ) {
            return bitmap
        }
        val scale = MAX_GALLERY_DECODE_SIDE.toFloat() / max(bitmap.width, bitmap.height)
        return Bitmap.createScaledBitmap(
            bitmap,
            (bitmap.width * scale).roundToInt().coerceAtLeast(1),
            (bitmap.height * scale).roundToInt().coerceAtLeast(1),
            true,
        ).also { scaled ->
            if (scaled !== bitmap) bitmap.recycle()
        }
    }

    private fun saveAcceptedFrame(bitmap: Bitmap): String? {
        return try {
            val output = File.createTempFile("accepted_card_", ".png", cacheDir)
            FileOutputStream(output).use { stream ->
                // Preserve fine embossed/low-contrast name and expiry strokes.
                // The temporary file is deleted immediately after local OCR.
                check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream))
            }
            output.absolutePath
        } catch (_: Exception) {
            null
        } finally {
            bitmap.recycle()
        }
    }

    private companion object {
        const val SCAN_SESSION_TIMEOUT_MILLIS = 20_000L
        const val MAX_GALLERY_IMAGE_BYTES = 30L * 1024L * 1024L
        const val MAX_GALLERY_DECODE_SIDE = 2048
        const val MAX_GALLERY_OCR_SIDE = 1200
        const val RESULT_SOURCE_GALLERY = "gallery"
        val GALLERY_ROTATIONS = floatArrayOf(0f, 180f)
    }

    private data class GalleryAnalysis(
        val pan: String?,
        val imagePath: String?,
    )
}
