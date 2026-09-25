// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import android.os.Handler
import android.os.Looper
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

    private val pcmRecorderBridge by lazy { PcmRecorderBridge(this) }
    private val pcmRecorderChannel = "com.sovereign.tagger/pcm_recorder"
    private val pcmEventChannel = "com.sovereign.tagger/pcm_events"

    private var eventSink: EventChannel.EventSink? = null
    private var pcmEventSink: EventChannel.EventSink? = null
    private val storageBridge by lazy { StorageBridge(this) }

    private val pythonEngine: Python by lazy {
        if (!Python.isStarted()) Python.start(AndroidPlatform(this))
        Python.getInstance()
    }

    private val ytBridgeModule by lazy { pythonEngine.getModule("sovereign_yt.bridge") }
    private val ytUpdaterModule by lazy { pythonEngine.getModule("sovereign_yt.updater") }
    private val spiderPythonModule by lazy { pythonEngine.getModule("sovereign_yt.spider") }
    private val doctorPythonModule by lazy { pythonEngine.getModule("sovereign_yt.doctor") }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { eventSink = events }
                override fun onCancel(arguments: Any?) { eventSink = null }
            }
        )

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, pcmEventChannel).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    pcmEventSink = events
                    pcmRecorderBridge.amplitudeListener = { amp ->
                        Handler(Looper.getMainLooper()).post { pcmEventSink?.success(amp) }
                    }
                }
                override fun onCancel(arguments: Any?) {
                    pcmRecorderBridge.amplitudeListener = null
                    pcmEventSink = null
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, YTDLP_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "searchMedia" -> {
                    val query = call.argument<String>("query") ?: ""
                    val source = call.argument<String>("source") ?: "youtube"
                    Thread {
                        try {
                            val jsonResult = ytBridgeModule.callAttr("search_media", query, source, 15).toString()
                            Handler(Looper.getMainLooper()).post { result.success(jsonResult) }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.error("PYTHON_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "getFormats" -> {
                    val url = call.argument<String>("url")
                    Thread {
                        try {
                            val jsonResult = ytBridgeModule.callAttr("get_available_formats", url).toString()
                            Handler(Looper.getMainLooper()).post { result.success(jsonResult) }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.error("PYTHON_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "cancelDownload" -> {
                    val jobId = call.argument<String>("jobId") ?: "default"
                    Thread {
                        try {
                            val jsonResult = ytBridgeModule.callAttr("cancel", jobId).toString()
                            Handler(Looper.getMainLooper()).post { result.success(jsonResult) }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.error("CANCEL_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "updateCore" -> {
                    Thread {
                        try {
                            val jsonResult = ytUpdaterModule.callAttr("execute_scorched_earth").toString()
                            Handler(Looper.getMainLooper()).post { result.success(jsonResult) }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.error("UPDATE_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "updateFullStack" -> {
                    Thread {
                        try {
                            val jsonResult = ytUpdaterModule.callAttr("execute_full_scorched_earth").toString()
                            Handler(Looper.getMainLooper()).post { result.success(jsonResult) }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.error("UPDATE_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "runDoctor" -> {
                    val errorLog = call.argument<String>("errorLog") ?: ""
                    Thread {
                        try {
                            val jsonResult = doctorPythonModule.callAttr("diagnose", errorLog).toString()
                            Handler(Looper.getMainLooper()).post { result.success(jsonResult) }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.error("DOCTOR_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "getDoctorRegistry" -> {
                    Thread {
                        try {
                            val jsonResult = doctorPythonModule.callAttr("get_registry").toString()
                            Handler(Looper.getMainLooper()).post { result.success(jsonResult) }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.error("DOCTOR_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "downloadMedia" -> {
                    val url = call.argument<String>("url")
                    val formatId = call.argument<String>("formatId")
                    val jobId = call.argument<String>("jobId") ?: "default"
                    val optionsJson = call.argument<String>("optionsJson") ?: "{}"
                    val outDir = context.getExternalFilesDir(null)?.absolutePath ?: context.cacheDir.absolutePath
                    
                    Thread {
                        try {
                            val progressCallback = object {
                                fun invoke(jsonStr: String) {
                                    Handler(Looper.getMainLooper()).post { eventSink?.success(jsonStr) }
                                }
                            }
                            val resultJson = ytBridgeModule.callAttr("download", url, optionsJson, jobId, outDir, progressCallback).toString()
                            Handler(Looper.getMainLooper()).post { result.success(resultJson) }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.error("DOWNLOAD_ERROR", e.message, null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ID3_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "writeTags" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    val metadata = call.argument<Map<String, String>>("metadata") ?: emptyMap()
                    Thread {
                        val success = Id3Tagger.writeTags(filePath, metadata)
                        Handler(Looper.getMainLooper()).post { 
                            if (success) result.success(true) 
                            else result.error("TAG_ERROR", "Failed to write tags", null)
                        }
                    }.start()
                }
                "readTags" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    Thread {
                        val tags = Id3Tagger.readTags(filePath)
                        Handler(Looper.getMainLooper()).post { result.success(tags) }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ACRCLOUD_CHANNEL).setMethodCallHandler { call, result ->
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
                    Thread {
                        try {
                            val jsonResponse = AcrCloudBridge.identify(filePath)
                            Handler(Looper.getMainLooper()).post { result.success(jsonResponse) }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.error("ACR_ERROR", e.message, null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SPIDER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scrape" -> {
                    val artist = call.argument<String>("artist") ?: ""
                    val title = call.argument<String>("title") ?: ""
                    val geniusKey = call.argument<String>("geniusKey") ?: ""
                    Thread {
                        try {
                            val jsonResult = spiderPythonModule.callAttr("scrape_metadata", artist, title, geniusKey).toString()
                            Handler(Looper.getMainLooper()).post { result.success(jsonResult) }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.error("SPIDER_ERROR", e.message, null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "addToMediaStore" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    val title = call.argument<String>("title") ?: "Sovereign_Audio"
                    Thread {
                        try {
                            val uri = storageBridge.addToMediaStore(filePath, title)
                            Handler(Looper.getMainLooper()).post { result.success(uri) }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.error("STORAGE_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "exportConfig" -> {
                    val data = call.argument<String>("data") ?: ""
                    Thread {
                        val success = storageBridge.exportConfig(data)
                        Handler(Looper.getMainLooper()).post { result.success(success) }
                    }.start()
                }
                "autoImportConfig" -> {
                    Thread {
                        val dataStr = storageBridge.autoImportConfig()
                        Handler(Looper.getMainLooper()).post { result.success(dataStr) }
                    }.start()
                }
                "getTempDirectory" -> { result.success(storageBridge.getTempDirectory()) }
                "openUrl" -> {
                    val url = call.argument<String>("url") ?: ""
                    try {
                        val intent = android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(url))
                        intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("URL_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pcmRecorderChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(pcmRecorderBridge.hasPermission())
                "isRecording" -> result.success(pcmRecorderBridge.isRecordingNow())
                "startRecording" -> {
                    val path = call.argument<String>("path") ?: ""
                    val sampleRate = call.argument<Int>("sampleRate") ?: 48000
                    val channels = call.argument<Int>("channels") ?: 1
                    Thread {
                        val ok = pcmRecorderBridge.startRecording(path, sampleRate, channels)
                        Handler(Looper.getMainLooper()).post {
                            if (ok) result.success(true) else result.error("PCM_ERROR", "Failed to start PCM recorder", null)
                        }
                    }.start()
                }
                "stopRecording" -> {
                    Thread {
                        val outPath = pcmRecorderBridge.stopRecording()
                        Handler(Looper.getMainLooper()).post {
                            if (outPath != null) result.success(outPath) else result.error("PCM_ERROR", "No recording active", null)
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }
}