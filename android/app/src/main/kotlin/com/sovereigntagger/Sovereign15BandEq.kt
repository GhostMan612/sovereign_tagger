// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import android.media.audiofx.DynamicsProcessing
import android.media.audiofx.Equalizer
import android.os.Build
import android.util.Log
import kotlin.math.ln
import kotlin.math.roundToInt
import kotlin.math.sqrt

internal object SovereignEqBands {
    val centersHz = doubleArrayOf(
        25.0, 40.0, 63.0, 100.0, 160.0,
        250.0, 400.0, 630.0, 1000.0, 1600.0,
        2500.0, 4000.0, 6300.0, 10000.0, 16000.0,
    )
    val cutoffsHz: FloatArray = FloatArray(centersHz.size) { i ->
        if (i == centersHz.lastIndex) 20000.0f
        else sqrt(centersHz[i] * centersHz[i + 1]).toFloat()
    }

    fun validate(gains: List<Double>): List<Double> {
        require(gains.size == centersHz.size) { "Expected 15 independent EQ gains" }
        require(gains.all { it.isFinite() }) { "EQ gains must be finite" }
        return gains.map { it.coerceIn(-12.0, 12.0) }
    }

    fun gainAt(gains: List<Double>, hz: Double): Double {
        if (hz <= centersHz.first()) return gains.first()
        if (hz >= centersHz.last()) return gains.last()
        val i = centersHz.indexOfLast { it <= hz }.coerceIn(0, centersHz.lastIndex - 1)
        val t = (ln(hz) - ln(centersHz[i])) / (ln(centersHz[i + 1]) - ln(centersHz[i]))
        return gains[i] + (gains[i + 1] - gains[i]) * t
    }

    fun verifyStereoReadback(
        ch0Gains: List<Double>,
        ch1Gains: List<Double>,
        ch0Enabled: List<Boolean>,
        ch1Enabled: List<Boolean>,
        ch0Cutoffs: List<Float>,
        ch1Cutoffs: List<Float>,
    ): Boolean {
        val n = centersHz.size
        if (ch0Gains.size != n || ch1Gains.size != n ||
            ch0Enabled.size != n || ch1Enabled.size != n ||
            ch0Cutoffs.size != n || ch1Cutoffs.size != n
        ) {
            return false
        }
        for (i in 0 until n) {
            if (!ch0Enabled[i] || !ch1Enabled[i]) return false
            val g0 = ch0Gains[i]
            val g1 = ch1Gains[i]
            if (!g0.isFinite() || !g1.isFinite()) return false
            if (kotlin.math.abs(g0 - g1) > 0.001) return false
            if (kotlin.math.abs(ch0Cutoffs[i] - cutoffsHz[i]) > 0.5f) return false
            if (kotlin.math.abs(ch1Cutoffs[i] - cutoffsHz[i]) > 0.5f) return false
        }
        return true
    }
}

internal class Sovereign15BandEq {
    private var sessionId = 0
    private var dynamics: DynamicsProcessing? = null
    private var legacy: Equalizer? = null
    private var legacyCentersHz = emptyList<Double>()
    private var legacyRangeDb = -15.0 to 15.0

