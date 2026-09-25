// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.util.Locale

class StorageBridge(private val context: Context) {

    fun addToMediaStore(filePath: String, title: String): String {
        val file = File(filePath)
        val extension = file.extension.lowercase(Locale.getDefault())
        val isVideo = extension == "mp4" || extension == "mkv" || extension == "webm"

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.TITLE, title)
            put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
            
            if (isVideo) {
                if (extension == "mkv") {
                    put(MediaStore.MediaColumns.MIME_TYPE, "video/x-matroska")
                } else {
                    put(MediaStore.MediaColumns.MIME_TYPE, "video/$extension")
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_MOVIES)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
            } else {
                val audioMime = when (extension) {
                    "flac" -> "audio/flac"
                    "wav" -> "audio/wav"
                    "m4a" -> "audio/mp4"
                    "ogg" -> "audio/ogg"
                    "opus" -> "audio/opus"
                    "mp3" -> "audio/mpeg"
                    else -> "audio/mpeg"
                }
                put(MediaStore.MediaColumns.MIME_TYPE, audioMime)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_MUSIC)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
            }
        }

        val collectionUri = if (isVideo) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val uri = context.contentResolver.insert(collectionUri, values)
        
        if (uri != null) {
            try {
                context.contentResolver.openOutputStream(uri)?.use { outputStream ->
                    file.inputStream().use { inputStream -> inputStream.copyTo(outputStream) }
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    values.clear()
                    values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                    context.contentResolver.update(uri, values, null, null)
                }
            } catch (e: Exception) {
                context.contentResolver.delete(uri, null, null)
                throw e
            }
        }
        return uri?.toString() ?: ""
    }

    fun exportConfig(data: String): Boolean {
        return try {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, "sovereign_config.bin")
                put(MediaStore.MediaColumns.MIME_TYPE, "application/octet-stream")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
            }
            
            val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            } else {
                val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                val file = File(dir, "sovereign_config.bin")
                file.writeText(data)
                return true
            }

            if (uri != null) {
                context.contentResolver.openOutputStream(uri)?.use { it.write(data.toByteArray()) }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    values.clear()
                    values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                    context.contentResolver.update(uri, values, null, null)
                }
                true
            } else false
        } catch (e: Exception) { false }
    }

    fun autoImportConfig(): String {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val projection = arrayOf(MediaStore.MediaColumns._ID)
                val selection = "${MediaStore.MediaColumns.DISPLAY_NAME} = ?"
                val selectionArgs = arrayOf("sovereign_config.bin")
                
                context.contentResolver.query(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    projection, selection, selectionArgs, null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID))
                        val uri = Uri.withAppendedPath(MediaStore.Downloads.EXTERNAL_CONTENT_URI, id.toString())
                        context.contentResolver.openInputStream(uri)?.use { return it.bufferedReader().readText() }
                    }
                }
            } else {
                val file = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "sovereign_config.bin")
                if (file.exists()) return file.readText()
            }
        } catch (e: Exception) {}
        return ""
    }

    fun getTempDirectory(): String = context.cacheDir.absolutePath
    fun queryMediaStore(): List<Map<String, String>> = emptyList()
    
    fun saveFile(uriString: String, data: ByteArray): Boolean {
        return try {
            val uri = Uri.parse(uriString)
            context.contentResolver.openOutputStream(uri)?.use { it.write(data) }
            true
        } catch (e: Exception) { false }
    }
}