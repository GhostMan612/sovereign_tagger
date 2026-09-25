// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform

class MainActivity: AudioServiceActivity() {
    private val YTDLP_CHANNEL = "com.sovereign.tagger/ytdlp"
    private val EVENT_CHANNEL = "com.sovereign.tagger/ytdlp_events"
    private val ID3_CHANNEL = "com.sovereign.tagger/id3"
    private val ACRCLOUD_CHANNEL = "com.sovereign.tagger/acrcloud"
    private val STORAGE_CHANNEL = "com.sovereign.tagger/storage"
    private val SPIDER_CHANNEL = "com.sovereign.tagger/spider"
    private val SHARE_CHANNEL = "com.sovereign.tagger/share"
    private val WIDGET_CHANNEL = "com.sovereign.tagger/widget"

    private val REQ_WRITE = 7301
    private val REQ_DELETE = 7302
    private val REQ_RECOVERABLE_WRITE = 7303
    private val REQ_RECOVERABLE_DELETE = 7304

    private val pcmRecorderBridge by lazy { PcmRecorderBridge(this) }
    private val pcmRecorderChannel = "com.sovereign.tagger/pcm_recorder"
    private val pcmEventChannel = "com.sovereign.tagger/pcm_events"

    private var eventSink: EventChannel.EventSink? = null
    private var pcmEventSink: EventChannel.EventSink? = null
    private var shareSink: EventChannel.EventSink? = null
    private var pendingShare: String? = null
    private val storageBridge by lazy { StorageBridge(this) }

    private var pendingGrantResult: MethodChannel.Result? = null
    private val recoverableQueue = ArrayDeque<Uri>()
    private var recoverableDeleting = false

    private val pythonEngine: Python by lazy {
        if (!Python.isStarted()) Python.start(AndroidPlatform(this))
        Python.getInstance()
    }

