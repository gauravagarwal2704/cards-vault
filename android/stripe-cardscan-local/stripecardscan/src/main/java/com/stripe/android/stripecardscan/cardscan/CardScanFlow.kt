package com.stripe.android.stripecardscan.cardscan

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Rect
import androidx.lifecycle.LifecycleOwner
import com.stripe.android.camera.CameraPreviewImage
import com.stripe.android.camera.framework.AggregateResultListener
import com.stripe.android.camera.framework.AnalyzerLoopErrorListener
import com.stripe.android.camera.framework.AnalyzerPool
import com.stripe.android.camera.framework.ProcessBoundAnalyzerLoop
import com.stripe.android.camera.framework.util.centerOn
import com.stripe.android.camera.framework.util.minAspectRatioSurroundingSize
import com.stripe.android.camera.framework.util.size
import com.stripe.android.camera.framework.util.union
import com.stripe.android.camera.scanui.ScanFlow
import com.stripe.android.stripecardscan.cardscan.result.MainLoopAggregator
import com.stripe.android.stripecardscan.cardscan.result.MainLoopState
import com.stripe.android.stripecardscan.payment.ml.SSDOcr
import com.stripe.android.stripecardscan.payment.ml.SSDOcrModelManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

internal abstract class CardScanFlow(
    private val scanErrorListener: AnalyzerLoopErrorListener
) : ScanFlow<Unit?, CameraPreviewImage<Bitmap>>,
    AggregateResultListener<MainLoopAggregator.InterimResult, MainLoopAggregator.FinalResult> {

    /**
     * If this is true, do not start the flow.
     */
    private var canceled = false

    private var mainLoopAnalyzerPool: AnalyzerPool<
        SSDOcr.Input,
        Any,
        SSDOcr.Prediction
        >? = null
    private var mainLoopAggregator: MainLoopAggregator? = null
    private var mainLoop: ProcessBoundAnalyzerLoop<
        SSDOcr.Input,
        MainLoopState,
        SSDOcr.Prediction
        >? = null

    private var mainLoopJob: Job? = null
    private val analyzerCleanupScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun startFlow(
        context: Context,
        imageStream: Flow<CameraPreviewImage<Bitmap>>,
        viewFinder: Rect,
        lifecycleOwner: LifecycleOwner,
        coroutineScope: CoroutineScope,
        parameters: Unit?,
        errorHandler: (e: Exception) -> Unit
    ) = coroutineScope.launch(Dispatchers.Main) {
        if (canceled) {
            return@launch
        }

        mainLoopAggregator = MainLoopAggregator(
            listener = this@CardScanFlow
        ).also {
            // make this result aggregator pause and reset when the lifecycle pauses.
            it.bindToLifecycle(lifecycleOwner)

            val analyzerPool = AnalyzerPool.of(
                SSDOcr.Factory(
                    context,
                    SSDOcrModelManager.fetchModel(
                        context,
                        forImmediateUse = true,
                        isOptional = false
                    )
                )
            )
            mainLoopAnalyzerPool = analyzerPool

            mainLoop = ProcessBoundAnalyzerLoop(
                analyzerPool = analyzerPool,
                resultHandler = it,
                analyzerLoopErrorListener = scanErrorListener,
            ).apply {
                mainLoopJob = subscribeTo(
                    imageStream.map { cameraImage ->
                        SSDOcr.cameraPreviewToInput(
                            cameraImage.image,
                            minAspectRatioSurroundingSize(
                                cameraImage.viewBounds.size().union(viewFinder.size()),
                                cameraImage.image.width.toFloat() / cameraImage.image.height
                            ).centerOn(cameraImage.viewBounds),
                            viewFinder
                        )
                    },
                    coroutineScope
                )
            }
        }
    }.let { }

    /**
     * Reset the flow to the initial state, ready to be started again
     */
    internal fun resetFlow() {
        canceled = false
        cleanUp()
    }

    override fun cancelFlow() {
        canceled = true
        cleanUp()
    }

    /**
     * Stop accepting camera frames and wait until every in-flight native inference has returned.
     * This is required before starting another TensorFlow Lite interpreter for gallery import.
     */
    internal suspend fun cancelFlowAndAwait() {
        canceled = true
        val pendingCleanup = detachFlow()
        pendingCleanup.analyzerJob?.join()
        pendingCleanup.analyzerPool?.closeAllAnalyzers()
    }

    private fun cleanUp() {
        val pendingCleanup = detachFlow()

        val analyzerPool = pendingCleanup.analyzerPool ?: return
        val analyzerJob = pendingCleanup.analyzerJob
        if (analyzerJob == null || analyzerJob.isCompleted) {
            analyzerPool.closeAllAnalyzers()
        } else {
            // TensorFlow Lite inference is native and is not cooperatively
            // cancellable. Closing an interpreter while a worker is still
            // inside JNI can crash the entire app with SIGSEGV. Stop frame
            // collection above, then close only after every worker exits.
            analyzerCleanupScope.launch {
                analyzerJob.join()
                analyzerPool.closeAllAnalyzers()
            }
        }
    }

    private fun detachFlow(): PendingCleanup {
        mainLoopAggregator?.run { cancel() }
        mainLoopAggregator = null

        val analyzerPool = mainLoopAnalyzerPool
        val analyzerJob = mainLoopJob
        mainLoop?.unsubscribe()
        mainLoop = null

        mainLoopAnalyzerPool = null
        mainLoopJob = null

        return PendingCleanup(analyzerPool, analyzerJob)
    }

    private data class PendingCleanup(
        val analyzerPool: AnalyzerPool<SSDOcr.Input, Any, SSDOcr.Prediction>?,
        val analyzerJob: Job?,
    )
}
