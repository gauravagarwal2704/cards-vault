package com.stripe.android.stripecardscan.cardscan.result

import android.graphics.Bitmap
import com.stripe.android.camera.framework.AggregateResultListener
import com.stripe.android.camera.framework.ResultAggregator
import com.stripe.android.stripecardscan.cardscan.result.MainLoopAggregator.FinalResult
import com.stripe.android.stripecardscan.cardscan.result.MainLoopAggregator.InterimResult
import com.stripe.android.stripecardscan.payment.ml.SSDOcr
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.sqrt
import kotlin.time.TimeSource

/**
 * Aggregate results from the main loop. Each frame will trigger an [InterimResult] to the
 * [listener]. Once the [MainLoopState.Finished] state is reached, a [FinalResult] will be sent to
 * the [listener].
 *
 * This aggregator is a state machine. The full list of possible states are subclasses of
 * [MainLoopState].
 */
internal class MainLoopAggregator(
    listener: AggregateResultListener<InterimResult, FinalResult>
) : ResultAggregator<
    SSDOcr.Input,
    MainLoopState,
    SSDOcr.Prediction,
    InterimResult,
    FinalResult
    >(
    listener = listener,
    initialState = MainLoopState.Initial(TimeSource.Monotonic)
) {

    // Keep at most one PAN-positive preview crop in memory. Replacing it with
    // a sharper candidate improves small expiry/name text without bringing
    // back high-resolution still capture or retaining rejected frames.
    private var bestFrame: Bitmap? = null
    private var bestFramePan: String? = null
    private var bestFrameQuality = Double.NEGATIVE_INFINITY

    internal data class FinalResult(
        val pan: String,
        val acceptedFrame: Bitmap,
    )

    internal data class InterimResult(
        val analyzerResult: SSDOcr.Prediction,
        val state: MainLoopState
    )

    override suspend fun aggregateResult(
        frame: SSDOcr.Input,
        result: SSDOcr.Prediction
    ): Pair<InterimResult, FinalResult?> {
        val previousState = state
        val currentState = previousState.consumeTransition(result)

        state = currentState

        val interimResult = InterimResult(
            analyzerResult = result,
            state = currentState
        )

        considerAcceptedFrame(frame.acceptedFrameCandidate, result.pan)

        return if (currentState is MainLoopState.Finished) {
            val acceptedFrame = if (bestFramePan == currentState.pan) {
                bestFrame.also { bestFrame = null }
            } else {
                null
            } ?: frame.acceptedFrameCandidate

            if (acceptedFrame !== frame.acceptedFrameCandidate &&
                !frame.acceptedFrameCandidate.isRecycled
            ) {
                frame.acceptedFrameCandidate.recycle()
            }
            recycleBestFrameUnless(acceptedFrame)
            interimResult to FinalResult(
                pan = currentState.pan,
                acceptedFrame = acceptedFrame,
            )
        } else {
            interimResult to null
        }
    }

    override fun reset() {
        recycleBestFrameUnless()
        super.reset()
    }

    private fun considerAcceptedFrame(candidate: Bitmap, pan: String?) {
        if (pan.isNullOrEmpty()) {
            candidate.recycle()
            return
        }

        val quality = previewTextQuality(candidate)
        val shouldReplace = bestFrame == null ||
            bestFramePan != pan ||
            quality > bestFrameQuality
        if (!shouldReplace) {
            candidate.recycle()
            return
        }

        recycleBestFrameUnless(candidate)
        bestFrame = candidate
        bestFramePan = pan
        bestFrameQuality = quality
    }

    private fun recycleBestFrameUnless(retained: Bitmap? = null) {
        bestFrame?.let { frame ->
            if (frame !== retained && !frame.isRecycled) frame.recycle()
        }
        if (bestFrame !== retained) bestFrame = null
        if (bestFrame == null) {
            bestFramePan = null
            bestFrameQuality = Double.NEGATIVE_INFINITY
        }
    }

    private fun previewTextQuality(bitmap: Bitmap): Double {
        val stepX = max(1, bitmap.width / 64)
        val stepY = max(1, bitmap.height / 40)
        var count = 0
        var luminanceTotal = 0.0
        var luminanceSquaredTotal = 0.0
        var edgeTotal = 0.0

        var y = stepY
        while (y < bitmap.height) {
            var previous = luminance(bitmap.getPixel(0, y))
            var x = stepX
            while (x < bitmap.width) {
                val current = luminance(bitmap.getPixel(x, y))
                luminanceTotal += current
                luminanceSquaredTotal += current * current
                edgeTotal += abs(current - previous)
                previous = current
                count++
                x += stepX
            }
            y += stepY
        }

        if (count == 0) return Double.NEGATIVE_INFINITY
        val mean = luminanceTotal / count
        val variance = max(0.0, luminanceSquaredTotal / count - mean * mean)
        val exposurePenalty = abs(mean - 132.0) * 0.08
        return edgeTotal / count + sqrt(variance) * 0.30 - exposurePenalty
    }

    private fun luminance(color: Int): Double {
        val red = color shr 16 and 0xFF
        val green = color shr 8 and 0xFF
        val blue = color and 0xFF
        return red * 0.299 + green * 0.587 + blue * 0.114
    }
}
