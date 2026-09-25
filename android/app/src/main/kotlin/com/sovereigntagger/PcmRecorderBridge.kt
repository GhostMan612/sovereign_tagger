// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.core.content.ContextCompat
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile

class PcmRecorderBridge(private val context: Context) {

    private var audioRecord: AudioRecord? = null
    private var recordingThread: Thread? = null
    @Volatile private var isRecording = false
    @Volatile var amplitudeListener: ((Int) -> Unit)? = null
    private var lastEmitMs = 0L
    private var wavFile: File? = null
    private var sampleRate: Int = 48000
    private var channelCount: Int = 1
    private var bitsPerSample: Int = 16

    fun hasPermission(): Boolean {
        return ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    }

    fun startRecording(path: String, reqSampleRate: Int, reqChannels: Int): Boolean {
        try {
            if (isRecording) return false
            sampleRate = if (reqSampleRate in 8000..96000) reqSampleRate else 48000
            channelCount = if (reqChannels == 2) 2 else 1
            bitsPerSample = 16

            val channelConfig = if (channelCount == 2) AudioFormat.CHANNEL_IN_STEREO else AudioFormat.CHANNEL_IN_MONO
            val audioFormat = AudioFormat.ENCODING_PCM_16BIT
            val minBuf = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
            if (minBuf <= 0) return false
            val bufferSize = minBuf * 2

            wavFile = File(path)
            wavFile!!.parentFile?.mkdirs()
            if (wavFile!!.exists()) wavFile!!.delete()
            writeWavHeaderPlaceholder(wavFile!!, sampleRate, channelCount, bitsPerSample)

            audioRecord = AudioRecord(MediaRecorder.AudioSource.MIC, sampleRate, channelConfig, audioFormat, bufferSize)
            if (audioRecord!!.state != AudioRecord.STATE_INITIALIZED) {
                audioRecord?.release()
                audioRecord = null
                return false
            }
            audioRecord!!.startRecording()
            isRecording = true

            recordingThread = Thread {
                val buffer = ShortArray(bufferSize / 2)
                val byteBuf = java.nio.ByteBuffer.allocate(bufferSize).order(java.nio.ByteOrder.LITTLE_ENDIAN)
                val fos = FileOutputStream(wavFile!!, true)
                try {
                    while (isRecording) {
                        val read = audioRecord?.read(buffer, 0, buffer.size) ?: 0
                        if (read > 0) {
                            byteBuf.clear()
                            var peak = 0
                            for (i in 0 until read) {
                                val s = buffer[i]
                                byteBuf.putShort(s)
                                val v: Int = if (s < 0) -s.toInt() else s.toInt()
                                if (v > peak) peak = v
                            }
                            fos.write(byteBuf.array(), 0, read * 2)
                            val listener = amplitudeListener
                            if (listener != null) {
                                val now = System.currentTimeMillis()
                                if (now - lastEmitMs >= 50) {
                                    lastEmitMs = now
                                    listener(peak)
                                }
                            }
                        }
                    }
                } catch (_: Exception) {
                } finally {
                    try { fos.flush(); fos.close() } catch (_: Exception) {}
                }
            }.apply {
                priority = Thread.MAX_PRIORITY
                start()
            }
            return true
        } catch (e: Exception) {
            try { audioRecord?.release() } catch (_: Exception) {}
            audioRecord = null
            isRecording = false
            return false
        }
    }

    fun stopRecording(): String? {
        if (!isRecording) return null
        isRecording = false
        try { recordingThread?.join(800) } catch (_: Exception) {}
        recordingThread = null
        try {
            audioRecord?.stop()
        } catch (_: Exception) {}
        try { audioRecord?.release() } catch (_: Exception) {}
        audioRecord = null
        val f = wavFile
        wavFile = null
        if (f != null && f.exists()) {
            finalizeWavHeader(f, sampleRate, channelCount, bitsPerSample)
            return f.absolutePath
        }
        return null
    }

    fun isRecordingNow(): Boolean = isRecording

    private fun writeWavHeaderPlaceholder(file: File, sr: Int, channels: Int, bits: Int) {
        val byteRate = sr * channels * bits / 8
        val blockAlign = channels * bits / 8
        val header = java.nio.ByteBuffer.allocate(44).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray())
        header.putInt(36)
        header.put("WAVE".toByteArray())
        header.put("fmt ".toByteArray())
        header.putInt(16)
        header.putShort(1)
        header.putShort(channels.toShort())
        header.putInt(sr)
        header.putInt(byteRate)
        header.putShort(blockAlign.toShort())
        header.putShort(bits.toShort())
        header.put("data".toByteArray())
        header.putInt(0)
        FileOutputStream(file).use { it.write(header.array()) }
    }

    private fun finalizeWavHeader(file: File, sr: Int, channels: Int, bits: Int) {
        try {
            val fileLen = file.length()
            val dataLen = (fileLen - 44).toInt().coerceAtLeast(0)
            val riffLen = (36 + dataLen)
            RandomAccessFile(file, "rw").use { raf ->
                raf.seek(4)
                raf.writeInt(java.lang.Integer.reverseBytes(riffLen))
                raf.seek(40)
                raf.writeInt(java.lang.Integer.reverseBytes(dataLen))
            }
        } catch (_: Exception) {}
    }
}
