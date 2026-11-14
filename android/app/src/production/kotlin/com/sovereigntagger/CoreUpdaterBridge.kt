// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import com.chaquo.python.PyObject

object CoreUpdaterBridge {
    fun execute(module: PyObject, fullStack: Boolean): String = module.callAttr(
        if (fullStack) "execute_full_scorched_earth" else "execute_scorched_earth"
    ).toString()
}
