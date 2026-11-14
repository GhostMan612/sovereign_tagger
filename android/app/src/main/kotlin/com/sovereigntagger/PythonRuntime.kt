// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import android.content.Context
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import java.io.File

object PythonRuntime {
    const val OVERLAY_DIR_NAME = "sovereign_py_overlay"

    @Volatile
    private var initialized = false
    private val initLock = Any()

    fun overlayRootDir(context: Context): File =
        File(context.applicationContext.filesDir, OVERLAY_DIR_NAME)

    fun overlayRootPath(context: Context): String =
        overlayRootDir(context).canonicalPath

    fun resolveContainedDirectory(rootDir: File, childName: String): File {
        require(childName.isNotBlank()) { "Overlay child name must not be blank." }
        require(!childName.contains("/") && !childName.contains("\\") && !childName.contains("..")) {
            "Overlay child name must stay within overlay root."
        }
        val rootCanonical = rootDir.canonicalFile
        val childCanonical = File(rootCanonical, childName).canonicalFile
        val rootPath = rootCanonical.path
        val childPath = childCanonical.path
        require(childPath.startsWith(rootPath + File.separator)) {
            "Overlay child escapes root container."
        }
        return childCanonical
    }

    fun ensureInitialized(context: Context): Python {
        synchronized(initLock) {
            val appContext = context.applicationContext
            if (!Python.isStarted()) {
                Python.start(AndroidPlatform(appContext))
            }
            val py = Python.getInstance()
            if (!initialized) {
                val overlayPath = overlayRootPath(appContext)
                val bootstrapModule = py.getModule("sovereign_yt.overlay_bootstrap")
                bootstrapModule.callAttr("bootstrap", overlayPath, BuildConfig.YTDLP_BUNDLED_VERSION)
                initialized = true
            }
            return py
        }
    }
}
