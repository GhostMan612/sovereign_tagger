// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import android.content.Context
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.UiScrollable
import androidx.test.uiautomator.UiSelector
import com.chaquo.python.PyObject
import com.chaquo.python.Python
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class UpdaterAcceptanceTest {
    private val bundledVersion = BuildConfig.YTDLP_BUNDLED_VERSION

    @After
    fun tearDown() {
        CoreUpdaterBridge.clearInstrumentationFixture()
    }

    private fun instrumentationContext(): Context =
        InstrumentationRegistry.getInstrumentation().context

    private fun targetContext(): Context =
        InstrumentationRegistry.getInstrumentation().targetContext

    private fun overlayRootPath(): String =
        PythonRuntime.overlayRootPath(targetContext())

    private fun installFixtureModule(py: Python): PyObject {
        val targetDir = File(targetContext().cacheDir, "acceptance_py")
        targetDir.mkdirs()
        val destFile = File(targetDir, "updater_acceptance_fixture.py")
        instrumentationContext().assets.open("updater_acceptance_fixture.py").use { input ->
            destFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        val sysMod = py.getModule("sys")
        val pathObj = sysMod["path"]
        val pathList = pathObj?.asList()?.map { it.toString() } ?: emptyList()
        if (!pathList.contains(targetDir.absolutePath)) {
            pathObj?.callAttr("insert", 0, targetDir.absolutePath)
        }
        return py.getModule("updater_acceptance_fixture")
    }

    private fun findByTextOrDesc(device: UiDevice, textSubstring: String): UiObject2? {
        return device.findObject(By.textContains(textSubstring))
            ?: device.findObject(By.descContains(textSubstring))
    }

    private fun waitForSettingsScrollAndFind(device: UiDevice, textSubstring: String): UiObject2 {
        val start = System.currentTimeMillis()
        while (System.currentTimeMillis() - start < 4000) {
            findByTextOrDesc(device, textSubstring)?.let { return it }
            Thread.sleep(200)
        }
        val scrollable = UiScrollable(UiSelector().scrollable(true))
        if (scrollable.exists()) {
            for (step in 0 until 12) {
                scrollable.scrollForward()
                Thread.sleep(350)
                findByTextOrDesc(device, textSubstring)?.let { return it }
            }
            for (step in 0 until 12) {
                scrollable.scrollBackward()
                Thread.sleep(350)
                findByTextOrDesc(device, textSubstring)?.let { return it }
            }
        }
        val deadline = System.currentTimeMillis() + 8000
        while (System.currentTimeMillis() < deadline) {
            findByTextOrDesc(device, textSubstring)?.let { return it }
            Thread.sleep(250)
        }
        return checkNotNull(findByTextOrDesc(device, textSubstring)) {
            "Expected UI element containing '$textSubstring'"
        }
    }

    @Test
    fun phase1_stageOverlayUpdateAndVerifyNoHotSwap() {
        val ctx = targetContext()
        PythonRuntime.overlayRootDir(ctx).deleteRecursively()

        val py = PythonRuntime.ensureInitialized(ctx)
        val fixture = installFixtureModule(py)
        val overlayRoot = overlayRootPath()

        val initialInfo = JSONObject(fixture.callAttr("inspect_live_ytdlp", overlayRoot).toString())
        assertEquals(bundledVersion, initialInfo.getString("version"))
        assertFalse(initialInfo.getBoolean("inside_overlay_slots"))
        assertEquals("bundled", initialInfo.getJSONObject("runtime_state").getString("active_source"))

        val fullStackRes = JSONObject(
            fixture.callAttr("execute_full_stack_check", overlayRoot, bundledVersion).toString()
        )
        assertEquals("requires_apk_update", fullStackRes.getString("status"))
        assertTrue(fullStackRes.getBoolean("core_updatable"))
        assertFalse(File(overlayRoot).exists())

        CoreUpdaterBridge.configureForInstrumentation(
            callback = { _, _, fullStack ->
                if (fullStack) {
                    fixture.callAttr("execute_full_stack_check", overlayRoot, bundledVersion).toString()
                } else {
                    fixture.callAttr("stage_synthetic_release", overlayRoot, "2099.01.02", bundledVersion, false).toString()
                }
            }
        )

        ActivityScenario.launch(MainActivity::class.java).use {
            val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
            waitForSettingsScrollAndFind(device, "BUNDLED YT-DLP: $bundledVersion")
            waitForSettingsScrollAndFind(device, "ACTIVE YT-DLP: $bundledVersion (BUNDLED)")
            waitForSettingsScrollAndFind(device, "MUTAGEN AND LYRICSGENIUS")
            val btn = waitForSettingsScrollAndFind(device, "CHECK FOR YT-DLP UPDATE")
            btn.click()

            waitForSettingsScrollAndFind(device, "PENDING OVERLAY: 2099.01.02")
            waitForSettingsScrollAndFind(device, "ACTIVE YT-DLP: $bundledVersion (BUNDLED)")
        }

        val postStageInfo = JSONObject(fixture.callAttr("inspect_live_ytdlp", overlayRoot).toString())
        assertEquals(bundledVersion, postStageInfo.getString("version"))
        assertFalse(postStageInfo.getBoolean("inside_overlay_slots"))
    }

    @Test
    fun phase2_freshProcessActivatesOverlayAndStagesFaultyCandidate() {
        val ctx = targetContext()
        val py = PythonRuntime.ensureInitialized(ctx)
        val fixture = installFixtureModule(py)
        val overlayRoot = overlayRootPath()

        val activeInfo = JSONObject(fixture.callAttr("inspect_live_ytdlp", overlayRoot).toString())
        assertEquals("2099.01.02", activeInfo.getString("version"))
        assertTrue(activeInfo.getBoolean("inside_overlay_slots"))
        assertTrue(activeInfo.getString("file").contains("sovereign_py_overlay"))
        assertEquals("overlay", activeInfo.getJSONObject("runtime_state").getString("active_source"))

        CoreUpdaterBridge.configureForInstrumentation(
            callback = { _, _, fullStack ->
                if (fullStack) {
                    fixture.callAttr("execute_full_stack_check", overlayRoot, bundledVersion).toString()
                } else {
                    fixture.callAttr("stage_synthetic_release", overlayRoot, "2099.02.03", bundledVersion, true).toString()
                }
            }
        )

        ActivityScenario.launch(MainActivity::class.java).use {
            val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
            waitForSettingsScrollAndFind(device, "BUNDLED YT-DLP: $bundledVersion")
            waitForSettingsScrollAndFind(device, "ACTIVE YT-DLP: 2099.01.02 (OVERLAY)")
            val btn = waitForSettingsScrollAndFind(device, "CHECK FOR YT-DLP UPDATE")
            btn.click()

            waitForSettingsScrollAndFind(device, "PENDING OVERLAY: 2099.02.03")
        }
    }

    @Test
    fun phase3_freshProcessRollsBackBrokenPendingToPriorOverlay() {
        val ctx = targetContext()
        val py = PythonRuntime.ensureInitialized(ctx)
        val fixture = installFixtureModule(py)
        val overlayRoot = overlayRootPath()

        val rolledInfo = JSONObject(fixture.callAttr("inspect_live_ytdlp", overlayRoot).toString())
        assertEquals("2099.01.02", rolledInfo.getString("version"))
        assertTrue(rolledInfo.getBoolean("inside_overlay_slots"))
        val rtState = rolledInfo.getJSONObject("runtime_state")
        assertEquals("overlay", rtState.getString("active_source"))
        assertTrue(rtState.getBoolean("rolled_back"))
        assertEquals("2099.02.03", rtState.getString("rolled_back_from"))

        ActivityScenario.launch(MainActivity::class.java).use {
            val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
            waitForSettingsScrollAndFind(device, "ACTIVE YT-DLP: 2099.01.02 (OVERLAY)")
            waitForSettingsScrollAndFind(device, "ROLLBACK NOTICE: REVERTED FROM 2099.02.03")
        }

        fixture.callAttr("corrupt_all_overlay_slots_for_bundled_fallback", overlayRoot)
    }

    @Test
    fun phase4_corruptOverlayFallsBackToBundledImy() {
        val ctx = targetContext()
        val py = PythonRuntime.ensureInitialized(ctx)
        val fixture = installFixtureModule(py)
        val overlayRoot = overlayRootPath()

        val bundledInfo = JSONObject(fixture.callAttr("inspect_live_ytdlp", overlayRoot).toString())
        assertEquals(bundledVersion, bundledInfo.getString("version"))
        assertFalse(bundledInfo.getBoolean("inside_overlay_slots"))
        assertEquals("bundled", bundledInfo.getJSONObject("runtime_state").getString("active_source"))

        ActivityScenario.launch(MainActivity::class.java).use {
            val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
            waitForSettingsScrollAndFind(device, "BUNDLED YT-DLP: $bundledVersion")
            waitForSettingsScrollAndFind(device, "ACTIVE YT-DLP: $bundledVersion (BUNDLED)")
        }
    }
}
