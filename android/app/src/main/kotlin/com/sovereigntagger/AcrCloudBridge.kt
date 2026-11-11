// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import android.app.Application
import android.content.Context
import com.acrcloud.rec.ACRCloudConfig
import com.acrcloud.rec.ACRCloudClient
import java.io.File

object AcrCloudBridge {
    private var isInitialized = false
    private var mClient: ACRCloudClient? = null
    private var lastHost: String = ""
    private var lastKey: String = ""
    private var lastSecret: String = ""



    private fun getAppContext(): Context? {
        return try {
            val activityThread = Class.forName("android.app.ActivityThread")
            val currentAppMethod = activityThread.getDeclaredMethod("currentApplication")
            currentAppMethod.invoke(null) as? Application
        } catch (e: Exception) {
            null
        }
    }

    private fun initInternal(host: String, accessKey: String, accessSecret: String) {
        val config = ACRCloudConfig()
        config.host = host
        config.accessKey = accessKey
        config.accessSecret = accessSecret


        getAppContext()?.let {
            config.context = it
        }


        val client = ACRCloudClient()
        client.initWithConfig(config)
        mClient = client
        isInitialized = true
    }

    fun initialize(host: String, accessKey: String, accessSecret: String) {
        lastHost = host
        lastKey = accessKey
        lastSecret = accessSecret
        if (!isInitialized) initInternal(host, accessKey, accessSecret)
    }

    fun identify(filePath: String): String {
        if (!isInitialized || mClient == null) {
            if (lastHost.isNotEmpty()) initInternal(lastHost, lastKey, lastSecret)
            if (!isInitialized) {
                return "{\"status\": \"error\", \"message\": \"ACRCloud Bridge must be initialized first\"}"
            }
        }

        val file = File(filePath)
        if (!file.exists()) {
            return "{\"status\": \"error\", \"message\": \"File not found for identification: $filePath\"}"
        }

        return try {


            val bytes = file.readBytes()


            val pcmData = if (bytes.size > 44) bytes.copyOfRange(44, bytes.size) else bytes


            val result = mClient?.recognize(pcmData, pcmData.size, 8000, 1)




                        try { mClient?.release() } catch (_: Exception) {}
            mClient = null
            isInitialized = false

            result ?: "{\"status\": \"error\", \"message\": \"Native Engine returned null\"}"
        } catch (e: Exception) {
                        try { mClient?.release() } catch (_: Exception) {}
            mClient = null
            isInitialized = false
            "{\"status\": \"error\", \"message\": \"Native Exception: ${e.message}\"}"
        }
    }
}