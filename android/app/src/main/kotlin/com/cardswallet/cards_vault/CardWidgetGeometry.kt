package com.cardswallet.cards_vault

import kotlin.math.ceil
import kotlin.math.min
import kotlin.math.roundToInt

/** Pure layout policy. All selected cards remain visible with the ISO ID-1 ratio. */
object CardWidgetGeometry {
    const val RATIO = 85.60f / 53.98f
    data class Plan(val count: Int, val columns: Int, val rows: Int,
                    val cardWidth: Float, val cardHeight: Float)

    // Preserve logical card size even when a large face is rasterized at a capped resolution.
    fun bitmapDensity(pixelWidth: Int, cardWidth: Float) =
        (pixelWidth / cardWidth.coerceAtLeast(1f) * 160f).roundToInt().coerceAtLeast(1)

    fun plan(width: Float, height: Float, selected: Int, vertical: Boolean = false,
             compactSquare: Boolean = false): Plan {
        val count = min(selected, 4).coerceAtLeast(1)
        if (compactSquare) {
            // The short header and 2 dp card margins give a 2×2 launcher cell room
            // for four equal credit-card faces without clipping their corners.
            val columns = if (count == 1) 1 else 2
            val rows = ceil(count.toFloat() / columns).toInt()
            val cardWidth = min(((width - 8f) / columns - 4f).coerceAtLeast(1f),
                ((height - 40f) / rows - 4f).coerceAtLeast(1f) * RATIO)
            return Plan(count, columns, rows, cardWidth, cardWidth / RATIO)
        }
        val availableWidth = (width - 12f).coerceAtLeast(1f)
        val availableHeight = (height - 60f).coerceAtLeast(1f)
        if (vertical) {
            val cardWidth = min((availableWidth - 8f).coerceAtLeast(1f),
                (availableHeight / count - 8f).coerceAtLeast(1f) * RATIO)
            val cardHeight = cardWidth / RATIO
            return Plan(count, 1, count, cardWidth, cardHeight)
        }
        val candidates = (1..count).mapNotNull { columns ->
            val rows = ceil(count.toFloat() / columns).toInt()
            if (rows > 1 && columns > 2) return@mapNotNull null
            val cellWidth = (availableWidth / columns - 8f).coerceAtLeast(1f)
            val cellHeight = (availableHeight / rows - 8f).coerceAtLeast(1f)
            val cardWidth = min(cellWidth, cellHeight * RATIO)
            Plan(count, columns, rows, cardWidth, cardWidth / RATIO)
        }
        val widest = candidates.maxBy { it.cardWidth }
        // In a tall widget, a width-filling grid can strand most of the height
        // below its second row. Reflow into a vertical list once that spare area
        // is substantial; every face still keeps the physical card ratio.
        val unusedGridHeight = availableHeight - widest.rows * (widest.cardHeight + 8f)
        return if (count >= 3 && widest.columns > 1 &&
            height > width * 1.2f && unusedGridHeight > 32f) {
            candidates.first { it.columns == 1 }
        } else {
            widest
        }
    }
}
