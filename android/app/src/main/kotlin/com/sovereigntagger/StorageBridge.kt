// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Process
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Size
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.Locale

class StorageBridge(private val context: Context) {

    fun addToMediaStore(filePath: String, title: String): Map<String, String> {
        val file = File(filePath)
        val extension = file.extension.lowercase(Locale.getDefault())
        val isVideo = extension == "mp4" || extension == "mkv" || extension == "webm"

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.TITLE, title)
            put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeFor(extension))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.MediaColumns.RELATIVE_PATH, if (isVideo) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_MUSIC)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            val dir = Environment.getExternalStoragePublicDirectory(if (isVideo) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_MUSIC)
            dir.mkdirs()
            var target = File(dir, file.name)
            var n = 1
            while (target.exists()) {
                target = File(dir, "${file.nameWithoutExtension} ($n).${file.extension}")
                n++
            }
            file.copyTo(target)
            scan(target.absolutePath)
            return mapOf("uri" to Uri.fromFile(target).toString(), "path" to target.absolutePath, "displayName" to target.name)
        }

        val collectionUri = if (isVideo) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val uri = context.contentResolver.insert(collectionUri, values) ?: throw IllegalStateException("MediaStore insert refused")
        try {
            context.contentResolver.openOutputStream(uri)?.use { outputStream ->
                file.inputStream().use { inputStream -> inputStream.copyTo(outputStream) }
            }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            context.contentResolver.update(uri, values, null, null)
        } catch (e: Exception) {
            context.contentResolver.delete(uri, null, null)
            throw e
        }
        val info = describe(uri)
        return mapOf("uri" to uri.toString(), "path" to (info["path"] ?: ""), "displayName" to (info["displayName"] ?: file.name))
    }

    fun queryAudio(): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val columns = mutableListOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.TRACK,
            MediaStore.Audio.Media.YEAR,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.MIME_TYPE,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.DATA
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            columns.add(MediaStore.Audio.Media.ALBUM_ARTIST)
            columns.add(MediaStore.Audio.Media.GENRE)
        }
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        context.contentResolver.query(collection, columns.toTypedArray(), selection, null, null)?.use { c ->
            fun str(col: String): String? {
                val i = c.getColumnIndex(col)
                return if (i >= 0 && !c.isNull(i)) c.getString(i) else null
            }
            fun long(col: String): Long {
                val i = c.getColumnIndex(col)
                return if (i >= 0 && !c.isNull(i)) c.getLong(i) else 0L
            }
            while (c.moveToNext()) {
                val id = long(MediaStore.Audio.Media._ID)
                val rawTrack = long(MediaStore.Audio.Media.TRACK)
                out.add(mapOf(
                    "id" to id,
                    "uri" to ContentUris.withAppendedId(collection, id).toString(),
                    "path" to (str(MediaStore.Audio.Media.DATA) ?: ""),
                    "title" to (str(MediaStore.Audio.Media.TITLE) ?: ""),
                    "artist" to (str(MediaStore.Audio.Media.ARTIST) ?: ""),
                    "album" to (str(MediaStore.Audio.Media.ALBUM) ?: ""),
                    "albumArtist" to (str("album_artist") ?: ""),
                    "genre" to (str("genre") ?: ""),
                    "albumId" to long(MediaStore.Audio.Media.ALBUM_ID),
                    "durationMs" to long(MediaStore.Audio.Media.DURATION),
                    "track" to (rawTrack % 1000),
                    "disc" to (rawTrack / 1000),
                    "year" to long(MediaStore.Audio.Media.YEAR),
                    "dateAdded" to long(MediaStore.Audio.Media.DATE_ADDED),
                    "mime" to (str(MediaStore.Audio.Media.MIME_TYPE) ?: ""),
                    "size" to long(MediaStore.Audio.Media.SIZE),
                    "displayName" to (str(MediaStore.Audio.Media.DISPLAY_NAME) ?: "")
                ))
            }
        }
        return out
    }

    fun loadArtwork(uriString: String, size: Int): ByteArray? {
        val uri = Uri.parse(uriString)
        val edge = if (size in 32..2048) size else 256
        var bitmap: Bitmap? = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && uri.scheme == "content") {
            try {
                bitmap = context.contentResolver.loadThumbnail(uri, Size(edge, edge), null)
            } catch (_: Exception) {}
        }
        if (bitmap == null) {
            val retriever = MediaMetadataRetriever()
            try {
                if (uri.scheme == "content") retriever.setDataSource(context, uri) else retriever.setDataSource(uri.path ?: uriString)
                val bytes = retriever.embeddedPicture
                if (bytes != null) {
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                    var sample = 1
                    while (bounds.outWidth / (sample * 2) >= edge && bounds.outHeight / (sample * 2) >= edge) sample *= 2
                    bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
                }
            } catch (_: Exception) {
            } finally {
                try { retriever.release() } catch (_: Exception) {}
            }
        }
        val bmp = bitmap ?: return null
        val scaled = if (bmp.width > edge * 2 || bmp.height > edge * 2) {
            val ratio = edge.toFloat() / maxOf(bmp.width, bmp.height)
            Bitmap.createScaledBitmap(bmp, (bmp.width * ratio).toInt().coerceAtLeast(1), (bmp.height * ratio).toInt().coerceAtLeast(1), true)
        } else bmp
        val stream = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, 88, stream)
        return stream.toByteArray()
    }

    fun resolveMediaUri(identifier: String?, path: String?): String? {
        if (identifier != null && identifier.startsWith("content://media/")) return identifier
        if (identifier != null && identifier.startsWith("content://") && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val media = MediaStore.getMediaUri(context, Uri.parse(identifier))
                if (media != null) return media.toString()
            } catch (_: Exception) {}
        }
        if (!path.isNullOrEmpty()) {
            findAudioBy("${MediaStore.Audio.Media.DATA} = ?", arrayOf(path))?.let { return it }
        }
        if (identifier != null && identifier.startsWith("content://")) {
            try {
                var name: String? = null
                var size: Long = -1
                context.contentResolver.query(Uri.parse(identifier), arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { c ->
                    if (c.moveToFirst()) {
                        name = c.getString(0)
                        size = if (c.isNull(1)) -1 else c.getLong(1)
                    }
                }
                val n = name
                if (n != null) {
                    if (size > 0) {
                        findAudioBy("${MediaStore.Audio.Media.DISPLAY_NAME} = ? AND ${MediaStore.Audio.Media.SIZE} = ?", arrayOf(n, size.toString()))?.let { return it }
                    }
                    findAudioBy("${MediaStore.Audio.Media.DISPLAY_NAME} = ?", arrayOf(n))?.let { return it }
                }
            } catch (_: Exception) {}
        }
        return null
    }

    private fun findAudioBy(selection: String, args: Array<String>): String? {
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        context.contentResolver.query(collection, arrayOf(MediaStore.Audio.Media._ID), selection, args, null)?.use { c ->
            if (c.count == 1 && c.moveToFirst()) return ContentUris.withAppendedId(collection, c.getLong(0)).toString()
        }
        return null
    }

    fun describe(uri: Uri): Map<String, String> {
        val out = mutableMapOf<String, String>()
        try {
            context.contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DATA, MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    if (!c.isNull(0)) out["path"] = c.getString(0)
                    if (!c.isNull(1)) out["displayName"] = c.getString(1)
                }
            }
        } catch (_: Exception) {}
        return out
    }

    fun urisNeedingWriteGrant(uris: List<String>): List<Uri> {
        return uris.map { Uri.parse(it) }.filter { uri ->
            if (uri.scheme != "content") return@filter false
            context.checkUriPermission(uri, Process.myPid(), Process.myUid(), Intent.FLAG_GRANT_WRITE_URI_PERMISSION) != PackageManager.PERMISSION_GRANTED
        }
    }

    fun overwriteMedia(uriString: String, srcPath: String, newDisplayName: String?): Map<String, String> {
        val uri = Uri.parse(uriString)
        val src = File(srcPath)
        if (!src.exists()) throw IllegalStateException("Working copy missing: $srcPath")

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || uri.scheme == "file") {
            val originalPath = if (uri.scheme == "file") uri.path ?: "" else describe(uri)["path"] ?: ""
            if (originalPath.isEmpty()) throw IllegalStateException("Original path unresolved")
            val original = File(originalPath)
            src.copyTo(original, overwrite = true)
            var finalFile = original
            if (!newDisplayName.isNullOrEmpty() && newDisplayName != original.name) {
                val renamed = File(original.parentFile, newDisplayName)
                if (!renamed.exists() && original.renameTo(renamed)) finalFile = renamed
            }
            scan(originalPath)
            if (finalFile.absolutePath != originalPath) scan(finalFile.absolutePath)
            return mapOf("uri" to uriString, "path" to finalFile.absolutePath, "displayName" to finalFile.name)
        }

        val stream = try {
            context.contentResolver.openOutputStream(uri, "wt")
        } catch (_: Exception) {
            context.contentResolver.openOutputStream(uri, "w")
        } ?: throw IllegalStateException("Original not writable")
        stream.use { out -> src.inputStream().use { it.copyTo(out) } }

        if (!newDisplayName.isNullOrEmpty()) {
            val current = describe(uri)["displayName"]
            if (current != newDisplayName) {
                try {
                    val values = ContentValues().apply { put(MediaStore.MediaColumns.DISPLAY_NAME, newDisplayName) }
                    context.contentResolver.update(uri, values, null, null)
                } catch (_: Exception) {}
            }
        }
        val info = describe(uri)
        info["path"]?.let { scan(it) }
        return mapOf("uri" to uriString, "path" to (info["path"] ?: ""), "displayName" to (info["displayName"] ?: ""))
    }

    fun deleteDirect(uriString: String): Boolean {
        val uri = Uri.parse(uriString)
        return try {
            if (uri.scheme == "file") File(uri.path ?: "").delete()
            else context.contentResolver.delete(uri, null, null) > 0
        } catch (_: Exception) {
            false
        }
    }

    fun scan(path: String) {
        try { MediaScannerConnection.scanFile(context, arrayOf(path), null, null) } catch (_: Exception) {}
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

    private fun mimeFor(extension: String): String = when (extension) {
        "mkv" -> "video/x-matroska"
        "mp4" -> "video/mp4"
        "webm" -> "video/webm"
        "flac" -> "audio/flac"
        "wav" -> "audio/wav"
        "m4a" -> "audio/mp4"
        "ogg" -> "audio/ogg"
        "opus" -> "audio/opus"
        else -> "audio/mpeg"
    }
}
