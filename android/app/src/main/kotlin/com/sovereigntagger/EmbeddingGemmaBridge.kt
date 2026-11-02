// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import android.app.ActivityManager
import android.content.ComponentCallbacks2
import android.content.Context
import android.util.Log
import org.tensorflow.lite.DataType
import org.tensorflow.lite.Interpreter
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import kotlin.math.min
import kotlin.math.sqrt

class EmbeddingGemmaBridge(private val context: Context) {
    private val executor = Executors.newSingleThreadScheduledExecutor { r ->
        Thread(r, "EmbeddingGemmaWorker").apply { isDaemon = true }
    }

    @Volatile private var interpreter: Interpreter? = null
    @Volatile private var tokenizer: SentencePieceTokenizer? = null
    private var mappedModel: MappedByteBuffer? = null
    @Volatile private var configuredModelPath: String? = null
    @Volatile private var configuredTokenizerPath: String? = null
    @Volatile private var seqLen: Int = 256
    @Volatile private var outputDim: Int = 768
    @Volatile private var lastError: String? = null
    private var idleUnloadFuture: ScheduledFuture<*>? = null

    private fun defaultDir(): File = File(context.filesDir, "embedding_gemma")

    private fun resolvePaths(modelPath: String?, tokenizerPath: String?): Pair<File, File> {
        val dir = defaultDir()
        val mFile = if (!modelPath.isNullOrBlank()) {
            File(modelPath)
        } else {
            val saved = configuredModelPath
            if (!saved.isNullOrBlank()) File(saved) else File(dir, DEFAULT_MODEL_FILE)
        }
        val tFile = if (!tokenizerPath.isNullOrBlank()) {
            File(tokenizerPath)
        } else {
            val saved = configuredTokenizerPath
            if (!saved.isNullOrBlank()) File(saved) else File(dir, DEFAULT_TOKENIZER_FILE)
        }
        return Pair(mFile, tFile)
    }

    fun isAvailable(): Boolean {
        if (interpreter != null && tokenizer != null) return true
        val (mFile, tFile) = resolvePaths(null, null)
        return mFile.exists() && mFile.length() >= MIN_MODEL_BYTES &&
            tFile.exists() && tFile.length() >= MIN_TOKENIZER_BYTES
    }

    fun getStatus(): Map<String, Any?> {
        val mem = readMemoryInfo()
        val (mFile, tFile) = resolvePaths(null, null)
        val filesReady = mFile.exists() && mFile.length() >= MIN_MODEL_BYTES &&
            tFile.exists() && tFile.length() >= MIN_TOKENIZER_BYTES
        return hashMapOf(
            "loaded" to (interpreter != null && tokenizer != null),
            "filesReady" to filesReady,
            "modelPath" to mFile.absolutePath,
            "tokenizerPath" to tFile.absolutePath,
            "modelBytes" to if (mFile.exists()) mFile.length() else 0L,
            "tokenizerBytes" to if (tFile.exists()) tFile.length() else 0L,
            "seqLen" to seqLen,
            "outputDim" to outputDim,
            "availRamMb" to (mem.availMem / (1024L * 1024L)),
            "totalRamMb" to (mem.totalMem / (1024L * 1024L)),
            "lowMemory" to mem.lowMemory,
            "lastError" to lastError,
        )
    }

    fun loadModel(
        modelPath: String?,
        tokenizerPath: String?,
        callback: (Map<String, Any?>?, String?) -> Unit,
    ) {
        executor.execute {
            try {
                loadInternal(modelPath, tokenizerPath)
                scheduleIdleUnloadIfConstrained()
                callback(getStatus(), null)
            } catch (t: Throwable) {
                Log.e(TAG, "Failed to load EmbeddingGemma", t)
                lastError = t.message ?: t.toString()
                closeInternal()
                callback(null, lastError)
            }
        }
    }

