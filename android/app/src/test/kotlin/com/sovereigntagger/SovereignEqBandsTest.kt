// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import kotlin.math.sqrt

class SovereignEqBandsTest {
    @Test fun centersAndCutoffsCover15IncreasingBands() {
        assertEquals(15, SovereignEqBands.centersHz.size)
        assertEquals(15, SovereignEqBands.cutoffsHz.size)
        assertEquals(20000.0f, SovereignEqBands.cutoffsHz.last(), 0.01f)
        for (i in 0 until SovereignEqBands.cutoffsHz.lastIndex) {
            assertTrue(SovereignEqBands.cutoffsHz[i + 1] > SovereignEqBands.cutoffsHz[i])
            assertEquals(
                sqrt(SovereignEqBands.centersHz[i] * SovereignEqBands.centersHz[i + 1]).toFloat(),
                SovereignEqBands.cutoffsHz[i], 0.01f,
            )
        }
    }

    @Test fun sixteenInputsRejectedAndNonfiniteRejected() {
        try {
            SovereignEqBands.validate(List(16) { 0.0 })
            fail("must reject sixteen gains")
        } catch (_: IllegalArgumentException) {}
        try {
            SovereignEqBands.validate(List(15) { if (it == 4) Double.NaN else 0.0 })
            fail("must reject NaN")
        } catch (_: IllegalArgumentException) {}
    }

    @Test fun gainsClampedToTwelveDecibels() {
        val gains = SovereignEqBands.validate(List(15) { if (it % 2 == 0) 99.0 else -99.0 })
        assertEquals(12.0, gains.first(), 0.0)
        assertEquals(-12.0, gains[1], 0.0)
        assertEquals(15, gains.size)
    }

    @Test fun legacyInterpolationOnlySamplesSpecifiedCurve() {
        val gains = List(15) { it.toDouble() - 7.0 }
        for (i in SovereignEqBands.centersHz.indices) {
            assertEquals(gains[i], SovereignEqBands.gainAt(gains, SovereignEqBands.centersHz[i]), 0.00001)
        }
        assertEquals(gains.first(), SovereignEqBands.gainAt(gains, 1.0), 0.00001)
        assertEquals(gains.last(), SovereignEqBands.gainAt(gains, 25000.0), 0.00001)
    }

    @Test fun stereoReadbackRequiresBothChannelsEnabledAndMatching() {
        val gains = List(15) { if (it == 4) 12.0 else 0.0 }
        val enabled = List(15) { true }
        val cutoffs = SovereignEqBands.cutoffsHz.toList()
        assertTrue(
            SovereignEqBands.verifyStereoReadback(
                gains, gains, enabled, enabled, cutoffs, cutoffs,
            ),
        )

        val divergedCh1 = gains.toMutableList().apply { set(4, 6.0) }
        assertFalse(
            SovereignEqBands.verifyStereoReadback(
                gains, divergedCh1, enabled, enabled, cutoffs, cutoffs,
            ),
        )

        val disabledBandCh1 = enabled.toMutableList().apply { set(8, false) }
        assertFalse(
            SovereignEqBands.verifyStereoReadback(
                gains, gains, enabled, disabledBandCh1, cutoffs, cutoffs,
            ),
        )

        val badCutoffCh1 = cutoffs.toMutableList().apply { set(0, cutoffs[0] + 100.0f) }
        assertFalse(
            SovereignEqBands.verifyStereoReadback(
                gains, gains, enabled, enabled, cutoffs, badCutoffCh1,
            ),
        )
    }
}
