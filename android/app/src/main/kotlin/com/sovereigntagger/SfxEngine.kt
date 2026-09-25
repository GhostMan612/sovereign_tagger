// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import android.media.AudioAttributes
import android.media.SoundPool
import java.util.concurrent.ConcurrentHashMap

class SfxEngine {
    private val pool: SoundPool = SoundPool.Builder()
        .setMaxStreams(8)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
        )
        .build()
    private val ids = ConcurrentHashMap<String, Int>()
    private val ready = ConcurrentHashMap<Int, Boolean>()

    init {
        pool.setOnLoadCompleteListener { _, sampleId, status ->
            if (status == 0) ready[sampleId] = true
        }
    }

    fun load(name: String, path: String) {
        ids.remove(name)?.let {
            ready.remove(it)
            pool.unload(it)
        }
        ids[name] = pool.load(path, 1)
    }

    fun play(name: String, volume: Float, rate: Float): Boolean {
        val id = ids[name] ?: return false
        if (ready[id] != true) return false
        val v = volume.coerceIn(0f, 1f)
        return pool.play(id, v, v, 1, 0, rate.coerceIn(0.5f, 2f)) != 0
    }

    fun release() {
        ids.clear()
        ready.clear()
        pool.release()
    }
}