    fun unloadModel(callback: ((Boolean) -> Unit)? = null) {
        executor.execute {
            closeInternal()
            callback?.invoke(true)
        }
    }

    fun onTrimMemory(level: Int) {
        if (level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW ||
            level >= ComponentCallbacks2.TRIM_MEMORY_BACKGROUND
        ) {
            Log.w(TAG, "System memory trim ($level) — unloading EmbeddingGemma interpreter")
            unloadModel()
        }
    }

    fun embedText(
        text: String,
        dims: Int,
        task: String,
        title: String?,
        callback: (FloatArray?, String?) -> Unit,
    ) {
        executor.execute {
            try {
                ensureLoadedInternal()
                val formatted = formatPrompt(text, task, title)
                val vec = runSingleInference(formatted, dims.coerceIn(32, 768))
                scheduleIdleUnloadIfConstrained()
                callback(vec, null)
            } catch (t: Throwable) {
                Log.e(TAG, "EmbeddingGemma embedText failed", t)
                lastError = t.message ?: t.toString()
                callback(null, lastError)
            }
        }
    }

    fun embedBatch(
        texts: List<String>,
        titles: List<String>?,
        dims: Int,
        task: String,
        callback: (ArrayList<FloatArray>?, String?) -> Unit,
    ) {
        executor.execute {
            try {
                ensureLoadedInternal()
                val clampedDims = dims.coerceIn(32, 768)
                val out = ArrayList<FloatArray>(texts.size)
                for (i in texts.indices) {
                    val tTitle = if (titles != null && i < titles.size) titles[i] else null
                    val formatted = formatPrompt(texts[i], task, tTitle)
                    out.add(runSingleInference(formatted, clampedDims))
                }
                scheduleIdleUnloadIfConstrained()
                callback(out, null)
            } catch (t: Throwable) {
                Log.e(TAG, "EmbeddingGemma embedBatch failed", t)
                lastError = t.message ?: t.toString()
                callback(null, lastError)
            }
        }
    }

    fun release() {
        try {
            executor.execute { closeInternal() }
            executor.shutdown()
        } catch (_: Throwable) {}
    }

    private fun ensureLoadedInternal() {
        if (interpreter != null && tokenizer != null) return
        loadInternal(configuredModelPath, configuredTokenizerPath)
    }

    private fun loadInternal(modelPath: String?, tokenizerPath: String?) {
        val (mFile, tFile) = resolvePaths(modelPath, tokenizerPath)
        require(mFile.exists() && mFile.length() >= MIN_MODEL_BYTES) {
            "EmbeddingGemma .tflite missing or incomplete at ${mFile.absolutePath}"
        }
        require(tFile.exists() && tFile.length() >= MIN_TOKENIZER_BYTES) {
            "SentencePiece tokenizer missing or incomplete at ${tFile.absolutePath}"
        }

        val mem = readMemoryInfo()
        if (mem.lowMemory || mem.availMem < 260L * 1024L * 1024L) {
            throw IllegalStateException(
                "Low device RAM (${mem.availMem / (1024L * 1024L)} MB free) — deferring EmbeddingGemma load"
            )
        }

        closeInternal()

        val sp = SentencePieceTokenizer.load(tFile)
        val mapped = mapReadOnly(mFile)
        val options = Interpreter.Options().apply {
            setNumThreads(4)
            setUseXNNPACK(true)
        }
        val interp = Interpreter(mapped, options)

        val inTensor0 = interp.getInputTensor(0)
        val shape0 = inTensor0.shape()
        if (shape0.isNotEmpty() && shape0.last() <= 1) {
            interp.resizeInput(0, intArrayOf(1, DEFAULT_SEQ_LEN))
            for (idx in 1 until interp.inputTensorCount) {
                val s = interp.getInputTensor(idx).shape()
                if (s.isNotEmpty() && s.last() <= 1) {
                    interp.resizeInput(idx, intArrayOf(1, DEFAULT_SEQ_LEN))
                }
            }
        }
        interp.allocateTensors()

        val resolvedInShape = interp.getInputTensor(0).shape()
        val resolvedOutShape = interp.getOutputTensor(0).shape()
        seqLen = if (resolvedInShape.isNotEmpty()) resolvedInShape.last().coerceAtLeast(16) else DEFAULT_SEQ_LEN
        outputDim = if (resolvedOutShape.isNotEmpty()) resolvedOutShape.last().coerceAtLeast(64) else 768

        configuredModelPath = mFile.absolutePath
        configuredTokenizerPath = tFile.absolutePath
        mappedModel = mapped
        tokenizer = sp
        interpreter = interp
        lastError = null
        Log.i(TAG, "Loaded EmbeddingGemma (${mFile.name}, seq=$seqLen, out=$outputDim, vocab=${sp.vocabSize})")
    }