    private val ytBridgeModule by lazy { pythonEngine.getModule("sovereign_yt.bridge") }
    private val ytUpdaterModule by lazy { pythonEngine.getModule("sovereign_yt.updater") }
    private val spiderPythonModule by lazy { pythonEngine.getModule("sovereign_yt.spider") }
    private val doctorPythonModule by lazy { pythonEngine.getModule("sovereign_yt.doctor") }

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureShare(intent)
    }

    private fun captureShare(intent: Intent?) {
        if (intent == null || intent.action != Intent.ACTION_SEND) return
        if (intent.type?.startsWith("text/") != true) return
        val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return
        val url = Regex("https?://\\S+").find(text)?.value ?: text.trim()
        if (url.isEmpty()) return
        intent.removeExtra(Intent.EXTRA_TEXT)
        val sink = shareSink
        if (sink != null) sink.success(url) else pendingShare = url
    }

    private fun runAsync(result: MethodChannel.Result, code: String, block: () -> Any?) {
        Thread {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                mainHandler.post { result.error(code, e.message, null) }
            }
        }.start()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { eventSink = events }
                override fun onCancel(arguments: Any?) { eventSink = null }
            }
        )

        EventChannel(messenger, SHARE_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    shareSink = events
                    val pending = pendingShare
                    if (pending != null && events != null) {
                        pendingShare = null
                        events.success(pending)
                    }
                }
                override fun onCancel(arguments: Any?) { shareSink = null }
            }
        )

        EventChannel(messenger, pcmEventChannel).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    pcmEventSink = events
                    pcmRecorderBridge.amplitudeListener = { amp ->
                        mainHandler.post { pcmEventSink?.success(amp) }
                    }
                }
                override fun onCancel(arguments: Any?) {
                    pcmRecorderBridge.amplitudeListener = null
                    pcmEventSink = null
                }
            }
        )

        MethodChannel(messenger, YTDLP_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "searchMedia" -> {
                    val query = call.argument<String>("query") ?: ""
                    val source = call.argument<String>("source") ?: "youtube"
                    runAsync(result, "PYTHON_ERROR") { ytBridgeModule.callAttr("search_media", query, source, 15).toString() }
                }
                "getFormats" -> {
                    val url = call.argument<String>("url")
                    runAsync(result, "PYTHON_ERROR") { ytBridgeModule.callAttr("get_available_formats", url).toString() }
                }
                "cancelDownload" -> {
                    val jobId = call.argument<String>("jobId") ?: "default"
                    runAsync(result, "CANCEL_ERROR") { ytBridgeModule.callAttr("cancel", jobId).toString() }
                }
                "fetchThumbnail" -> {
                    val url = call.argument<String>("url") ?: ""
                    val outPath = call.argument<String>("outPath") ?: ""
                    runAsync(result, "THUMB_ERROR") { ytBridgeModule.callAttr("fetch_thumbnail", url, outPath).toString() }
                }
                "updateCore" -> runAsync(result, "UPDATE_ERROR") { ytUpdaterModule.callAttr("execute_scorched_earth").toString() }
                "updateFullStack" -> runAsync(result, "UPDATE_ERROR") { ytUpdaterModule.callAttr("execute_full_scorched_earth").toString() }
                "runDoctor" -> {
                    val errorLog = call.argument<String>("errorLog") ?: ""
                    runAsync(result, "DOCTOR_ERROR") { doctorPythonModule.callAttr("diagnose", errorLog).toString() }
                }
                "getDoctorRegistry" -> runAsync(result, "DOCTOR_ERROR") { doctorPythonModule.callAttr("get_registry").toString() }
                "downloadMedia" -> {
                    val url = call.argument<String>("url")
                    val jobId = call.argument<String>("jobId") ?: "default"
                    val optionsJson = call.argument<String>("optionsJson") ?: "{}"
                    val outDir = context.getExternalFilesDir(null)?.absolutePath ?: context.cacheDir.absolutePath
                    val progressCallback = object {
                        fun invoke(jsonStr: String) {
                            mainHandler.post { eventSink?.success(jsonStr) }
                        }
                    }
                    runAsync(result, "DOWNLOAD_ERROR") { ytBridgeModule.callAttr("download", url, optionsJson, jobId, outDir, progressCallback).toString() }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, ID3_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "writeTags" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    val metadata = call.argument<Map<String, String>>("metadata") ?: emptyMap()
                    Thread {
                        val success = Id3Tagger.writeTags(filePath, metadata)
                        mainHandler.post {
                            if (success) result.success(true)
                            else result.error("TAG_ERROR", "Failed to write tags", null)
                        }
                    }.start()
                }
                "readTags" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    Thread {
                        val tags = Id3Tagger.readTags(filePath)
                        mainHandler.post { result.success(tags) }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, ACRCLOUD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    val host = call.argument<String>("host") ?: ""
                    val accessKey = call.argument<String>("accessKey") ?: ""
                    val accessSecret = call.argument<String>("accessSecret") ?: ""
                    AcrCloudBridge.initialize(host, accessKey, accessSecret)
                    result.success(true)
                }
                "identify" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    runAsync(result, "ACR_ERROR") { AcrCloudBridge.identify(filePath) }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, SPIDER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scrape" -> {
                    val artist = call.argument<String>("artist") ?: ""
                    val title = call.argument<String>("title") ?: ""
                    val geniusKey = call.argument<String>("geniusKey") ?: ""
                    val album = call.argument<String>("album") ?: ""
                    val durationMs = call.argument<Number>("durationMs")?.toInt() ?: 0
                    runAsync(result, "SPIDER_ERROR") { spiderPythonModule.callAttr("scrape_metadata", artist, title, geniusKey, durationMs, album).toString() }
                }
                "fetchLyrics" -> {
                    val artist = call.argument<String>("artist") ?: ""
                    val title = call.argument<String>("title") ?: ""
                    val album = call.argument<String>("album") ?: ""
                    val durationMs = call.argument<Number>("durationMs")?.toInt() ?: 0
                    runAsync(result, "SPIDER_ERROR") { spiderPythonModule.callAttr("fetch_lyrics", artist, title, album, durationMs).toString() }
                }
                "fetchArtwork" -> {
                    val url = call.argument<String>("url") ?: ""
                    runAsync(result, "SPIDER_ERROR") { spiderPythonModule.callAttr("fetch_artwork", url).toString() }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, STORAGE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "addToMediaStore" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    val title = call.argument<String>("title") ?: "Sovereign_Audio"
                    runAsync(result, "STORAGE_ERROR") { storageBridge.addToMediaStore(filePath, title)["uri"] }
                }
                "exportToLibrary" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    val title = call.argument<String>("title") ?: "Sovereign_Audio"
                    runAsync(result, "STORAGE_ERROR") { storageBridge.addToMediaStore(filePath, title) }
                }
                "queryAudio" -> runAsync(result, "STORAGE_ERROR") { storageBridge.queryAudio() }
                "loadArtwork" -> {
                    val uri = call.argument<String>("uri") ?: ""
                    val size = call.argument<Int>("size") ?: 256
                    runAsync(result, "STORAGE_ERROR") { storageBridge.loadArtwork(uri, size) }
                }
                "resolveMediaUri" -> {
                    val identifier = call.argument<String>("identifier")
                    val path = call.argument<String>("path")
                    runAsync(result, "STORAGE_ERROR") { storageBridge.resolveMediaUri(identifier, path) }
                }
                "describeMedia" -> {
                    val uri = call.argument<String>("uri") ?: ""
                    runAsync(result, "STORAGE_ERROR") { storageBridge.describe(Uri.parse(uri)) }
                }
                "requestWriteAccess" -> {
                    val uris = call.argument<List<String>>("uris") ?: emptyList()
                    requestWriteAccess(uris, result)
                }
                "requestDelete" -> {
                    val uris = call.argument<List<String>>("uris") ?: emptyList()
                    requestDelete(uris, result)
                }
                "overwriteMedia" -> {
                    val uri = call.argument<String>("uri") ?: ""
                    val srcPath = call.argument<String>("srcPath") ?: ""
                    val newName = call.argument<String>("displayName")
                    runAsync(result, "STORAGE_ERROR") { storageBridge.overwriteMedia(uri, srcPath, newName) }
                }
                "scanFile" -> {
                    val path = call.argument<String>("path") ?: ""
                    storageBridge.scan(path)
                    result.success(true)
                }
                "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                "exportConfig" -> {
                    val data = call.argument<String>("data") ?: ""
                    runAsync(result, "STORAGE_ERROR") { storageBridge.exportConfig(data) }
                }
                "autoImportConfig" -> runAsync(result, "STORAGE_ERROR") { storageBridge.autoImportConfig() }
                "getTempDirectory" -> { result.success(storageBridge.getTempDirectory()) }
                "openUrl" -> {
                    val url = call.argument<String>("url") ?: ""
                    try {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("URL_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, WIDGET_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    val title = call.argument<String>("title") ?: ""
                    val artist = call.argument<String>("artist") ?: ""
                    val playing = call.argument<Boolean>("playing") ?: false
                    SovereignWidgetProvider.pushState(this, title, artist, playing)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, pcmRecorderChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(pcmRecorderBridge.hasPermission())
                "isRecording" -> result.success(pcmRecorderBridge.isRecordingNow())
                "startRecording" -> {
                    val path = call.argument<String>("path") ?: ""
                    val sampleRate = call.argument<Int>("sampleRate") ?: 48000
                    val channels = call.argument<Int>("channels") ?: 1
                    Thread {
                        val ok = pcmRecorderBridge.startRecording(path, sampleRate, channels)
                        mainHandler.post {
                            if (ok) result.success(true) else result.error("PCM_ERROR", "Failed to start PCM recorder", null)
                        }
                    }.start()
                }
                "stopRecording" -> {
                    Thread {
                        val outPath = pcmRecorderBridge.stopRecording()
                        mainHandler.post {
                            if (outPath != null) result.success(outPath) else result.error("PCM_ERROR", "No recording active", null)
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun finishGrant(granted: Boolean) {
        val r = pendingGrantResult
        pendingGrantResult = null
        recoverableQueue.clear()
        r?.success(granted)
    }

    private fun requestWriteAccess(uris: List<String>, result: MethodChannel.Result) {
        if (pendingGrantResult != null) {
            result.error("BUSY", "Another permission request is active", null)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success(true)
            return
        }
        val needed = storageBridge.urisNeedingWriteGrant(uris)
        if (needed.isEmpty()) {
            result.success(true)
            return
        }
        pendingGrantResult = result
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val pending = MediaStore.createWriteRequest(contentResolver, needed)
                startIntentSenderForResult(pending.intentSender, REQ_WRITE, null, 0, 0, 0)
            } else {
                recoverableDeleting = false
                recoverableQueue.clear()
                recoverableQueue.addAll(needed)
                advanceRecoverable()
            }
        } catch (e: Exception) {
            pendingGrantResult = null
            result.error("GRANT_ERROR", e.message, null)
        }
    }

    private fun requestDelete(uris: List<String>, result: MethodChannel.Result) {
        if (pendingGrantResult != null) {
            result.error("BUSY", "Another permission request is active", null)
            return
        }
        val parsed = uris.map { Uri.parse(it) }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                pendingGrantResult = result
                val pending = MediaStore.createDeleteRequest(contentResolver, parsed)
                startIntentSenderForResult(pending.intentSender, REQ_DELETE, null, 0, 0, 0)
            } else if (Build.VERSION.SDK_INT == Build.VERSION_CODES.Q) {
                pendingGrantResult = result
                recoverableDeleting = true
                recoverableQueue.clear()
                recoverableQueue.addAll(parsed)
                advanceRecoverable()
            } else {
                result.success(uris.all { storageBridge.deleteDirect(it) })
            }
        } catch (e: Exception) {
            pendingGrantResult = null
            result.error("DELETE_ERROR", e.message, null)
        }
    }

    private fun advanceRecoverable() {
        while (recoverableQueue.isNotEmpty()) {
            val uri = recoverableQueue.first()
            try {
                if (recoverableDeleting) {
                    contentResolver.delete(uri, null, null)
                } else {
                    contentResolver.openFileDescriptor(uri, "rw")?.close()
                }
                recoverableQueue.removeFirst()
            } catch (e: Exception) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && e is RecoverableSecurityException) {
                    try {
                        startIntentSenderForResult(e.userAction.actionIntent.intentSender, if (recoverableDeleting) REQ_RECOVERABLE_DELETE else REQ_RECOVERABLE_WRITE, null, 0, 0, 0)
                    } catch (_: Exception) {
                        finishGrant(false)
                    }
                    return
                }
                finishGrant(false)
                return
            }
        }
        finishGrant(true)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        when (requestCode) {
            REQ_WRITE, REQ_DELETE -> finishGrant(resultCode == Activity.RESULT_OK)
            REQ_RECOVERABLE_WRITE, REQ_RECOVERABLE_DELETE -> {
                if (resultCode == Activity.RESULT_OK) advanceRecoverable() else finishGrant(false)
            }
            else -> super.onActivityResult(requestCode, resultCode, data)
        }
    }
}
