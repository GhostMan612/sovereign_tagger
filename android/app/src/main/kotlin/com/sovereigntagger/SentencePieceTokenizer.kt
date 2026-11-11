// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import java.io.File
import kotlin.math.max

class SentencePieceTokenizer private constructor(
    private val pieces: Array<String>,
    private val scores: FloatArray,
    private val types: IntArray,
    private val pieceToId: HashMap<String, Int>,
    private val byteTokens: IntArray,
    val modelType: Int,
    val unkId: Int,
    val bosId: Int,
    val eosId: Int,
    val padId: Int,
    private val addDummyPrefix: Boolean,
    private val removeExtraWhitespaces: Boolean,
    private val escapeWhitespaces: Boolean,
    private val maxPieceLength: Int,
) {
    val vocabSize: Int get() = pieces.size

    fun encode(rawText: String, addBos: Boolean = true, addEos: Boolean = true): IntArray {
        var norm = rawText
        if (removeExtraWhitespaces) {
            norm = norm.trim().replace(WHITESPACE_REGEX, " ")
        }
        val out = ArrayList<Int>(norm.length + 4)
        if (addBos && bosId >= 0) out.add(bosId)
        if (norm.isEmpty()) {
            if (addEos && eosId >= 0) out.add(eosId)
            return out.toIntArray()
        }
        if (addDummyPrefix) {
            norm = " $norm"
        }
        if (escapeWhitespaces) {
            norm = norm.replace(' ', '\u2581')
        }

        if (modelType == MODEL_BPE) {
            encodeBpe(norm, out)
        } else {
            encodeUnigram(norm, out)
        }

        if (addEos && eosId >= 0) out.add(eosId)
        return out.toIntArray()
    }

    private fun encodeBpe(norm: String, out: MutableList<Int>) {
        var segStart = 0
        val len = norm.length
        while (segStart < len) {
            var segEnd = segStart + 1
            while (segEnd < len && norm[segEnd] != '\u2581') {
                segEnd++
            }
            val segment = norm.substring(segStart, segEnd)
            val direct = pieceToId[segment]
            if (direct != null) {
                out.add(direct)
            } else {
                encodeBpeSegment(segment, out)
            }
            segStart = segEnd
        }
    }

    private fun encodeBpeSegment(segment: String, out: MutableList<Int>) {
        val symbols = ArrayList<String>(segment.length)
        var i = 0
        while (i < segment.length) {
            val cp = segment.codePointAt(i)
            val charCount = Character.charCount(cp)
            symbols.add(segment.substring(i, i + charCount))
            i += charCount
        }

        var merges = 0
        val maxMerges = symbols.size * 2
        while (symbols.size > 1 && merges < maxMerges) {
            var bestIdx = -1
            var bestScore = Float.NEGATIVE_INFINITY
            for (idx in 0 until symbols.size - 1) {
                val merged = symbols[idx] + symbols[idx + 1]
                val id = pieceToId[merged] ?: continue
                val rawSc = scores[id]
                val sc = if (rawSc != 0f) rawSc else -id.toFloat()
                if (sc > bestScore) {
                    bestScore = sc
                    bestIdx = idx
                }
            }
            if (bestIdx < 0) break
            symbols[bestIdx] = symbols[bestIdx] + symbols[bestIdx + 1]
            symbols.removeAt(bestIdx + 1)
            merges++
        }

        for (sym in symbols) {
            val id = pieceToId[sym]
            if (id != null) {
                out.add(id)
            } else {
                appendFallbackBytes(sym, out)
            }
        }
    }

    private fun encodeUnigram(norm: String, out: MutableList<Int>) {
        val n = norm.length
        val bestScore = DoubleArray(n + 1) { Double.NEGATIVE_INFINITY }
        val bestPrev = IntArray(n + 1) { -1 }
        val bestId = IntArray(n + 1) { unkId }
        bestScore[0] = 0.0

        var pos = 0
        while (pos < n) {
            if (bestScore[pos] == Double.NEGATIVE_INFINITY) {
                pos++
                continue
            }
            val maxEnd = minOf(n, pos + maxPieceLength)
            var matchedAny = false
            var end = pos + 1
            while (end <= maxEnd) {
                if (Character.isHighSurrogate(norm[end - 1]) && end < n && Character.isLowSurrogate(norm[end])) {
                    end++
                }
                val sub = norm.substring(pos, end)
                val id = pieceToId[sub]
                if (id != null) {
                    matchedAny = true
                    val cand = bestScore[pos] + scores[id].toDouble()
                    if (cand > bestScore[end]) {
                        bestScore[end] = cand
                        bestPrev[end] = pos
                        bestId[end] = id
                    }
                }
                end++
            }
            if (!matchedAny) {
                val cp = norm.codePointAt(pos)
                val step = Character.charCount(cp)
                val next = minOf(n, pos + step)
                val cand = bestScore[pos] - 20.0
                if (cand > bestScore[next]) {
                    bestScore[next] = cand
                    bestPrev[next] = pos
                    bestId[next] = -1
                }
            }
            pos++
        }

        val revRanges = ArrayList<Triple<Int, Int, Int>>()
        var cur = n
        while (cur > 0) {
            val prev = bestPrev[cur]
            if (prev < 0) break
            revRanges.add(Triple(prev, cur, bestId[cur]))
            cur = prev
        }
        for (idx in revRanges.size - 1 downTo 0) {
            val (s, e, id) = revRanges[idx]
            if (id >= 0) {
                out.add(id)
            } else {
                appendFallbackBytes(norm.substring(s, e), out)
            }
        }
    }

    private fun appendFallbackBytes(sym: String, out: MutableList<Int>) {
        val utf8 = sym.toByteArray(Charsets.UTF_8)
        var usedAllBytes = true
        for (b in utf8) {
            if (byteTokens[b.toInt() and 0xFF] < 0) {
                usedAllBytes = false
                break
            }
        }
        if (usedAllBytes && utf8.isNotEmpty()) {
            for (b in utf8) {
                out.add(byteTokens[b.toInt() and 0xFF])
            }
        } else if (unkId >= 0) {
            out.add(unkId)
        }
    }

    companion object {
        const val MODEL_UNIGRAM = 1
        const val MODEL_BPE = 2
        private val WHITESPACE_REGEX = Regex("\\s+")

        fun load(file: File): SentencePieceTokenizer {
            val bytes = file.readBytes()
            require(bytes.size >= 64) { "Tokenizer file too small (${bytes.size} bytes)" }

            val pieceList = ArrayList<String>(65536)
            val scoreList = ArrayList<Float>(65536)
            val typeList = ArrayList<Int>(65536)

            var modelType = MODEL_BPE
            var unkId = 3
            var bosId = 2
            var eosId = 1
            var padId = 0
            var addDummyPrefix = false
            var removeExtraWhitespaces = true
            var escapeWhitespaces = true

            val root = ProtoReader(bytes, 0, bytes.size)
            while (root.hasMore()) {
                val tag = root.readVarint().toInt()
                if (tag == 0) break
                val fieldNo = tag ushr 3
                val wireType = tag and 0x07
                when {
                    fieldNo == 1 && wireType == 2 -> {
                        val len = root.readVarint().toInt()
                        val subEnd = root.pos + len
                        var pStr = ""
                        var pScore = 0f
                        var pType = 1
                        val sub = ProtoReader(bytes, root.pos, subEnd)
                        while (sub.hasMore()) {
                            val st = sub.readVarint().toInt()
                            val sf = st ushr 3
                            val sw = st and 0x07
                            when {
                                sf == 1 && sw == 2 -> pStr = sub.readString()
                                sf == 2 && sw == 5 -> pScore = Float.fromBits(sub.readFixed32())
                                sf == 3 && sw == 0 -> pType = sub.readVarint().toInt()
                                else -> sub.skip(sw)
                            }
                        }
                        root.pos = subEnd
                        pieceList.add(pStr)
                        scoreList.add(pScore)
                        typeList.add(pType)
                    }
                    fieldNo == 2 && wireType == 2 -> {
                        val len = root.readVarint().toInt()
                        val subEnd = root.pos + len
                        val sub = ProtoReader(bytes, root.pos, subEnd)
                        while (sub.hasMore()) {
                            val st = sub.readVarint().toInt()
                            val sf = st ushr 3
                            val sw = st and 0x07
                            when {
                                sf == 3 && sw == 0 -> modelType = sub.readVarint().toInt()
                                sf == 40 && sw == 0 -> unkId = sub.readVarint().toInt()
                                sf == 41 && sw == 0 -> bosId = sub.readVarint().toInt()
                                sf == 42 && sw == 0 -> eosId = sub.readVarint().toInt()
                                sf == 43 && sw == 0 -> padId = sub.readVarint().toInt()
                                else -> sub.skip(sw)
                            }
                        }
                        root.pos = subEnd
                    }
                    fieldNo == 3 && wireType == 2 -> {
                        val len = root.readVarint().toInt()
                        val subEnd = root.pos + len
                        val sub = ProtoReader(bytes, root.pos, subEnd)
                        while (sub.hasMore()) {
                            val st = sub.readVarint().toInt()
                            val sf = st ushr 3
                            val sw = st and 0x07
                            when {
                                sf == 3 && sw == 0 -> addDummyPrefix = sub.readVarint() != 0L
                                sf == 4 && sw == 0 -> removeExtraWhitespaces = sub.readVarint() != 0L
                                sf == 5 && sw == 0 -> escapeWhitespaces = sub.readVarint() != 0L
                                else -> sub.skip(sw)
                            }
                        }
                        root.pos = subEnd
                    }
                    else -> root.skip(wireType)
                }
            }

            require(pieceList.size >= 256) {
                "Invalid SentencePiece model: found only ${pieceList.size} vocabulary pieces"
            }

            val count = pieceList.size
            val piecesArr = pieceList.toTypedArray()
            val scoresArr = FloatArray(count) { scoreList[it] }
            val typesArr = IntArray(count) { typeList[it] }
            val map = HashMap<String, Int>(count * 2)
            val byteToks = IntArray(256) { -1 }
            var maxLen = 1

            for (idx in 0 until count) {
                val p = piecesArr[idx]
                val t = typesArr[idx]
                if (t == 6 || (p.length == 6 && p.startsWith("<0x") && p.endsWith(">"))) {
                    val hex = p.substring(3, 5).toIntOrNull(16)
                    if (hex != null && hex in 0..255) {
                        byteToks[hex] = idx
                    }
                }
                if (t == 0 || t == 1 || t == 4) {
                    if (!map.containsKey(p)) {
                        map[p] = idx
                    }
                    maxLen = max(maxLen, p.length)
                }
            }

            return SentencePieceTokenizer(
                pieces = piecesArr,
                scores = scoresArr,
                types = typesArr,
                pieceToId = map,
                byteTokens = byteToks,
                modelType = modelType,
                unkId = unkId,
                bosId = bosId,
                eosId = eosId,
                padId = padId,
                addDummyPrefix = addDummyPrefix,
                removeExtraWhitespaces = removeExtraWhitespaces,
                escapeWhitespaces = escapeWhitespaces,
                maxPieceLength = minOf(maxLen, 64),
            )
        }
    }

    private class ProtoReader(
        private val buf: ByteArray,
        var pos: Int,
        private val limit: Int,
    ) {
        fun hasMore(): Boolean = pos < limit

        fun readVarint(): Long {
            var result = 0L
            var shift = 0
            while (pos < limit && shift < 64) {
                val b = buf[pos++].toInt() and 0xFF
                result = result or ((b and 0x7F).toLong() shl shift)
                if ((b and 0x80) == 0) return result
                shift += 7
            }
            return result
        }

        fun readFixed32(): Int {
            if (pos + 4 > limit) {
                pos = limit
                return 0
            }
            val b0 = buf[pos++].toInt() and 0xFF
            val b1 = buf[pos++].toInt() and 0xFF
            val b2 = buf[pos++].toInt() and 0xFF
            val b3 = buf[pos++].toInt() and 0xFF
            return b0 or (b1 shl 8) or (b2 shl 16) or (b3 shl 24)
        }

        fun readString(): String {
            val len = readVarint().toInt()
            if (len <= 0 || pos + len > limit) {
                pos = minOf(limit, pos + max(0, len))
                return ""
            }
            val str = String(buf, pos, len, Charsets.UTF_8)
            pos += len
            return str
        }

        fun skip(wireType: Int) {
            when (wireType) {
                0 -> readVarint()
                1 -> pos = minOf(limit, pos + 8)
                2 -> {
                    val len = readVarint().toInt()
                    pos = minOf(limit, pos + max(0, len))
                }
                5 -> pos = minOf(limit, pos + 4)
                else -> pos = limit
            }
        }
    }
}
