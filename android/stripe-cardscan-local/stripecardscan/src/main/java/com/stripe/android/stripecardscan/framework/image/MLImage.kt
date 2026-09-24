package com.stripe.android.stripecardscan.framework.image

import android.graphics.Bitmap
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.ArrayDeque

private const val DIM_PIXEL_SIZE = 3
private const val NUM_BYTES_PER_CHANNEL = 4 // Float.size / Byte.size

internal data class ImageTransformValues(val red: Float, val green: Float, val blue: Float)

/**
 * An image in the required ML input format (array of floats, 3 floats per pixel in R, G, B format).
 */
internal class MLImage private constructor(
    val width: Int,
    val height: Int,
    private var imageData: ByteBuffer?,
) : AutoCloseable {

    constructor(bitmap: Bitmap, mean: Float = 0F, std: Float = 255F) : this(
        bitmap,
        ImageTransformValues(mean, mean, mean),
        ImageTransformValues(std, std, std)
    )

    constructor(bitmap: Bitmap, mean: ImageTransformValues, std: ImageTransformValues) : this(
        bitmap.width,
        bitmap.height,
        createImageData(bitmap, mean, std),
    )

    /**
     * Get the RBG direct [ByteBuffer] for use in ML models.
     */
    @Synchronized
    fun getData(): ByteBuffer = checkNotNull(imageData) {
        "ML image data has already been released"
    }.apply { rewind() }

    /** Return the native input allocation to the bounded pool after inference. */
    @Synchronized
    override fun close() {
        val data = imageData ?: return
        imageData = null
        imageDataPool.release(data)
    }

    private companion object {
        // The live scanner creates four analyzers. Retaining at most one input
        // per worker prevents per-frame direct-buffer growth across scans.
        val imageDataPool = DirectByteBufferPool(maxRetainedBuffers = 4)

        fun createImageData(
            bitmap: Bitmap,
            mean: ImageTransformValues,
            std: ImageTransformValues,
        ): ByteBuffer {
            val pixelCount = Math.multiplyExact(bitmap.width, bitmap.height)
            val byteCount = Math.multiplyExact(
                pixelCount,
                DIM_PIXEL_SIZE * NUM_BYTES_PER_CHANNEL,
            )
            val rgbFloat = imageDataPool.acquire(byteCount)
            return try {
                val pixels = IntArray(pixelCount)
                bitmap.getPixels(
                    pixels,
                    0,
                    bitmap.width,
                    0,
                    0,
                    bitmap.width,
                    bitmap.height,
                )
                pixels.forEach { pixel ->
                    // Ignore alpha; the model consumes normalized RGB values.
                    rgbFloat.putFloat(((pixel shr 16 and 0xFF) - mean.red) / std.red)
                    rgbFloat.putFloat(((pixel shr 8 and 0xFF) - mean.green) / std.green)
                    rgbFloat.putFloat(((pixel and 0xFF) - mean.blue) / std.blue)
                }
                rgbFloat.rewind()
                rgbFloat
            } catch (t: Throwable) {
                imageDataPool.release(rgbFloat)
                throw t
            }
        }
    }
}

/** A small exact-capacity pool for native-order direct inference buffers. */
internal class DirectByteBufferPool(private val maxRetainedBuffers: Int) {
    private val buffers = ArrayDeque<ByteBuffer>(maxRetainedBuffers)

    init {
        require(maxRetainedBuffers > 0)
    }

    @Synchronized
    fun acquire(capacity: Int): ByteBuffer {
        require(capacity > 0)
        val iterator = buffers.iterator()
        while (iterator.hasNext()) {
            val candidate = iterator.next()
            if (candidate.capacity() == capacity) {
                iterator.remove()
                return candidate.apply {
                    clear()
                    order(ByteOrder.nativeOrder())
                }
            }
        }
        return ByteBuffer.allocateDirect(capacity).order(ByteOrder.nativeOrder())
    }

    @Synchronized
    fun release(buffer: ByteBuffer) {
        if (!buffer.isDirect || buffers.size >= maxRetainedBuffers) return
        buffer.clear()
        buffers.addLast(buffer)
    }
}
