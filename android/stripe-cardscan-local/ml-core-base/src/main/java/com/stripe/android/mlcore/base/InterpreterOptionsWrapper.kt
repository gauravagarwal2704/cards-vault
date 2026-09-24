package com.stripe.android.mlcore.base

import androidx.annotation.RestrictTo

/**
 * Wrapper class for the options to initialize the encapsulated interpreter.
 */
@RestrictTo(RestrictTo.Scope.LIBRARY_GROUP)
class InterpreterOptionsWrapper private constructor(
    val numThreads: Int?
) {
    @RestrictTo(RestrictTo.Scope.LIBRARY_GROUP)
    class Builder {
        private var numThreads: Int? = null

        fun numThreads(numThreads: Int): Builder {
            this.numThreads = numThreads
            return this
        }

        fun build(): InterpreterOptionsWrapper = InterpreterOptionsWrapper(
            numThreads
        )
    }
}
