// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class PythonOverlayContractTest {
    @get:Rule
    val tempFolder = TemporaryFolder()

    @Test
    fun resolveContainedDirectoryAcceptsValidChildWithinOverlayRoot() {
        val root = tempFolder.newFolder("sovereign_py_overlay")
        val slots = PythonRuntime.resolveContainedDirectory(root, "slots")
        assertEquals(File(root.canonicalFile, "slots").canonicalPath, slots.canonicalPath)
        assertTrue(slots.canonicalPath.startsWith(root.canonicalPath + File.separator))
    }

    @Test
    fun resolveContainedDirectoryRejectsTraversalAndSeparators() {
        val root = tempFolder.newFolder("sovereign_py_overlay")
        assertThrows(IllegalArgumentException::class.java) {
            PythonRuntime.resolveContainedDirectory(root, "../escape")
        }
        assertThrows(IllegalArgumentException::class.java) {
            PythonRuntime.resolveContainedDirectory(root, "a/b")
        }
        assertThrows(IllegalArgumentException::class.java) {
            PythonRuntime.resolveContainedDirectory(root, "")
        }
    }
}
