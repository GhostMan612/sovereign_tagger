// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import com.chaquo.python.PyObject

object CoreUpdaterBridge {
    @Volatile
    private var fixture: ((PyObject, Boolean) -> String)? = null

    fun configureForInstrumentation(callback: (PyObject, Boolean) -> String) {
        check(BuildConfig.APPLICATION_ID == "com.sovereigntagger.updateracceptance")
        fixture = callback
    }

    fun clearInstrumentationFixture() {
        fixture = null
    }

    fun execute(module: PyObject, fullStack: Boolean): String {
        check(BuildConfig.APPLICATION_ID == "com.sovereigntagger.updateracceptance")
        val configured = checkNotNull(fixture) { "Isolated updater fixture is not configured." }
        return configured(module, fullStack)
    }
}
