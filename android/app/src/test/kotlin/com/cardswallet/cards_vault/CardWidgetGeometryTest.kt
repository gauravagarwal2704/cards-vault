package com.cardswallet.cards_vault

import org.junit.Assert.*
import org.junit.Test

class CardWidgetGeometryTest {
    @Test fun facesKeepTheirRatioAndFitAcrossSizesAndFontScales() {
        for (width in 80..800 step 20) for (height in 90..800 step 20) {
            for (selected in 1..4) {
                val plan = CardWidgetGeometry.plan(width.toFloat(), height.toFloat(), selected)
                assertEquals(selected, plan.count)
                assertTrue(plan.columns * plan.rows >= plan.count)
                assertTrue(plan.cardWidth > 0 && plan.cardHeight > 0)
                assertEquals(CardWidgetGeometry.RATIO, plan.cardWidth / plan.cardHeight, .0001f)
                assertTrue(plan.cardWidth <= (width - 12f) / plan.columns - 8f + .001f)
                assertTrue(plan.cardHeight <= (height - 60f) / plan.rows - 8f + .001f)
            }
        }
    }

    @Test fun layoutsAdaptToShapeWithoutStretchingTheCard() {
        val tall = CardWidgetGeometry.plan(200f, 600f, 4)
        assertEquals(4, tall.count)
        assertEquals(1, tall.columns)
        val wide = CardWidgetGeometry.plan(900f, 180f, 4)
        assertEquals(4, wide.count)
        assertEquals(1, wide.rows)
        val square = CardWidgetGeometry.plan(400f, 400f, 4)
        assertEquals(4, square.count)
        assertEquals(2, square.columns)
        assertEquals(2, square.rows)
        assertEquals(4, CardWidgetGeometry.plan(200f, 190f, 4).count)
    }

    @Test fun tallResizeUsesHeightInsteadOfLeavingAnEmptyLowerPanel() {
        val plan = CardWidgetGeometry.plan(247f, 319f, 4)
        assertEquals(1, plan.columns)
        assertEquals(4, plan.rows)
        assertEquals(4, plan.count)
        assertTrue(4 * (plan.cardHeight + 8f) <= 319f - 60f + .001f)
        assertTrue(319f - 60f - 4 * (plan.cardHeight + 8f) < 1f)
        assertEquals(CardWidgetGeometry.RATIO, plan.cardWidth / plan.cardHeight, .0001f)
    }

    @Test fun dedicatedVerticalWidgetUsesEqualCardsAndFitsAllFour() {
        val plan = CardWidgetGeometry.plan(110f, 280f, 4, vertical = true)
        assertEquals(1, plan.columns)
        assertEquals(4, plan.rows)
        assertTrue(4 * (plan.cardHeight + 8f) <= 280f - 60f + .001f)
        assertTrue(plan.cardWidth <= 110f - 20f + .001f)
        assertEquals(CardWidgetGeometry.RATIO, plan.cardWidth / plan.cardHeight, .0001f)
        val square = CardWidgetGeometry.plan(240f, 240f, 4)
        assertEquals(2, square.columns)
    }

    @Test fun compactSquareFitsFourSmallerCardsInsideTwoLauncherCells() {
        val compact = CardWidgetGeometry.plan(110f, 110f, 4, compactSquare = true)
        val large = CardWidgetGeometry.plan(240f, 240f, 4)
        assertEquals(4, compact.count)
        assertEquals(2, compact.columns)
        assertEquals(2, compact.rows)
        assertTrue(compact.cardWidth < large.cardWidth)
        assertTrue(2 * (compact.cardWidth + 4f) <= 110f - 8f + .001f)
        assertTrue(2 * (compact.cardHeight + 4f) <= 110f - 40f + .001f)
        assertEquals(CardWidgetGeometry.RATIO,
            compact.cardWidth / compact.cardHeight, .0001f)
    }

    @Test fun shrinkingChangesCardSizeWithoutHidingCards() {
        val large = CardWidgetGeometry.plan(400f, 400f, 4)
        val small = CardWidgetGeometry.plan(160f, 176f, 4)
        assertEquals(4, small.count)
        assertTrue(small.cardWidth < large.cardWidth)
        assertEquals(2, small.columns)
        assertEquals(2, small.rows)
    }

    @Test fun nativeNameBoundaryRejectsNumbersAndControls() {
        assertEquals("Avery Sharma", CardWidgetPreviewPolicy.name("Avery 4111 1111 1111 1111 Sharma"))
        assertEquals("José O’Connor", CardWidgetPreviewPolicy.name("José O’Connor"))
        assertEquals("आरव शर्मा", CardWidgetPreviewPolicy.name("आरव शर्मा"))
        assertEquals("Avery", CardWidgetPreviewPolicy.name("Avery\u202e1234"))
        assertEquals(48, CardWidgetPreviewPolicy.name("A".repeat(100)).length)
    }
    @Test fun nicknameKeepsShortNumbersButDropsPastedCardNumbers() {
        assertEquals("Fuel 1", CardWidgetPreviewPolicy.nickname("Fuel 1"))
        assertEquals("Travel", CardWidgetPreviewPolicy.nickname("Travel 4111 1111 1111 1111"))
        assertEquals("Home", CardWidgetPreviewPolicy.nickname("Home\u202e"))
    }

    @Test fun limitedBitmapResolutionDoesNotShrinkLegacyLayouts() {
        for (cardWidth in listOf(60f, 150f, 500f, 900f)) {
            val pixels = (cardWidth * 3).toInt().coerceAtMost(960)
            val density = CardWidgetGeometry.bitmapDensity(pixels, cardWidth)
            val intrinsicDp = pixels * 160f / density
            assertEquals(cardWidth, intrinsicDp, cardWidth * .02f)
        }
    }

}