    private fun runSingleInference(promptText: String, targetDims: Int): FloatArray {
        val interp = interpreter ?: throw IllegalStateException("Interpreter not loaded")
        val sp = tokenizer ?: throw IllegalStateException("Tokenizer not loaded")

        val rawIds = sp.encode(promptText, addBos = true, addEos = true)
        val maxLen = seqLen
        val validLen = min(rawIds.size, maxLen)
        val paddedIds = IntArray(maxLen) { sp.padId.coerceAtLeast(0) }
        for (i in 0 until validLen) {
            paddedIds[i] = rawIds[i]
        }
        if (rawIds.size > maxLen && sp.eosId >= 0) {
            paddedIds[maxLen - 1] = sp.eosId
        }

        val inputCount = interp.inputTensorCount
        val inputs = Array<Any>(inputCount) { idx ->
            val tensor = interp.getInputTensor(idx)
            val name = tensor.name().lowercase()
            val numElem = tensor.numElements()
            val values = IntArray(numElem)
            when {
                idx == 0 || name.contains("token") || name.contains("input_id") -> {
                    for (k in 0 until min(numElem, paddedIds.size)) values[k] = paddedIds[k]
                }
                name.contains("pos") -> {
                    for (k in 0 until numElem) values[k] = k % maxLen
                }
                else -> {
                    for (k in 0 until numElem) values[k] = if ((k % maxLen) < validLen) 1 else 0
                }
            }
            buildInputBuffer(tensor.dataType(), tensor.numBytes(), values)
        }

        val outTensor = interp.getOutputTensor(0)
        val outBuf = ByteBuffer.allocateDirect(outTensor.numBytes()).order(ByteOrder.nativeOrder())
        val outputs = HashMap<Int, Any>(2)
        outputs[0] = outBuf

        interp.runForMultipleInputsOutputs(inputs, outputs)

        outBuf.rewind()
        val outShape = outTensor.shape()
        val hiddenDim = if (outShape.isNotEmpty()) outShape.last() else outputDim
        val rawVec = FloatArray(hiddenDim)

        if (outTensor.dataType() == DataType.FLOAT32) {
            val floatBuf = outBuf.asFloatBuffer()
            if (outShape.size >= 3 && outShape[outShape.size - 2] > 1) {
                val steps = min(validLen.coerceAtLeast(1), outShape[outShape.size - 2])
                for (s in 0 until steps) {
                    val base = s * hiddenDim
                    for (d in 0 until hiddenDim) {
                        rawVec[d] += floatBuf.get(base + d)
                    }
                }
                val invSteps = 1.0f / steps.toFloat()
                for (d in 0 until hiddenDim) rawVec[d] *= invSteps
            } else {
                val lim = min(hiddenDim, floatBuf.remaining())
                for (d in 0 until lim) rawVec[d] = floatBuf.get(d)
            }
        } else {
            val lim = min(hiddenDim, outBuf.remaining())
            for (d in 0 until lim) rawVec[d] = outBuf.get(d).toFloat()
        }

        val finalDim = min(targetDims, hiddenDim)
        val truncated = FloatArray(finalDim)
        var sumSq = 0.0
        for (i in 0 until finalDim) {
            val v = rawVec[i]
            truncated[i] = v
            sumSq += (v * v).toDouble()
        }
        if (sumSq > 1e-12) {
            val inv = (1.0 / sqrt(sumSq)).toFloat()
            for (i in 0 until finalDim) {
                truncated[i] *= inv
            }
        }
        return truncated
    }

