package com.stripe.android.stripecardscan

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.stripe.android.mlcore.base.InterpreterOptionsWrapper
import com.stripe.android.mlcore.impl.InterpreterWrapperImpl
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LiteRtModelSmokeTest {
    @Test
    fun bundledCardModelLoadsInPinnedLiteRtRuntime() {
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
        interpreter.close()
    }
}