    fun attach(newSessionId: Int): Map<String, Any> {
        require(newSessionId > 0) { "Audio session must be positive" }
        if (newSessionId == sessionId && (dynamics != null || legacy != null)) return describe()
        release()
        sessionId = newSessionId
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            var candidate: DynamicsProcessing? = null
            try {
                val config = DynamicsProcessing.Config.Builder(
                    DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                    2, true, SovereignEqBands.centersHz.size,
                    false, 0, false, 0, false,
                ).build()
                candidate = DynamicsProcessing(0, newSessionId, config)
                check(candidate.config.preEqBandCount == SovereignEqBands.centersHz.size) {
                    "DynamicsProcessing did not retain all 15 EQ bands"
                }
                for (i in SovereignEqBands.cutoffsHz.indices) {
                    candidate.setPreEqBandAllChannelsTo(
                        i, DynamicsProcessing.EqBand(true, SovereignEqBands.cutoffsHz[i], 0.0f),
                    )
                }
                candidate.enabled = false
                dynamics = candidate
                Log.i("SovereignEq15", "Attached independent 15-band DSP to session $newSessionId")
                return describe()
            } catch (error: Throwable) {
                Log.w("SovereignEq15", "Independent DSP unavailable; trying legacy EQ", error)
                try { candidate?.release() } catch (_: Throwable) {}
            }
        }
        try {
            val eq = Equalizer(0, newSessionId)
            eq.enabled = false
            legacy = eq
            legacyCentersHz = (0 until eq.numberOfBands.toInt()).map {
                eq.getCenterFreq(it.toShort()).toDouble() / 1000.0
            }
            val range = eq.bandLevelRange
            legacyRangeDb = range[0] / 100.0 to range[1] / 100.0
            Log.w("SovereignEq15", "Using " + legacyCentersHz.size + "-band legacy fallback; NOT independent DSP")
        } catch (error: Throwable) {
            Log.w("SovereignEq15", "Neither DSP nor legacy EQ available; playback remains unprocessed", error)
            legacy = null
        }
        return describe()
    }

    fun apply(enabled: Boolean, inputGains: List<Double>): Boolean {
        val gains = try {
            SovereignEqBands.validate(inputGains)
        } catch (error: IllegalArgumentException) {
            Log.w("SovereignEq15", "Rejected invalid EQ gains", error)
            return false
        }
        dynamics?.let { effect ->
            return try {
                for (i in SovereignEqBands.cutoffsHz.indices) {
                    effect.setPreEqBandAllChannelsTo(
                        i, DynamicsProcessing.EqBand(
                            true, SovereignEqBands.cutoffsHz[i], gains[i].toFloat(),
                        ),
                    )
                }
                effect.enabled = enabled
                true
            } catch (error: Throwable) {
                try { effect.enabled = false } catch (_: Throwable) {}
                Log.w("SovereignEq15", "DSP update failed; effect bypassed", error)
                false
            }
        }
        legacy?.let { eq ->
            return try {
                val range = eq.bandLevelRange
                for (i in legacyCentersHz.indices) {
                    val db = SovereignEqBands.gainAt(gains, legacyCentersHz[i])
                    val mb = (db * 100).roundToInt().coerceIn(range[0].toInt(), range[1].toInt())
                    eq.setBandLevel(i.toShort(), mb.toShort())
                }
                eq.enabled = enabled
                true
            } catch (error: Throwable) {
                try { eq.enabled = false } catch (_: Throwable) {}
                Log.w("SovereignEq15", "Legacy EQ update failed; effect bypassed", error)
                false
            }
        }
        return false
    }

    fun describe(): Map<String, Any> {
        if (dynamics != null) return mapOf(
            "engine" to "dynamics15",
            "bands" to SovereignEqBands.centersHz.toList(),
            "minDb" to -12.0, "maxDb" to 12.0,
        )
        if (legacy != null) return mapOf(
            "engine" to "legacy",
            "bands" to legacyCentersHz,
            "minDb" to legacyRangeDb.first,
            "maxDb" to legacyRangeDb.second,
        )
        return mapOf(
            "engine" to "unavailable",
            "bands" to emptyList<Double>(),
            "minDb" to -12.0, "maxDb" to 12.0,
        )
    }

    fun readEq(): Map<String, Any> {
        dynamics?.let { effect ->
            return try {
                val indices = SovereignEqBands.centersHz.indices
                val bands0 = indices.map { i -> effect.getPreEqBandByChannelIndex(0, i) }
                val bands1 = indices.map { i -> effect.getPreEqBandByChannelIndex(1, i) }
                val ch0Gains = bands0.map { it.gain.toDouble() }
                val ch1Gains = bands1.map { it.gain.toDouble() }
                val ch0Enabled = bands0.map { it.isEnabled }
                val ch1Enabled = bands1.map { it.isEnabled }
                val ch0Cutoffs = bands0.map { it.cutoffFrequency }
                val ch1Cutoffs = bands1.map { it.cutoffFrequency }
                val stereoOk = SovereignEqBands.verifyStereoReadback(
                    ch0Gains, ch1Gains, ch0Enabled, ch1Enabled, ch0Cutoffs, ch1Cutoffs,
                )
                mapOf(
                    "engine" to "dynamics15",
                    "enabled" to effect.enabled,
                    "channelCount" to 2,
                    "channelsMatch" to stereoOk,
                    "gainsDb" to if (stereoOk) ch0Gains else emptyList<Double>(),
                    "channel0GainsDb" to ch0Gains,
                    "channel1GainsDb" to ch1Gains,
                )
            } catch (error: Throwable) {
                Log.w("SovereignEq15", "EQ readback failed", error)
                mapOf(
                    "engine" to "dynamics15",
                    "enabled" to false,
                    "channelCount" to 2,
                    "channelsMatch" to false,
                    "gainsDb" to emptyList<Double>(),
                    "channel0GainsDb" to emptyList<Double>(),
                    "channel1GainsDb" to emptyList<Double>(),
                )
            }
        }
        legacy?.let { eq ->
            return try {
                val gains = (0 until eq.numberOfBands.toInt()).map { i ->
                    eq.getBandLevel(i.toShort()).toDouble() / 100.0
                }
                mapOf(
                    "engine" to "legacy",
                    "enabled" to eq.enabled,
                    "channelCount" to 1,
                    "channelsMatch" to gains.isNotEmpty(),
                    "gainsDb" to gains,
                    "channel0GainsDb" to gains,
                    "channel1GainsDb" to gains,
                )
            } catch (error: Throwable) {
                Log.w("SovereignEq15", "Legacy EQ readback failed", error)
                mapOf(
                    "engine" to "legacy",
                    "enabled" to false,
                    "channelCount" to 1,
                    "channelsMatch" to false,
                    "gainsDb" to emptyList<Double>(),
                    "channel0GainsDb" to emptyList<Double>(),
                    "channel1GainsDb" to emptyList<Double>(),
                )
            }
        }
        return mapOf(
            "engine" to (describe()["engine"] ?: "unavailable"),
            "enabled" to false,
            "channelCount" to 0,
            "channelsMatch" to false,
            "gainsDb" to emptyList<Double>(),
            "channel0GainsDb" to emptyList<Double>(),
            "channel1GainsDb" to emptyList<Double>(),
        )
    }

    fun release() {
        try { dynamics?.enabled = false } catch (_: Throwable) {}
        try { dynamics?.release() } catch (_: Throwable) {}
        try { legacy?.enabled = false } catch (_: Throwable) {}
        try { legacy?.release() } catch (_: Throwable) {}
        dynamics = null
        legacy = null
        legacyCentersHz = emptyList()
        sessionId = 0
    }
}
