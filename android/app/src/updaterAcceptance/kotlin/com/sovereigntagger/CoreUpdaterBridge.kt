// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import android.content.Context
import com.chaquo.python.PyObject

object CoreUpdaterBridge {
    @Volatile
    private var fixture: ((Context, PyObject, Boolean) -> String)? = null

    @Volatile
    private var statusFixture: ((Context, PyObject) -> String)? = null

    fun configureForInstrumentation(
        callback: (Context, PyObject, Boolean) -> String,
        statusCallback: ((Context, PyObject) -> String)? = null,
    ) {
        check(BuildConfig.APPLICATION_ID == "com.sovereigntagger.updateracceptance")
        fixture = callback
        statusFixture = statusCallback
    }

    fun clearInstrumentationFixture() {
        fixture = null
        statusFixture = null
    }

    fun execute(context: Context, module: PyObject, fullStack: Boolean): String {
        check(BuildConfig.APPLICATION_ID == "com.sovereigntagger.updateracceptance")
        val configured = checkNotNull(fixture) { "Isolated updater fixture is not configured." }
        return configured(context, module, fullStack)
    }

    fun status(context: Context, module: PyObject): String {
        check(BuildConfig.APPLICATION_ID == "com.sovereigntagger.updateracceptance")
        val configuredStatus = statusFixture
        if (configuredStatus != null) {
            return configuredStatus(context, module)
        }
        val overlayRoot = PythonRuntime.overlayRootPath(context)
        return module.callAttr(
            "get_status",
            overlayRoot,
            BuildConfig.YTDLP_BUNDLED_VERSION,
        ).toString()
    }
}
