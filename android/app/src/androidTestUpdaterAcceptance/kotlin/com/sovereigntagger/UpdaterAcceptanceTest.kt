// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import android.content.Context
import android.content.pm.PackageInfo
import android.os.Process
import android.util.Log
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Configurator
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.UiScrollable
import androidx.test.uiautomator.UiSelector
import androidx.test.uiautomator.Until
import com.chaquo.python.PyObject
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class UpdaterAcceptanceTest {
    private val timeout = 60_000L
    private val buttonText = "CHECK FOR YT-DLP UPDATE"

    @Test(timeout = 360_000L)
    fun isolatedUpdaterThroughSettings() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        assertEquals("com.sovereigntagger.updateracceptance", context.packageName)
        assertEquals(context.packageName, BuildConfig.APPLICATION_ID)
        val originalBefore = originalPackage(context)
        assertNotEquals(originalBefore.applicationInfo!!.uid, context.applicationInfo.uid)
        val phase = InstrumentationRegistry.getArguments().getString("phase", "all")
        assertTrue(phase in setOf("all", "failure", "restart"))
        val base = File(context.filesDir, "updater_acceptance").canonicalFile
        val fixtureRoot = File(base, if (phase == "all") "all" else "restart").canonicalFile
        assertTrue(fixtureRoot.path.startsWith(context.filesDir.canonicalPath + File.separator))
        if (!Python.isStarted()) Python.start(AndroidPlatform(context))
        val python = Python.getInstance()
        val updater = python.getModule("sovereign_yt.updater")
        val fixture = checkNotNull(python.getModule("types").callAttr("ModuleType", "sovereign_updater_acceptance_fixture"))
        val source = instrumentation.context.assets.open("updater_acceptance_fixture.py")
            .bufferedReader(Charsets.UTF_8).use { it.readText() }
        python.builtins.callAttr("exec", source, fixture.get("__dict__"))
        fixture.callAttr("initialize", fixtureRoot.path, updater, phase != "restart")
        val reports = JSONArray()
        val mode = AtomicReference("success")
        val response = AtomicReference<JSONObject?>()
        val exception = AtomicReference<Throwable?>()
        val latch = AtomicReference(CountDownLatch(1))
        var scenario: ActivityScenario<MainActivity>? = null
        val configurator = Configurator.getInstance()
        val previousIdleTimeout = configurator.waitForIdleTimeout
        configurator.waitForIdleTimeout = 250L
        try {
            CoreUpdaterBridge.clearInstrumentationFixture()
            var unconfiguredBlocked = true
            for (fullStack in listOf(false, true)) {
                var blocked = false
                try {
                    CoreUpdaterBridge.execute(updater, fullStack)
                } catch (_: IllegalStateException) {
                    blocked = true
                }
                unconfiguredBlocked = unconfiguredBlocked && blocked
            }
            assertTrue("Unconfigured acceptance build must fail closed", unconfiguredBlocked)
            CoreUpdaterBridge.configureForInstrumentation { actualModule, fullStack ->
                check(!fullStack) { "Full-stack fixture is not configured." }
                try {
                    val raw = fixture.callAttr("run", actualModule, mode.get()).toString()
                    response.set(JSONObject(raw))
                    raw
                } catch (failure: Throwable) {
                    exception.set(failure)
                    throw failure
                } finally {
                    latch.get().countDown()
                }
            }
            scenario = ActivityScenario.launch(MainActivity::class.java)
            val device = UiDevice.getInstance(instrumentation)
            if (phase == "all") {
                invoke(device, mode, response, exception, latch, "success")
                val success = snapshot(fixture)
                assertSuccessful(success)
                reports.put(success.put("acceptance_phase", "initial_success"))
            }
            if (phase != "restart") {
                invoke(device, mode, response, exception, latch, "failure")
                val failed = snapshot(fixture)
                assertRecoveryEvidence(failed)
                assertTrue(failed.getJSONObject("last_response").getBoolean("recovery_required"))
                assertNotNull(scrollToLabel(device, "RECOVERY REQUIRED"))
                reports.put(failed.put("acceptance_phase", "failed_restore"))
            } else {
                val preserved = snapshot(fixture)
                assertRecoveryEvidence(preserved)
                assertNotEquals("Restart must use a new app process", preserved.getInt("failure_pid"), Process.myPid())
                reports.put(preserved.put("acceptance_phase", "preserved_after_process_restart"))
            }
            if (phase != "failure") {
                invoke(device, mode, response, exception, latch, "retry")
                val retry = snapshot(fixture)
                assertSuccessful(retry)
                reports.put(retry.put("acceptance_phase", "retry_success"))
            }
            val originalAfter = originalPackage(context)
            assertEquals(originalBefore.longVersionCode, originalAfter.longVersionCode)
            assertEquals(originalBefore.lastUpdateTime, originalAfter.lastUpdateTime)
            assertEquals(originalBefore.firstInstallTime, originalAfter.firstInstallTime)
            assertEquals(originalBefore.applicationInfo!!.uid, originalAfter.applicationInfo!!.uid)
            base.mkdirs()
            val evidence = JSONObject()
                .put("status", "passed")
                .put("phase", phase)
                .put("package", context.packageName)
                .put("source_sha", BuildConfig.SOURCE_SHA)
                .put("source_dirty", BuildConfig.SOURCE_DIRTY)
                .put("apk_sha256", digest(File(context.applicationInfo.sourceDir)))
                .put("original_package", "com.sovereigntagger")
                .put("original_package_uid", originalAfter.applicationInfo!!.uid)
                .put("original_package_last_update", originalAfter.lastUpdateTime)
                .put("original_package_unchanged", true)
                .put("distinct_application_uid", true)
                .put("unconfigured_bridge_blocked", unconfiguredBlocked)
                .put("reports", reports)
            File(base, "evidence-$phase.json").writeText(evidence.toString(2), Charsets.UTF_8)
            Log.i("UpdaterAcceptance", "PASS phase=$phase source=${BuildConfig.SOURCE_SHA} dirty=${BuildConfig.SOURCE_DIRTY} package=${context.packageName}")
        } finally {
            configurator.waitForIdleTimeout = previousIdleTimeout
            CoreUpdaterBridge.clearInstrumentationFixture()
            scenario?.close()
        }
    }

    private fun invoke(
        device: UiDevice,
        mode: AtomicReference<String>,
        response: AtomicReference<JSONObject?>,
        exception: AtomicReference<Throwable?>,
        latch: AtomicReference<CountDownLatch>,
        next: String,
    ) {
        mode.set(next)
        response.set(null)
        exception.set(null)
        val completion = CountDownLatch(1)
        latch.set(completion)
        scrollToLabel(device, buttonText).click()
        assertTrue("Updater callback timed out", completion.await(timeout, TimeUnit.MILLISECONDS))
        exception.get()?.let { throw AssertionError("Isolated updater invocation failed", it) }
        val result = checkNotNull(response.get())
        val message = if (result.optBoolean("recovery_required")) "RECOVERY REQUIRED" else result.getString("message")
        assertNotNull(scrollToLabel(device, message))
    }

    private fun scrollToLabel(device: UiDevice, label: String): UiObject2 {
        assertTrue("Settings scroll semantics were not ready", device.wait(Until.hasObject(By.scrollable(true)), timeout))
        fun visible(): UiObject2? {
            val candidates = listOfNotNull(
                device.findObject(By.textContains(label)),
                device.findObject(By.descContains(label)),
            )
            return candidates.firstOrNull { !it.visibleBounds.isEmpty }
        }
        visible()?.let { return it }
        val scroll = UiScrollable(UiSelector().scrollable(true)).setAsVerticalList()
        scroll.setMaxSearchSwipes(60)
        scroll.scrollToBeginning(60)
        for (attempt in 0 until 60) {
            visible()?.let { return it }
            if (!scroll.scrollForward()) break
        }
        return visible() ?: throw AssertionError("Settings label was not visible through text or description: $label")
    }

    private fun snapshot(fixture: PyObject): JSONObject = JSONObject(fixture.callAttr("snapshot").toString())

    private fun assertSuccessful(snapshot: JSONObject) {
        assertEquals("success", snapshot.getJSONObject("last_response").getString("status"))
        assertTrue(snapshot.getBoolean("target_exists"))
        assertTrue(snapshot.getString("target_version_source").contains("2026.11.14"))
        assertFalse(snapshot.getBoolean("backup_exists"))
        assertFalse(snapshot.getBoolean("journal_exists"))
        assertFalse(snapshot.getBoolean("staging_exists"))
        assertTrue(snapshot.getBoolean("runtime_import_fingerprint_unchanged"))
    }

    private fun assertRecoveryEvidence(snapshot: JSONObject) {
        assertFalse(snapshot.getBoolean("target_exists"))
        assertTrue(snapshot.getBoolean("backup_exists"))
        assertTrue(snapshot.getBoolean("journal_exists"))
        assertTrue(snapshot.getBoolean("staging_exists"))
        assertEquals(snapshot.getString("expected_backup_sha256"), snapshot.getString("backup_sha256"))
        assertTrue(snapshot.getBoolean("runtime_import_fingerprint_unchanged"))
    }

    private fun originalPackage(context: Context): PackageInfo = context.packageManager
        .getPackageInfo("com.sovereigntagger", 0)

    private fun digest(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { stream ->
            val buffer = ByteArray(65536)
            while (true) {
                val count = stream.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