    private fun buildInputBuffer(dtype: DataType, numBytes: Int, values: IntArray): ByteBuffer {
        val buf = ByteBuffer.allocateDirect(numBytes).order(ByteOrder.nativeOrder())
        when (dtype) {
            DataType.INT64 -> {
                val lb = buf.asLongBuffer()
                for (i in 0 until min(values.size, lb.remaining())) lb.put(values[i].toLong())
            }
            DataType.FLOAT32 -> {
                val fb = buf.asFloatBuffer()
                for (i in 0 until min(values.size, fb.remaining())) fb.put(values[i].toFloat())
            }
            DataType.BOOL, DataType.UINT8, DataType.INT8 -> {
                for (i in 0 until min(values.size, buf.remaining())) buf.put(values[i].toByte())
            }
            else -> {
                val ib = buf.asIntBuffer()
                for (i in 0 until min(values.size, ib.remaining())) ib.put(values[i])
            }
        }
        buf.rewind()
        return buf
    }

    private fun formatPrompt(text: String, task: String, title: String?): String {
        val clean = text.trim()
        if (clean.startsWith("task:") || clean.startsWith("title:")) return clean
        return when (task.lowercase()) {
            "document", "doc" -> {
                val safeTitle = if (title.isNullOrBlank()) "none" else title.trim()
                "title: $safeTitle | text: $clean"
            }
            "similarity" -> "task: sentence similarity | query: $clean"
            else -> "task: search result | query: $clean"
        }
    }

    private fun scheduleIdleUnloadIfConstrained() {
        idleUnloadFuture?.cancel(false)
        val mem = readMemoryInfo()
        val sixGb = 6L * 1024L * 1024L * 1024L
        val delayMs = if (mem.totalMem < sixGb) IDLE_UNLOAD_MS else IDLE_UNLOAD_HIGH_RAM_MS
        idleUnloadFuture = executor.schedule({
            Log.i(TAG, "Unloading idle EmbeddingGemma interpreter to conserve RAM")
            closeInternal()
        }, delayMs, TimeUnit.MILLISECONDS)
    }

    private fun closeInternal() {
        idleUnloadFuture?.cancel(false)
        idleUnloadFuture = null
        try {
            interpreter?.close()
        } catch (_: Throwable) {}
        interpreter = null
        tokenizer = null
        mappedModel = null
    }

    private fun mapReadOnly(file: File): MappedByteBuffer {
        RandomAccessFile(file, "r").use { raf ->
            raf.channel.use { ch ->
                return ch.map(FileChannel.MapMode.READ_ONLY, 0L, ch.size())
            }
        }
    }

    private fun readMemoryInfo(): ActivityManager.MemoryInfo {
        val info = ActivityManager.MemoryInfo()
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        am?.getMemoryInfo(info)
        return info
    }

    companion object {
        private const val TAG = "EmbeddingGemmaBridge"
        const val DEFAULT_MODEL_FILE = "embeddinggemma-300m_seq256_mixed-precision.tflite"
        const val DEFAULT_TOKENIZER_FILE = "sentencepiece.model"
        private const val DEFAULT_SEQ_LEN = 256
        private const val MIN_MODEL_BYTES = 16L * 1024L * 1024L
        private const val MIN_TOKENIZER_BYTES = 100L * 1024L
        private const val IDLE_UNLOAD_MS = 5L * 60L * 1000L
        private const val IDLE_UNLOAD_HIGH_RAM_MS = 15L * 60L * 1000L
    }
}
