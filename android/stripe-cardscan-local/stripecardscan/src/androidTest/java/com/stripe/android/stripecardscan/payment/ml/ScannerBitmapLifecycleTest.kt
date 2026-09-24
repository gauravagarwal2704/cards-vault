package com.stripe.android.stripecardscan.payment.ml

import android.graphics.Bitmap
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ScannerBitmapLifecycleTest {
    @Test
    fun repeatedGalleryInputsRecycleFramesAndReuseNativeModelBuffers() {
        val source = Bitmap.createBitmap(1600, 1000, Bitmap.Config.ARGB_8888)
        val bufferIdentities = mutableSetOf<Int>()

        try {
            repeat(25) {
                val input = SSDOcr.galleryBitmapToInput(source)
                val acceptedFrame = input.acceptedFrameCandidate
                bufferIdentities += System.identityHashCode(input.ssdOcrImage.getData())

                input.close()

                assertTrue(acceptedFrame.isRecycled)
                assertThrows(IllegalStateException::class.java) {
                    input.ssdOcrImage.getData()
                }
            }

            // Sequential scans should reuse one 600x375 direct model buffer.
            assertEquals(1, bufferIdentities.size)
            assertFalse(source.isRecycled)
        } finally {
            source.recycle()
        }
    }
}
