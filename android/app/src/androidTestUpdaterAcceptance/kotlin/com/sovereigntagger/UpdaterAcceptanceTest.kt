// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import android.content.Context
import android.util.Log
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Configurator
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.StaleObjectException
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import com.chaquo.python.PyObject
import com.chaquo.python.Python
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class UpdaterAcceptanceTest {
    private val bundledVersion = BuildConfig.YTDLP_BUNDLED_VERSION

    @Before
    fun configureUiAutomator() {
        val cfg = Configurator.getInstance()
        cfg.waitForIdleTimeout = 400L
        cfg.waitForSelectorTimeout = 1500L
    }

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
        File(targetDir, "__pycache__").deleteRecursively()
        val destFile = File(targetDir, "updater_acceptance_fixture.py")
        destFile.delete()
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

    private fun ensureSettingsRendered(device: UiDevice) {
        val readyDeadline = System.currentTimeMillis() + 35000L
        while (System.currentTimeMillis() < readyDeadline) {
            if (device.findObject(By.scrollable(true)) != null ||
                findByTextOrDesc(device, "BUNDLED YT-DLP") != null ||
                findByTextOrDesc(device, "SETTINGS") != null
            ) {
                return
            }
            Thread.sleep(300L)
        }
    }

    private fun dumpAllScreenNodes(device: UiDevice): String {
        val pkg = targetContext().packageName
        val nodes = device.findObjects(By.pkg(pkg))
        val labels = nodes.mapNotNull { obj ->
            try {
                val t = (obj.text ?: obj.contentDescription ?: "").trim()
                if (t.isEmpty()) {
                    null
                } else {
                    val b = obj.visibleBounds
                    "${t.replace("\n", " | ")}@[${b.top}..${b.bottom}]"
                }
            } catch (_: StaleObjectException) {
                null
            }
        }.distinct()
        return if (labels.isEmpty()) "<no visible nodes>" else labels.joinToString("; ")
    }

    private fun dumpDiagnostics(device: UiDevice): String {
        val interesting = device.findObjects(By.clazz("android.view.View")) +
            device.findObjects(By.clazz("android.widget.Button"))
        val labels = interesting.mapNotNull { obj ->
            val t = obj.text ?: obj.contentDescription ?: ""
            if (t.contains("YT-DLP", ignoreCase = true) ||
                t.contains("OVERLAY", ignoreCase = true) ||
                t.contains("ERR:", ignoreCase = true) ||
                t.contains("UPDAT", ignoreCase = true) ||
                t.contains("ROLLBACK", ignoreCase = true) ||
                t.contains("RECOVERY", ignoreCase = true) ||
                t.contains("Core Engine", ignoreCase = true)
            ) {
                t.replace("\n", " | ")
            } else {
                null
            }
        }.distinct()
        return if (labels.isEmpty()) dumpAllScreenNodes(device) else labels.joinToString("; ")
    }

    private fun waitForSettingsScrollAndFind(
        device: UiDevice,
        textSubstring: String,
        timeoutMs: Long = 12000L,
    ): UiObject2 {
        ensureSettingsRendered(device)
        val initialEnd = System.currentTimeMillis() + 2500L
        while (System.currentTimeMillis() < initialEnd) {
            findByTextOrDesc(device, textSubstring)?.let { return it }
            Thread.sleep(250L)
        }
        for (step in 0 until 12) {
            val scroller = device.findObject(By.scrollable(true)) ?: break
            scroller.scroll(Direction.DOWN, 0.75f)
            Thread.sleep(250L)
            findByTextOrDesc(device, textSubstring)?.let { return it }
        }
        for (step in 0 until 12) {
            val scroller = device.findObject(By.scrollable(true)) ?: break
            scroller.scroll(Direction.UP, 0.75f)
            Thread.sleep(250L)
            findByTextOrDesc(device, textSubstring)?.let { return it }
        }
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            findByTextOrDesc(device, textSubstring)?.let { return it }
            Thread.sleep(250L)
        }
        throw IllegalStateException(
            "Expected UI element containing '$textSubstring' (visible: ${dumpDiagnostics(device)})"
        )
    }

    private fun clickSettingsButton(device: UiDevice, labelSubstring: String) {
        var btn = waitForSettingsScrollAndFind(device, labelSubstring)
        for (adj in 0 until 4) {
            val b = btn.visibleBounds
            val h = device.displayHeight
            val scroller = device.findObject(By.scrollable(true))
            if (scroller == null) break
            if (b.top < 320 || b.height() < 30) {
                scroller.scroll(Direction.UP, 0.35f)
                Thread.sleep(300L)
                btn = findByTextOrDesc(device, labelSubstring) ?: btn
            } else if (b.bottom > h - 200) {
                scroller.scroll(Direction.DOWN, 0.35f)
                Thread.sleep(300L)
                btn = findByTextOrDesc(device, labelSubstring) ?: btn
            } else {
                break
            }
        }
        val target = if (btn.isClickable) btn else btn.parent?.takeIf { it.isClickable } ?: btn
        val b = target.visibleBounds
        Log.i(
            "UpdaterAcceptance",
            "Clicking '$labelSubstring' bounds=[${b.left},${b.top}..${b.right},${b.bottom}] clickable=${btn.isClickable} targetClickable=${target.isClickable} cls=${target.className}"
        )
        target.click()
    }

    private fun waitAfterActionForText(
        device: UiDevice,
        textSubstring: String,
        timeoutMs: Long = 20000L,
    ): UiObject2 {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            findByTextOrDesc(device, textSubstring)?.let { return it }
            findByTextOrDesc(device, "ERR:")?.let {
                val dump = dumpAllScreenNodes(device)
                Log.e("UpdaterAcceptance", "UI showed error while waiting for '$textSubstring': $dump")
                throw IllegalStateException("Updater UI showed error waiting for '$textSubstring': $dump")
            }
            Thread.sleep(300L)
        }
        val beforeScroll = dumpAllScreenNodes(device)
        Log.w("UpdaterAcceptance", "Timeout waiting for '$textSubstring'; nodes before scroll: $beforeScroll")
        for (step in 0 until 6) {
            val scroller = device.findObject(By.scrollable(true)) ?: break
            scroller.scroll(Direction.UP, 0.45f)
            Thread.sleep(250L)
            findByTextOrDesc(device, textSubstring)?.let { return it }
            findByTextOrDesc(device, "ERR:")?.let {
                throw IllegalStateException("Updater UI showed error waiting for '$textSubstring': ${dumpAllScreenNodes(device)}")
            }
        }
        for (step in 0 until 10) {
            val scroller = device.findObject(By.scrollable(true)) ?: break
            scroller.scroll(Direction.DOWN, 0.45f)
            Thread.sleep(250L)
            findByTextOrDesc(device, textSubstring)?.let { return it }
            findByTextOrDesc(device, "ERR:")?.let {
                throw IllegalStateException("Updater UI showed error waiting for '$textSubstring': ${dumpAllScreenNodes(device)}")
            }
        }
        throw IllegalStateException(
            "Expected UI element containing '$textSubstring' (beforeScroll: $beforeScroll | afterScroll: ${dumpAllScreenNodes(device)})"
        )
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
                Log.i("UpdaterAcceptance", "phase1 bridge callback fullStack=$fullStack")
                val res = if (fullStack) {
                    fixture.callAttr("execute_full_stack_check", overlayRoot, bundledVersion).toString()
                } else {
                    fixture.callAttr("stage_synthetic_release", overlayRoot, "2099.01.02", bundledVersion, false).toString()
                }
                Log.i("UpdaterAcceptance", "phase1 bridge result=$res")
                res
            }
        )

        ActivityScenario.launch(MainActivity::class.java).use {
            val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
            waitForSettingsScrollAndFind(device, "BUNDLED YT-DLP: $bundledVersion")
            waitForSettingsScrollAndFind(device, "ACTIVE YT-DLP: $bundledVersion (BUNDLED)")
            waitForSettingsScrollAndFind(device, "MUTAGEN AND LYRICSGENIUS")
            clickSettingsButton(device, "CHECK FOR YT-DLP UPDATE")

            waitAfterActionForText(device, "PENDING OVERLAY: 2099.01.02", timeoutMs = 25000L)
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
                Log.i("UpdaterAcceptance", "phase2 bridge callback fullStack=$fullStack")
                val res = if (fullStack) {
                    fixture.callAttr("execute_full_stack_check", overlayRoot, bundledVersion).toString()
                } else {
                    fixture.callAttr("stage_synthetic_release", overlayRoot, "2099.02.03", bundledVersion, true).toString()
                }
                Log.i("UpdaterAcceptance", "phase2 bridge result=$res")
                res
            }
        )

        ActivityScenario.launch(MainActivity::class.java).use {
            val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
            waitForSettingsScrollAndFind(device, "BUNDLED YT-DLP: $bundledVersion")
            waitForSettingsScrollAndFind(device, "ACTIVE YT-DLP: 2099.01.02 (OVERLAY)")
            clickSettingsButton(device, "CHECK FOR YT-DLP UPDATE")

            waitAfterActionForText(device, "PENDING OVERLAY: 2099.02.03", timeoutMs = 25000L)
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

    @Test
    fun phase5_liveGitHubAuthenticityAndOverlayStage() {
        val ctx = targetContext()
        PythonRuntime.overlayRootDir(ctx).deleteRecursively()

        val py = PythonRuntime.ensureInitialized(ctx)
        val fixture = installFixtureModule(py)
        val overlayRoot = overlayRootPath()

        CoreUpdaterBridge.configureForInstrumentation(
            callback = { _, _, fullStack ->
                Log.i("UpdaterAcceptance", "phase5 bridge callback fullStack=$fullStack")
                val res = if (fullStack) {
                    fixture.callAttr("execute_full_stack_check", overlayRoot, bundledVersion).toString()
                } else {
                    fixture.callAttr("stage_live_github_release", overlayRoot).toString()
                }
                Log.i("UpdaterAcceptance", "phase5 bridge result=$res")
                res
            }
        )

        ActivityScenario.launch(MainActivity::class.java).use {
            val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
            waitForSettingsScrollAndFind(device, "BUNDLED YT-DLP: $bundledVersion")
            waitForSettingsScrollAndFind(device, "ACTIVE YT-DLP: $bundledVersion (BUNDLED)")
            clickSettingsButton(device, "CHECK FOR YT-DLP UPDATE")

            waitAfterActionForText(device, "PENDING OVERLAY:", timeoutMs = 90000L)
            waitForSettingsScrollAndFind(device, "ACTIVE YT-DLP: 2026.01.01 (BUNDLED)")
        }

        val postStageInfo = JSONObject(fixture.callAttr("inspect_live_ytdlp", overlayRoot).toString())
        assertEquals(bundledVersion, postStageInfo.getString("version"))
        assertFalse(postStageInfo.getBoolean("inside_overlay_slots"))
        val rtState = postStageInfo.getJSONObject("runtime_state")
        assertTrue(rtState.getBoolean("restart_required"))
        assertTrue(rtState.optString("pending_version", "").isNotBlank())
    }

    @Test
    fun phase6_liveGitHubOverlayActivatesAfterRestart() {
        val ctx = targetContext()
        val py = PythonRuntime.ensureInitialized(ctx)
        val fixture = installFixtureModule(py)
        val overlayRoot = overlayRootPath()

        val liveInfoRaw = fixture.callAttr("inspect_live_ytdlp", overlayRoot).toString()
        Log.i("UpdaterAcceptance", "phase6 inspect_live_ytdlp=$liveInfoRaw")
        val liveInfo = JSONObject(liveInfoRaw)
        val liveVer = liveInfo.getString("version")
        assertTrue(liveVer.isNotBlank())
        assertTrue(liveInfo.getBoolean("inside_overlay_slots"))
        assertTrue(liveInfo.getString("file").contains("sovereign_py_overlay"))
        val rtState = liveInfo.getJSONObject("runtime_state")
        assertEquals("overlay", rtState.getString("active_source"))
        assertEquals(liveVer, rtState.getString("active_version"))
        assertFalse(rtState.getBoolean("restart_required"))
        assertFalse(rtState.getBoolean("rolled_back"))

        ActivityScenario.launch(MainActivity::class.java).use {
            val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
            waitForSettingsScrollAndFind(device, "BUNDLED YT-DLP: $bundledVersion")
            waitForSettingsScrollAndFind(device, "ACTIVE YT-DLP: $liveVer (OVERLAY)")
        }
    }
}
