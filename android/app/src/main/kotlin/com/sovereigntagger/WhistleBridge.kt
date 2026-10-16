// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors

class WhistleBridge(private val context: Context) {
    private val TAG = "WhistleBridge"
    private val executor = Executors.newSingleThreadExecutor()
    @Volatile private var isLoaded = false
    @Volatile private var nativeLibraryLoaded = false

    init {
        try {
            System.loadLibrary("sovereign_whistle")
            nativeLibraryLoaded = true
            Log.i(TAG, "sovereign_whistle native library loaded successfully")
        } catch (e: Throwable) {
            Log.w(TAG, "Failed to load sovereign_whistle native library: ${e.message}")
            nativeLibraryLoaded = false
        }
    }

    external fun nativeIsSupported(): Boolean
    external fun nativeLoad(modelPath: String): Int
    external fun nativeTranscribe(
        pcmFloats: FloatArray,
        language: String?,
        keywords: String?,
        wordTimestamps: Boolean
    ): String?
    external fun nativeLastError(): String?
    external fun nativeReset()

    fun isSupported(): Boolean {
        if (!nativeLibraryLoaded) return false
        return try {
            nativeIsSupported()
        } catch (e: Throwable) {
            Log.e(TAG, "nativeIsSupported check failed", e)
            false
        }
    }

    fun isReady(): Boolean = isLoaded && isSupported()

    fun loadModel(modelPath: String, onComplete: (Boolean, String?) -> Unit) {
        if (!isSupported()) {
            onComplete(false, "UNSUPPORTED_ABI")
            return
        }
        executor.submit {
            try {
                val file = File(modelPath)
                if (!file.exists() || file.length() < 10000000) {
                    onComplete(false, "MODEL_FILE_NOT_FOUND_OR_INVALID")
                    return@submit
                }
                val rc = nativeLoad(file.absolutePath)
                if (rc == 0) {
                    isLoaded = true
                    Log.i(TAG, "Whistle model loaded: ${file.absolutePath}")
                    onComplete(true, null)
                } else {
                    isLoaded = false
                    val err = nativeLastError() ?: "LOAD_FAILED_CODE_$rc"
                    Log.e(TAG, "Whistle nativeLoad failed: $err")
                    onComplete(false, err)
                }
            } catch (e: Throwable) {
                isLoaded = false
                Log.e(TAG, "Whistle loadModel exception", e)
                onComplete(false, e.message ?: "UNKNOWN_LOAD_EXCEPTION")
            }
        }
    }

    fun transcribeWav(
        wavPath: String,
        language: String?,
        keywords: String?,
        wordTimestamps: Boolean,
        onComplete: (String?, String?) -> Unit
    ) {
        if (!isSupported()) {
            onComplete(null, "UNSUPPORTED_ABI")
            return
        }
        if (!isLoaded) {
            onComplete(null, "MODEL_NOT_LOADED")
            return
        }

        executor.submit {
            try {
                val wavFile = File(wavPath)
                if (!wavFile.exists() || wavFile.length() < 44) {
                    onComplete(null, "WAV_FILE_TOO_SHORT")
                    return@submit
                }

                val pcmFloats = readWavToFloatArray(wavFile)
                if (pcmFloats == null || pcmFloats.isEmpty()) {
                    onComplete(null, "MALFORMED_OR_EMPTY_WAV")
                    return@submit
                }

                val jsonResponse = nativeTranscribe(pcmFloats, language, keywords, wordTimestamps)
                if (jsonResponse == null) {
                    val err = nativeLastError() ?: "NULL_TRANSCRIBE_RESULT"
                    onComplete(null, err)
                    return@submit
                }

                val jsonObj = JSONObject(jsonResponse)
                if (jsonObj.has("error")) {
                    onComplete(null, jsonObj.getString("error"))
                    return@submit
                }

                val text = jsonObj.optString("text", "").trim()
                onComplete(text, null)
            } catch (e: Throwable) {
                Log.e(TAG, "Whistle transcribeWav exception", e)
                onComplete(null, e.message ?: "TRANSCRIBE_EXCEPTION")
            }
        }
    }

    private fun readWavToFloatArray(file: File): FloatArray? {
        try {
            val bytes = file.readBytes()
            if (bytes.size < 44) return null

            val bb = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)

            val riff = String(bytes, 0, 4)
            val wave = String(bytes, 8, 4)
            if (riff != "RIFF" || wave != "WAVE") return null

            var offset = 12
            var audioFormat = 1
            var numChannels = 1
            var sampleRate = 16000
            var bitsPerSample = 16
            var dataOffset = -1
            var dataLength = 0

            while (offset + 8 <= bytes.size) {
                val chunkId = String(bytes, offset, 4)
                val chunkSize = bb.getInt(offset + 4)
                offset += 8

                if (chunkId == "fmt ") {
                    if (chunkSize >= 16) {
                        audioFormat = bb.getShort(offset).toInt()
                        numChannels = bb.getShort(offset + 2).toInt()
                        sampleRate = bb.getInt(offset + 4)
                        bitsPerSample = bb.getShort(offset + 14).toInt()
                    }
                    offset += chunkSize
                } else if (chunkId == "data") {
                    dataOffset = offset
                    dataLength = chunkSize.coerceAtMost(bytes.size - offset)
                    break
                } else {
                    offset += chunkSize
                }
            }

            if (dataOffset < 0 || dataLength <= 0) return null
            if (audioFormat != 1) return null // PCM only
            if (bitsPerSample != 16) return null // 16-bit only

            val sampleCount = dataLength / (2 * numChannels)
            val floats = FloatArray(sampleCount)

            var byteIdx = dataOffset
            for (i in 0 until sampleCount) {
                val s = bb.getShort(byteIdx)
                floats[i] = (s.toFloat() / 32768.0f).coerceIn(-1.0f, 1.0f)
                byteIdx += 2 * numChannels // if stereo, read left channel only
            }

            return floats
        } catch (e: Throwable) {
            Log.e(TAG, "Failed to read WAV file: ${e.message}")
            return null
        }
    }
}
