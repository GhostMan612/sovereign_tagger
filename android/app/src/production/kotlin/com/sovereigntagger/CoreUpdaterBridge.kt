// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import android.content.Context
import com.chaquo.python.PyObject

object CoreUpdaterBridge {
    fun execute(context: Context, module: PyObject, fullStack: Boolean): String {
        val overlayRoot = PythonRuntime.overlayRootPath(context)
        return if (fullStack) {
            module.callAttr(
                "execute_full_scorched_earth",
                overlayRoot,
                BuildConfig.YTDLP_BUNDLED_VERSION,
            ).toString()
        } else {
            module.callAttr(
                "execute_scorched_earth",
                overlayRoot,
                null,
                BuildConfig.YTDLP_BUNDLED_VERSION,
            ).toString()
        }
    }

    fun status(context: Context, module: PyObject): String {
        val overlayRoot = PythonRuntime.overlayRootPath(context)
        return module.callAttr(
            "get_status",
            overlayRoot,
            BuildConfig.YTDLP_BUNDLED_VERSION,
        ).toString()
    }
}
