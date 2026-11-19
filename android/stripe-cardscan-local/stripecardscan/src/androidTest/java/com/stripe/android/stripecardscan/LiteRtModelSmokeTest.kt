package com.stripe.android.stripecardscan

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.stripe.android.mlcore.base.InterpreterOptionsWrapper
import com.stripe.android.mlcore.impl.InterpreterWrapperImpl
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LiteRtModelSmokeTest {
    @Test
    fun bundledCardModelRunsInferenceInPinnedLiteRtRuntime() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val modelBytes = context.assets.open("darknite_1_1_1_16.tflite").use {
            it.readBytes()
        }
        val model = ByteBuffer.allocateDirect(modelBytes.size)
            .order(ByteOrder.nativeOrder())
            .put(modelBytes)
        model.rewind()

        val interpreter = InterpreterWrapperImpl(
            model,
            InterpreterOptionsWrapper.Builder().numThreads(1).build(),
        )
        try {
            // Match SSDOcr's float RGB input and its two output tensors.
            val input = ByteBuffer.allocateDirect(600 * 375 * 3 * 4)
                .order(ByteOrder.nativeOrder())
            val classes = arrayOf(FloatArray(3420 * 11) { Float.NaN })
            val locations = arrayOf(FloatArray(3420 * 4) { Float.NaN })
            interpreter.runForMultipleInputsOutputs(
                arrayOf<Any>(input),
                mapOf(0 to classes, 1 to locations),
            )
            assertTrue("Class outputs must be populated and finite", classes[0].all { it.isFinite() })
            assertTrue("Location outputs must be populated and finite", locations[0].all { it.isFinite() })
        } finally {
            interpreter.close()
        }
    }
}
