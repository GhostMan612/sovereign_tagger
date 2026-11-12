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
import android.graphics.Matrix
import android.media.ExifInterface
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Process
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import android.util.Size
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Locale
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

class StorageBridge(private val context: Context) {

    companion object {
        private const val TAG = "StorageBridge"
        private const val KEYSTORE_ALIAS = "SovereignLocalVaultKey"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val DEFAULT_PBKDF2_ITERATIONS = 250000
        private const val LEGACY_PBKDF2_ITERATIONS = 10000
        private const val MIN_PBKDF2_ITERATIONS = 1000
        private const val MAX_PBKDF2_ITERATIONS = 2000000
        private const val LEGACY_PHASE38_SECRET = "SovereignVault::KernelMasterKey::v2"
    }

    private fun validateRecoveryFile(backupPath: String): File {
        val recoveryDir = File(context.filesDir, "sov_recovery").canonicalFile
        val file = File(backupPath).canonicalFile
        if (!file.path.startsWith(recoveryDir.path + File.separator)) {
            throw SecurityException("Path traversal rejected: $backupPath is outside recovery vault (${recoveryDir.path})")
        }
        if (!file.name.startsWith("sov_rec_") || !file.name.endsWith(".bak")) {
            throw SecurityException("Invalid recovery backup filename: ${file.name}")
        }
        return file
    }

    private data class Quad<A, B, C, D>(val first: A, val second: B, val third: C, val fourth: D)

    private fun getOrCreateKeystoreKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        if (!keyStore.containsAlias(KEYSTORE_ALIAS)) {
            val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                try {
                    val strongBoxSpec = KeyGenParameterSpec.Builder(
                        KEYSTORE_ALIAS,
                        KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
                    )
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .setKeySize(256)
                        .setIsStrongBoxBacked(true)
                        .build()
                    keyGenerator.init(strongBoxSpec)
                    return keyGenerator.generateKey()
                } catch (_: Throwable) {
                    Log.i(TAG, "StrongBox unavailable, falling back to standard TEE Keystore")
                }
            }
            val spec = KeyGenParameterSpec.Builder(
                KEYSTORE_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
            keyGenerator.init(spec)
            return keyGenerator.generateKey()
        }
        val entry = keyStore.getEntry(KEYSTORE_ALIAS, null) as? KeyStore.SecretKeyEntry
            ?: throw IllegalStateException("Keystore entry for $KEYSTORE_ALIAS is not a SecretKeyEntry")
        return entry.secretKey
    }

    private fun derivePassphraseKey(passphrase: String, salt: ByteArray, iterations: Int = DEFAULT_PBKDF2_ITERATIONS): SecretKey {
        val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
        val spec = PBEKeySpec(passphrase.toCharArray(), salt, iterations, 256)
        return SecretKeySpec(factory.generateSecret(spec).encoded, "AES")
    }

    private fun computeSha256(file: File): String {
        val md = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buf = ByteArray(64 * 1024)
            while (true) {
                val n = input.read(buf)
                if (n <= 0) break
                md.update(buf, 0, n)
            }
        }
        return md.digest().joinToString("") { "%02x".format(it) }
    }

    private fun computeSha256(uri: Uri): String {
        val md = MessageDigest.getInstance("SHA-256")
        context.contentResolver.openInputStream(uri)?.use { input ->
            val buf = ByteArray(64 * 1024)
            while (true) {
                val n = input.read(buf)
                if (n <= 0) break
                md.update(buf, 0, n)
            }
        } ?: throw IllegalStateException("Cannot read stream to compute SHA-256: $uri")
        return md.digest().joinToString("") { "%02x".format(it) }
    }

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
            if (target.length() != file.length()) {
                target.delete()
                throw java.io.IOException("ERR: MediaStore copy truncated. Expected ${file.length()} bytes, found ${target.length()} bytes.")
            }
            val srcSha = computeSha256(file)
            val destSha = computeSha256(target)
            if (destSha != srcSha) {
                target.delete()
                throw java.io.IOException("ERR: MediaStore copy SHA-256 mismatch. Expected $srcSha, found $destSha.")
            }
            scan(target.absolutePath)
            return mapOf("uri" to Uri.fromFile(target).toString(), "path" to target.absolutePath, "displayName" to target.name)
        }

        val collectionUri = if (isVideo) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val uri = context.contentResolver.insert(collectionUri, values) ?: throw IllegalStateException("MediaStore insert refused")
        try {
            val outputStream = context.contentResolver.openOutputStream(uri)
                ?: throw java.io.IOException("ERR: MediaStore opened null output stream for $uri")
            var bytesCopied: Long
            outputStream.use { os ->
                file.inputStream().use { inputStream ->
                    bytesCopied = inputStream.copyTo(os)
                }
            }
            if (bytesCopied != file.length()) {
                throw java.io.IOException("ERR: MediaStore import truncated. Expected ${file.length()} bytes, wrote $bytesCopied bytes.")
            }
            val srcSha = computeSha256(file)
            val destSha = computeSha256(uri)
            if (destSha != srcSha) {
                throw java.io.IOException("ERR: MediaStore SHA-256 mismatch before publication. Expected $srcSha, got $destSha.")
            }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            val rowsUpdated = context.contentResolver.update(uri, values, null, null)
            if (rowsUpdated <= 0) {
                throw java.io.IOException("ERR: MediaStore update IS_PENDING=0 failed for $uri (rows affected: $rowsUpdated)")
            }
        } catch (e: Exception) {
            try {
                val deleted = context.contentResolver.delete(uri, null, null)
                if (deleted <= 0) {
                    android.util.Log.w("StorageBridge", "MediaStore rollback delete returned 0 for $uri")
                }
            } catch (delErr: Exception) {
                android.util.Log.e("StorageBridge", "MediaStore rollback delete failed for $uri: $delErr")
            }
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

    fun queryPhotos(): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val columns = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.MIME_TYPE,
            MediaStore.Images.Media.SIZE,
            MediaStore.Images.Media.DATE_ADDED,
            MediaStore.Images.Media.WIDTH,
            MediaStore.Images.Media.HEIGHT,
            MediaStore.Images.Media.DATA
        )
        val sortOrder = "${MediaStore.Images.Media.DATE_ADDED} DESC"
        context.contentResolver.query(collection, columns, null, null, sortOrder)?.use { c ->
            fun str(col: String): String? {
                val i = c.getColumnIndex(col)
                return if (i >= 0 && !c.isNull(i)) c.getString(i) else null
            }
            fun long(col: String): Long {
                val i = c.getColumnIndex(col)
                return if (i >= 0 && !c.isNull(i)) c.getLong(i) else 0L
            }
            while (c.moveToNext()) {
                val id = long(MediaStore.Images.Media._ID)
                out.add(mapOf(
                    "id" to id,
                    "uri" to ContentUris.withAppendedId(collection, id).toString(),
                    "path" to (str(MediaStore.Images.Media.DATA) ?: ""),
                    "displayName" to (str(MediaStore.Images.Media.DISPLAY_NAME) ?: ""),
                    "mime" to (str(MediaStore.Images.Media.MIME_TYPE) ?: ""),
                    "size" to long(MediaStore.Images.Media.SIZE),
                    "dateAdded" to long(MediaStore.Images.Media.DATE_ADDED),
                    "width" to long(MediaStore.Images.Media.WIDTH),
                    "height" to long(MediaStore.Images.Media.HEIGHT)
                ))
            }
        }
        return out
    }

    fun loadPhotoThumbnail(uriString: String, size: Int): ByteArray? {
        val uri = Uri.parse(uriString)
        val edge = if (size in 32..2048) size else 256
        var bitmap: Bitmap? = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && uri.scheme == "content") {
            try {
                bitmap = context.contentResolver.loadThumbnail(uri, Size(edge, edge), null)
            } catch (_: Exception) {}
        }
        if (bitmap == null) {
            bitmap = decodeSampled(uri, edge)
        }
        val bmp = bitmap ?: return null
        val stream = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, 88, stream)
        return stream.toByteArray()
    }

    fun loadPhoto(uriString: String, maxSize: Int): ByteArray? {
        val uri = Uri.parse(uriString)
        val cap = if (maxSize in 256..8192) maxSize else 2048
        val decoded = decodeSampled(uri, cap) ?: return null
        val oriented = applyExifRotation(uri, decoded)
        val stream = ByteArrayOutputStream()
        oriented.compress(Bitmap.CompressFormat.JPEG, 90, stream)
        return stream.toByteArray()
    }

    fun exportPhotoToPictures(uriString: String, displayName: String?): String? {
        val uri = Uri.parse(uriString)
        val safeName = (displayName?.takeIf { it.isNotEmpty() } ?: describe(uri)["displayName"] ?: "sovereign_photo.jpg")
            .replace(Regex("[\\\\/:*?\"<>|]"), "_").trim().ifEmpty { "sovereign_photo.jpg" }
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, safeName)
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeForPhoto(safeName))
                    put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/Sovereign Tagger")
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val target = context.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return null
                try {
                    val input = context.contentResolver.openInputStream(uri) ?: throw IllegalStateException("Photo unreadable")
                    context.contentResolver.openOutputStream(target)?.use { out -> input.use { it.copyTo(out) } }
                        ?: throw IllegalStateException("Pictures output refused")
                } catch (e: Exception) {
                    context.contentResolver.delete(target, null, null)
                    throw e
                }
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                context.contentResolver.update(target, values, null, null)
                "Pictures/Sovereign Tagger/$safeName"
            } else {
                val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "Sovereign Tagger")
                if (!dir.exists()) dir.mkdirs()
                val file = File(dir, safeName)
                context.contentResolver.openInputStream(uri)?.use { input -> file.outputStream().use { out -> input.copyTo(out) } }
                    ?: throw IllegalStateException("Photo unreadable")
                scan(file.absolutePath)
                file.absolutePath
            }
        } catch (_: Exception) {
            null
        }
    }

    fun photoOrientation(uriString: String): Int {
        return try {
            val uri = Uri.parse(uriString)
            context.contentResolver.openInputStream(uri)?.use { input ->
                ExifInterface(input).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            } ?: ExifInterface.ORIENTATION_NORMAL
        } catch (_: Exception) {
            ExifInterface.ORIENTATION_NORMAL
        }
    }

    fun exportPhotoFileToPictures(filePath: String, displayName: String?): String? {
        val src = File(filePath)
        if (!src.exists()) return null
        val safeName = (displayName?.takeIf { it.isNotEmpty() } ?: src.name)
            .replace(Regex("[\\\\/:*?\"<>|]"), "_").trim().ifEmpty { "sovereign_photo.jpg" }
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, safeName)
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeForPhoto(safeName))
                    put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/Sovereign Tagger")
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val target = context.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return null
                try {
                    context.contentResolver.openOutputStream(target)?.use { out -> src.inputStream().use { it.copyTo(out) } }
                        ?: throw IllegalStateException("Pictures output refused")
                } catch (e: Exception) {
                    context.contentResolver.delete(target, null, null)
                    throw e
                }
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                context.contentResolver.update(target, values, null, null)
                "Pictures/Sovereign Tagger/$safeName"
            } else {
                val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "Sovereign Tagger")
                if (!dir.exists()) dir.mkdirs()
                val file = File(dir, safeName)
                src.inputStream().use { input -> file.outputStream().use { out -> input.copyTo(out) } }
                scan(file.absolutePath)
                file.absolutePath
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun decodeSampled(uri: Uri, maxEdge: Int): Bitmap? {
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            var sample = 1
            val longest = maxOf(bounds.outWidth, bounds.outHeight)
            while (longest / (sample * 2) >= maxEdge) sample *= 2
            val opts = BitmapFactory.Options().apply { inSampleSize = sample }
            context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, opts) }
        } catch (_: Exception) {
            null
        }
    }

    private fun applyExifRotation(uri: Uri, bitmap: Bitmap): Bitmap {
        return try {
            val orientation = context.contentResolver.openInputStream(uri)?.use { input ->
                ExifInterface(input).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            } ?: ExifInterface.ORIENTATION_NORMAL
            val degrees = when (orientation) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
            if (degrees == 0f) return bitmap
            val matrix = Matrix().apply { postRotate(degrees) }
            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        } catch (_: Exception) {
            bitmap
        }
    }

    private fun mimeForPhoto(name: String): String = when (name.substringAfterLast('.', "").lowercase(Locale.getDefault())) {
        "png" -> "image/png"
        "webp" -> "image/webp"
        "gif" -> "image/gif"
        "bmp" -> "image/bmp"
        "heic", "heif" -> "image/heic"
        else -> "image/jpeg"
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
        val srcLen = src.length()

        if (uri.scheme == "file" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            throw IllegalStateException("Raw-path originals cannot be fixed in place on Android 10+; re-import through MediaStore")
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || uri.scheme == "file") {
            val originalPath = if (uri.scheme == "file") uri.path ?: "" else describe(uri)["path"] ?: ""
            if (originalPath.isEmpty()) throw IllegalStateException("Original path unresolved")
            val original = File(originalPath)
            val staged = File(original.parentFile, ".${original.name}.sov-save")
            try {
                src.copyTo(staged, overwrite = true)
                if (staged.length() != srcLen) {
                    staged.delete()
                    throw IllegalStateException("Write-back staged only ${staged.length()} of $srcLen bytes; the original was left untouched")
                }
                if (!staged.renameTo(original)) {
                    throw IllegalStateException("Could not move the staged write over the original")
                }
                var finalFile = original
                if (!newDisplayName.isNullOrEmpty() && newDisplayName != original.name) {
                    val renamed = File(original.parentFile, newDisplayName)
                    if (renamed.exists()) throw IllegalStateException("Target filename already exists: $newDisplayName")
                    if (!original.renameTo(renamed)) throw IllegalStateException("Rename failed: ${original.name} -> $newDisplayName")
                    finalFile = renamed
                }
                scan(originalPath)
                if (finalFile.absolutePath != originalPath) scan(finalFile.absolutePath)
                return mapOf(
                    "uri" to uriString,
                    "path" to finalFile.absolutePath,
                    "displayName" to finalFile.name,
                    "verified" to "true",
                    "renamed" to "true",
                )
            } finally {
                try { staged.delete() } catch (_: Throwable) {}
            }
        }

        if (uri.authority != null && !uri.authority!!.contains("media")) {
            throw IllegalStateException("Not a MediaStore item (authority=${uri.authority}); Android will not let it be fixed in place. Use LIBRARY > EDIT IN FORGE instead.")
        }

        val recoveryDir = File(context.filesDir, "sov_recovery").apply { mkdirs() }
        val opId = System.currentTimeMillis()
        val transactionId = "${opId}_${UUID.randomUUID().toString().replace("-", "")}"
        val recoveryFile = File(recoveryDir, "sov_rec_${transactionId}.bak")
        val metaFile = File(recoveryDir, "sov_rec_${transactionId}.meta")

        val srcSha = computeSha256(src)
        val bakSha: String
        val bakLen: Long

        try {
            context.contentResolver.openInputStream(uri)?.use { inStream ->
                recoveryFile.outputStream().use { outStream ->
                    inStream.copyTo(outStream)
                }
            } ?: throw IllegalStateException("Could not read original media from $uri")
            bakLen = recoveryFile.length()
            if (bakLen <= 0L) {
                throw IllegalStateException("Original media backup returned 0 bytes")
            }
            bakSha = computeSha256(recoveryFile)
            metaFile.writeText("URI=$uriString\nSIZE=$bakLen\nSHA256=$bakSha\nTIME=$opId\nSTATUS=PENDING\n")
        } catch (e: Throwable) {
            try { recoveryFile.delete() } catch (_: Throwable) {}
            try { metaFile.delete() } catch (_: Throwable) {}
            throw IllegalStateException("Pre-overwrite safety backup failed; operation aborted to protect original media: ${e.message}", e)
        }

        var success = false
        try {
            val stream = try {
                context.contentResolver.openOutputStream(uri, "rwt")
            } catch (_: Exception) {
                context.contentResolver.openOutputStream(uri, "wt")
            } ?: throw IllegalStateException("Destination URI not writable: $uriString")

            var written = 0L
            try {
                stream.use { out ->
                    src.inputStream().use { input ->
                        val buf = ByteArray(64 * 1024)
                        while (true) {
                            val n = input.read(buf)
                            if (n <= 0) break
                            out.write(buf, 0, n)
                            written += n
                        }
                        out.flush()
                    }
                }
            } catch (e: Exception) {
                var restoredBytes = 0L
                var restoreVerified = false
                try {
                    val rStream = try {
                        context.contentResolver.openOutputStream(uri, "rwt")
                    } catch (_: Exception) {
                        context.contentResolver.openOutputStream(uri, "wt")
                    }
                    if (rStream != null) {
                        rStream.use { rOut ->
                            recoveryFile.inputStream().use { rIn ->
                                val rBuf = ByteArray(64 * 1024)
                                while (true) {
                                    val n = rIn.read(rBuf)
                                    if (n <= 0) break
                                    rOut.write(rBuf, 0, n)
                                    restoredBytes += n
                                }
                                rOut.flush()
                            }
                        }
                        val restoredSha = computeSha256(uri)
                        restoreVerified = (restoredBytes == recoveryFile.length() && restoredSha == bakSha)
                    }
                } catch (re: Throwable) {
                    Log.e(TAG, "Restoration attempt failed: ${re.message}")
                }
                if (restoreVerified) {
                    try { recoveryFile.delete() } catch (_: Throwable) {}
                    try { metaFile.delete() } catch (_: Throwable) {}
                    throw IllegalStateException("Write-back failed after $written of $srcLen bytes. Original media verified and restored ($restoredBytes bytes, SHA-256 match): ${e.message}")
                } else {
                    metaFile.writeText("URI=$uriString\nSIZE=${recoveryFile.length()}\nSHA256=$bakSha\nTIME=$opId\nSTATUS=RETAINED_FAILED_RESTORE\nRESTORED=$restoredBytes\n")
                    throw IllegalStateException("CRITICAL: Write-back failed AND in-place restore could not be verified. Original bytes PRESERVED in recovery file: ${recoveryFile.absolutePath}")
                }
            }

            if (written != srcLen) {
                var restoredBytes = 0L
                var restoreVerified = false
                try {
                    val rStream = try {
                        context.contentResolver.openOutputStream(uri, "rwt")
                    } catch (_: Exception) {
                        context.contentResolver.openOutputStream(uri, "wt")
                    }
                    if (rStream != null) {
                        rStream.use { rOut ->
                            recoveryFile.inputStream().use { rIn ->
                                val rBuf = ByteArray(64 * 1024)
                                while (true) {
                                    val n = rIn.read(rBuf)
                                    if (n <= 0) break
                                    rOut.write(rBuf, 0, n)
                                    restoredBytes += n
                                }
                                rOut.flush()
                            }
                        }
                        val restoredSha = computeSha256(uri)
                        restoreVerified = (restoredBytes == recoveryFile.length() && restoredSha == bakSha)
                    }
                } catch (re: Throwable) {
                    Log.e(TAG, "Restoration attempt failed: ${re.message}")
                }
                if (restoreVerified) {
                    try { recoveryFile.delete() } catch (_: Throwable) {}
                    try { metaFile.delete() } catch (_: Throwable) {}
                    throw IllegalStateException("Write-back short: $written of $srcLen bytes landed. Original media verified and restored ($restoredBytes bytes, SHA-256 match).")
                } else {
                    metaFile.writeText("URI=$uriString\nSIZE=${recoveryFile.length()}\nSHA256=$bakSha\nTIME=$opId\nSTATUS=RETAINED_FAILED_RESTORE\nRESTORED=$restoredBytes\n")
                    throw IllegalStateException("CRITICAL: Write-back short AND in-place restore could not be verified. Original bytes PRESERVED in recovery file: ${recoveryFile.absolutePath}")
                }
            }

            val destSha = computeSha256(uri)
            if (destSha != srcSha) {
                var restoredBytes = 0L
                var restoreVerified = false
                try {
                    val rStream = try {
                        context.contentResolver.openOutputStream(uri, "rwt")
                    } catch (_: Exception) {
                        context.contentResolver.openOutputStream(uri, "wt")
                    }
                    if (rStream != null) {
                        rStream.use { rOut ->
                            recoveryFile.inputStream().use { rIn ->
                                val rBuf = ByteArray(64 * 1024)
                                while (true) {
                                    val n = rIn.read(rBuf)
                                    if (n <= 0) break
                                    rOut.write(rBuf, 0, n)
                                    restoredBytes += n
                                }
                                rOut.flush()
                            }
                        }
                        val restoredSha = computeSha256(uri)
                        restoreVerified = (restoredBytes == recoveryFile.length() && restoredSha == bakSha)
                    }
                } catch (re: Throwable) {
                    Log.e(TAG, "Restoration attempt failed: ${re.message}")
                }
                if (restoreVerified) {
                    try { recoveryFile.delete() } catch (_: Throwable) {}
                    try { metaFile.delete() } catch (_: Throwable) {}
                    throw IllegalStateException("Write-back hash mismatch (expected $srcSha, got $destSha). Original media verified and restored ($restoredBytes bytes, SHA-256 match).")
                } else {
                    metaFile.writeText("URI=$uriString\nSIZE=${recoveryFile.length()}\nSHA256=$bakSha\nTIME=$opId\nSTATUS=RETAINED_FAILED_RESTORE\nRESTORED=$restoredBytes\n")
                    throw IllegalStateException("CRITICAL: Write-back hash mismatch AND restore could not be verified. Original bytes PRESERVED in recovery file: ${recoveryFile.absolutePath}")
                }
            }

            try {
                metaFile.writeText("URI=$uriString\nSIZE=${recoveryFile.length()}\nSHA256=$bakSha\nSRC_SHA=$srcSha\nDEST_SHA=$destSha\nTIME=$opId\nSTATUS=COMMITTED\n")
            } catch (_: Throwable) {}
            success = true
        } finally {
            if (success) {
                try { recoveryFile.delete() } catch (_: Throwable) {}
                try { metaFile.delete() } catch (_: Throwable) {}
            }
        }

        var renamedOk = true
        if (!newDisplayName.isNullOrEmpty()) {
            val current = describe(uri)["displayName"]
            if (current == null) {
                renamedOk = false
                Log.w(TAG, "overwriteMedia: cannot resolve the current name on $uriString, rename not attempted")
            } else if (current != newDisplayName) {
                try {
                    val values = ContentValues().apply { put(MediaStore.MediaColumns.DISPLAY_NAME, newDisplayName) }
                    context.contentResolver.update(uri, values, null, null)
                } catch (e: Exception) {
                    renamedOk = false
                    Log.w(TAG, "overwriteMedia: rename to '$newDisplayName' failed on $uriString: ${e.message}")
                }
            }
        }
        val info = describe(uri)
        info["path"]?.let { scan(it) }
        return mapOf(
            "uri" to uriString,
            "path" to (info["path"] ?: ""),
            "displayName" to (info["displayName"] ?: ""),
            "verified" to "true",
            "renamed" to renamedOk.toString(),
        )
    }

    fun recoverPendingOverwrites(): List<Map<String, String>> {
        val recoveryDir = File(context.filesDir, "sov_recovery")
        if (!recoveryDir.exists()) return emptyList()
        val reports = mutableListOf<Map<String, String>>()
        val baks = recoveryDir.listFiles { _, name -> name.startsWith("sov_rec_") && name.endsWith(".bak") } ?: return emptyList()
        for (bak in baks) {
            val meta = File(recoveryDir, "${bak.nameWithoutExtension}.meta")
            var uri = ""
            var size = bak.length().toString()
            var sha256 = ""
            var time = ""
            var status = "UNKNOWN"
            var srcSha = ""
            var destSha = ""
            if (meta.exists()) {
                val lines = meta.readLines()
                for (line in lines) {
                    val p = line.indexOf('=')
                    if (p > 0) {
                        val key = line.substring(0, p).trim()
                        val value = line.substring(p + 1).trim()
                        when (key) {
                            "URI" -> uri = value
                            "SIZE" -> size = value
                            "SHA256" -> sha256 = value
                            "TIME" -> time = value
                            "STATUS" -> status = value
                            "SRC_SHA" -> srcSha = value
                            "DEST_SHA" -> destSha = value
                        }
                    }
                }
            }
            if (sha256.isEmpty()) {
                try {
                    sha256 = computeSha256(bak)
                } catch (_: Throwable) {}
            }
            var resolvedStatus = status
            var liveVerified = false
            if (uri.isNotEmpty() && srcSha.isNotEmpty()) {
                try {
                    val currentDestSha = computeSha256(Uri.parse(uri))
                    if (currentDestSha == srcSha) {
                        liveVerified = true
                    }
                } catch (_: Throwable) {}
            }
            if (status == "COMMITTED") {
                if (liveVerified) {
                    resolvedStatus = "COMMITTED_PRE_CLEANUP"
                } else {
                    resolvedStatus = "DESTINATION_HASH_UNVERIFIED"
                }
            }
            reports.add(mapOf(
                "backupPath" to bak.canonicalPath,
                "backupName" to bak.name,
                "uri" to uri,
                "size" to size,
                "sha256" to sha256,
                "time" to time,
                "status" to resolvedStatus,
                "srcSha" to srcSha,
                "destSha" to destSha
            ))
        }
        val metas = recoveryDir.listFiles { _, name -> name.startsWith("sov_rec_") && name.endsWith(".meta") } ?: emptyArray()
        for (meta in metas) {
            val companionBak = File(recoveryDir, "${meta.nameWithoutExtension}.bak")
            if (!companionBak.exists()) {
                try { meta.delete() } catch (_: Throwable) {}
            }
        }
        return reports
    }

    fun restorePendingOverwrite(backupPath: String): Map<String, String> {
        val bak = validateRecoveryFile(backupPath)
        if (!bak.exists()) throw IllegalStateException("Backup file does not exist: $backupPath")
        val meta = File(bak.parentFile, "${bak.nameWithoutExtension}.meta")
        var uriString = ""
        var expectedSha = ""
        if (meta.exists()) {
            for (line in meta.readLines()) {
                val p = line.indexOf('=')
                if (p > 0) {
                    val key = line.substring(0, p).trim()
                    val value = line.substring(p + 1).trim()
                    if (key == "URI") uriString = value
                    if (key == "SHA256") expectedSha = value
                }
            }
        }
        if (uriString.isEmpty()) {
            throw IllegalStateException("No target URI found in metadata for $backupPath")
        }
        val uri = Uri.parse(uriString)
        val bakSha = computeSha256(bak)
        if (expectedSha.isNotEmpty() && expectedSha != bakSha) {
            throw IllegalStateException("Backup corruption detected before restore: meta $expectedSha != actual $bakSha")
        }
        val stream = try {
            context.contentResolver.openOutputStream(uri, "rwt")
        } catch (_: Exception) {
            context.contentResolver.openOutputStream(uri, "wt")
        } ?: throw IllegalStateException("Destination URI not writable: $uriString")

        var restoredBytes = 0L
        stream.use { out ->
            bak.inputStream().use { input ->
                val buf = ByteArray(64 * 1024)
                while (true) {
                    val n = input.read(buf)
                    if (n <= 0) break
                    out.write(buf, 0, n)
                    restoredBytes += n
                }
                out.flush()
            }
        }

        val destSha = computeSha256(uri)
        if (destSha != bakSha) {
            throw IllegalStateException("Restore SHA-256 mismatch: destination $destSha != backup $bakSha")
        }

        try { bak.delete() } catch (_: Throwable) {}
        try { meta.delete() } catch (_: Throwable) {}

        val info = describe(uri)
        info["path"]?.let { scan(it) }

        return mapOf(
            "status" to "RESTORED",
            "uri" to uriString,
            "path" to (info["path"] ?: ""),
            "displayName" to (info["displayName"] ?: ""),
            "sha256" to destSha,
            "bytes" to restoredBytes.toString()
        )
    }

    fun discardPendingOverwrite(backupPath: String): Boolean {
        val bak = validateRecoveryFile(backupPath)
        val meta = File(bak.parentFile, "${bak.nameWithoutExtension}.meta")
        val bOk = if (bak.exists()) bak.delete() else true
        val mOk = if (meta.exists()) meta.delete() else true
        if (!bOk || !mOk) {
            Log.w(TAG, "discardPendingOverwrite: incomplete discard (bakDeleted=$bOk, metaDeleted=$mOk)")
            if (meta.exists() && !bak.exists()) {
                try {
                    meta.writeText("STATUS=ORPHANED_META\nERROR=BACKUP_DELETED_META_RETAINED\n")
                } catch (_: Throwable) {}
            }
        }
        return bOk && mOk
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

    fun exportTextToDownloads(fileName: String, mimeType: String, data: String): String? {
        return try {
            val safeName = fileName.replace(Regex("[\\\\/:*?\"<>|]"), "_").trim().ifEmpty { "sovereign_report.txt" }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, safeName)
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return null
                context.contentResolver.openOutputStream(uri)?.use { it.write(data.toByteArray(Charsets.UTF_8)) }
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                context.contentResolver.update(uri, values, null, null)
                "Downloads/$safeName"
            } else {
                val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                if (!dir.exists()) dir.mkdirs()
                val file = File(dir, safeName)
                file.writeText(data, Charsets.UTF_8)
                scan(file.absolutePath)
                file.absolutePath
            }
        } catch (_: Exception) {
            null
        }
    }

    fun encryptConfig(plainText: String, passphrase: String? = null): String {
        try {
            if (!passphrase.isNullOrEmpty()) {
                val iterations = DEFAULT_PBKDF2_ITERATIONS
                val random = SecureRandom()
                val salt = ByteArray(16).also { random.nextBytes(it) }
                val iv = ByteArray(12).also { random.nextBytes(it) }
                val key = derivePassphraseKey(passphrase, salt, iterations)
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, iv))
                val cipherBytes = cipher.doFinal(plainText.toByteArray(Charsets.UTF_8))
                val saltB64 = Base64.encodeToString(salt, Base64.NO_WRAP)
                val ivB64 = Base64.encodeToString(iv, Base64.NO_WRAP)
                val cipherB64 = Base64.encodeToString(cipherBytes, Base64.NO_WRAP)
                return "SOV2:P:$iterations:$saltB64:$ivB64:$cipherB64"
            } else {
                val key = getOrCreateKeystoreKey()
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.ENCRYPT_MODE, key)
                val iv = cipher.iv ?: ByteArray(12).also { SecureRandom().nextBytes(it) }
                val cipherBytes = cipher.doFinal(plainText.toByteArray(Charsets.UTF_8))
                val ivB64 = Base64.encodeToString(iv, Base64.NO_WRAP)
                val cipherB64 = Base64.encodeToString(cipherBytes, Base64.NO_WRAP)
                return "SOV2:K:$ivB64:$cipherB64"
            }
        } catch (e: Exception) {
            throw IllegalStateException("Encryption failed: ${e.message}", e)
        }
    }

    fun decryptConfig(cipherText: String, passphrase: String? = null): String {
        val trimmed = cipherText.trim()
        if (trimmed.startsWith("SOV2:K:")) {
            val parts = trimmed.split(":")
            if (parts.size < 4) throw IllegalArgumentException("Malformed SOV2:K payload")
            val iv = Base64.decode(parts[2], Base64.NO_WRAP)
            val cipherBytes = Base64.decode(parts[3], Base64.NO_WRAP)
            val key = getOrCreateKeystoreKey()
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
            val plainBytes = cipher.doFinal(cipherBytes)
            return String(plainBytes, Charsets.UTF_8)
        }
        if (trimmed.startsWith("SOV2:P:")) {
            val parts = trimmed.split(":")
            val iterations: Int
            val saltB64: String
            val ivB64: String
            val cipherB64: String
            if (parts.size >= 6) {
                val parsed = parts[2].toIntOrNull()
                if (parsed == null || parsed < MIN_PBKDF2_ITERATIONS || parsed > MAX_PBKDF2_ITERATIONS) {
                    throw IllegalArgumentException("PBKDF2 iterations out of bounds: ${parts[2]} (allowed: $MIN_PBKDF2_ITERATIONS..$MAX_PBKDF2_ITERATIONS)")
                }
                iterations = parsed
                saltB64 = parts[3]
                ivB64 = parts[4]
                cipherB64 = parts[5]
            } else if (parts.size == 5) {
                iterations = LEGACY_PBKDF2_ITERATIONS
                saltB64 = parts[2]
                ivB64 = parts[3]
                cipherB64 = parts[4]
            } else {
                throw IllegalArgumentException("Malformed SOV2:P payload")
            }
            if (passphrase.isNullOrEmpty()) {
                throw IllegalArgumentException("Passphrase required to decrypt encrypted backup")
            }
            val salt = Base64.decode(saltB64, Base64.NO_WRAP)
            val iv = Base64.decode(ivB64, Base64.NO_WRAP)
            val cipherBytes = Base64.decode(cipherB64, Base64.NO_WRAP)
            val key = derivePassphraseKey(passphrase, salt, iterations)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
            val plainBytes = cipher.doFinal(cipherBytes)
            return String(plainBytes, Charsets.UTF_8)
        }
        if (trimmed.startsWith("SOV2:")) {
            val parts = trimmed.split(":")
            if (parts.size < 4) throw IllegalArgumentException("Malformed SOV2 payload")
            val saltB64 = parts[1]
            val ivB64 = parts[2]
            val cipherB64 = parts[3]
            val salt = Base64.decode(saltB64, Base64.NO_WRAP)
            val iv = Base64.decode(ivB64, Base64.NO_WRAP)
            val cipherBytes = Base64.decode(cipherB64, Base64.NO_WRAP)
            if (!passphrase.isNullOrEmpty()) {
                try {
                    val key = derivePassphraseKey(passphrase, salt, LEGACY_PBKDF2_ITERATIONS)
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
                    val plainBytes = cipher.doFinal(cipherBytes)
                    return String(plainBytes, Charsets.UTF_8)
                } catch (_: Throwable) {}
            }
            try {
                val legacyKey = derivePassphraseKey(LEGACY_PHASE38_SECRET, salt, LEGACY_PBKDF2_ITERATIONS)
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.DECRYPT_MODE, legacyKey, GCMParameterSpec(128, iv))
                val plainBytes = cipher.doFinal(cipherBytes)
                return String(plainBytes, Charsets.UTF_8)
            } catch (e: Throwable) {
                throw IllegalArgumentException("Decryption failed for legacy Phase 38 SOV2 backup: ${e.message}", e)
            }
        }
        try {
            val xorBytes = Base64.decode(trimmed, Base64.NO_WRAP)
            val plainBytes = ByteArray(xorBytes.size) { i -> (xorBytes[i].toInt() xor 0x53).toByte() }
            val decoded = String(plainBytes, Charsets.UTF_8)
            if (decoded.startsWith("{")) return decoded
        } catch (_: Exception) {}
        throw IllegalArgumentException("Unrecognized or corrupted backup payload")
    }

    fun runNativeSecuritySelfTest(): Map<String, Any> {
        val results = mutableMapOf<String, Any>()
        val plainText = "SOVEREIGN_VAULT_TEST_PAYLOAD_αβγ_12345"
        val passphrase = "test-passphrase-alpha"

        val encP = encryptConfig(plainText, passphrase)
        val pParts = encP.split(":")
        results["format_correct"] = encP.startsWith("SOV2:P:250000:") && pParts.size == 6

        val decP = decryptConfig(encP, passphrase)
        results["roundtrip_passphrase"] = (decP == plainText)

        var tamperCaught = false
        try {
            val badCipher = encP.substring(0, encP.length - 4) + "AAAA"
            decryptConfig(badCipher, passphrase)
        } catch (_: Throwable) {
            tamperCaught = true
        }
        results["tamper_resistance"] = tamperCaught

        var lowIterCaught = false
        try {
            decryptConfig("SOV2:P:500:${pParts[3]}:${pParts[4]}:${pParts[5]}", passphrase)
        } catch (_: IllegalArgumentException) {
            lowIterCaught = true
        }
        results["min_iterations_enforced"] = lowIterCaught

        var highIterCaught = false
        try {
            decryptConfig("SOV2:P:5000000:${pParts[3]}:${pParts[4]}:${pParts[5]}", passphrase)
        } catch (_: IllegalArgumentException) {
            highIterCaught = true
        }
        results["max_iterations_enforced"] = highIterCaught

        val random = SecureRandom()
        val legacySalt = ByteArray(16).also { random.nextBytes(it) }
        val legacyIv = ByteArray(12).also { random.nextBytes(it) }
        val legacyKey = derivePassphraseKey(LEGACY_PHASE38_SECRET, legacySalt, LEGACY_PBKDF2_ITERATIONS)
        val legacyCipher = Cipher.getInstance("AES/GCM/NoPadding")
        legacyCipher.init(Cipher.ENCRYPT_MODE, legacyKey, GCMParameterSpec(128, legacyIv))
        val legacyCipherBytes = legacyCipher.doFinal(plainText.toByteArray(Charsets.UTF_8))
        val legacyPayload = "SOV2:${Base64.encodeToString(legacySalt, Base64.NO_WRAP)}:${Base64.encodeToString(legacyIv, Base64.NO_WRAP)}:${Base64.encodeToString(legacyCipherBytes, Base64.NO_WRAP)}"
        val decLegacy = decryptConfig(legacyPayload, null)
        results["legacy_phase38_fallback"] = (decLegacy == plainText)

        var pathTraversalCaught = false
        try {
            validateRecoveryFile("../../etc/hosts")
        } catch (_: SecurityException) {
            pathTraversalCaught = true
        }
        results["path_traversal_confinement"] = pathTraversalCaught

        val recoveryDir = File(context.filesDir, "sov_recovery").apply { mkdirs() }
        val randomSuffix = UUID.randomUUID().toString().replace("-", "").take(8)
        val uniqueName = "sov_rec_selftest_${System.currentTimeMillis()}_$randomSuffix"
        val testBak = File(recoveryDir, "$uniqueName.bak")
        val testMeta = File(recoveryDir, "$uniqueName.meta")
        try {
            testBak.writeText("TEST_BACKUP")
            testMeta.writeText("URI=content://media/test\nSTATUS=PENDING\n")
            val discardSuccess = discardPendingOverwrite(testBak.absolutePath)
            val cleaned = discardSuccess && !testBak.exists() && !testMeta.exists()
            results["discard_cleanup_success"] = cleaned
            results["discard_atomic_success"] = cleaned
        } finally {
            try { testBak.delete() } catch (_: Throwable) {}
            try { testMeta.delete() } catch (_: Throwable) {}
        }

        results["all_passed"] = results.values.all { it == true }
        return results
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
                context.contentResolver.openOutputStream(uri)?.use { it.write(data.toByteArray(Charsets.UTF_8)) }
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
            var raw = ""
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
                        context.contentResolver.openInputStream(uri)?.use { raw = it.bufferedReader().readText() }
                    }
                }
            } else {
                val file = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "sovereign_config.bin")
                if (file.exists()) raw = file.readText()
            }
            if (raw.isNotEmpty()) {
                val trimmed = raw.trim()
                if (trimmed.startsWith("SOV2:K:")) {
                    return decryptConfig(trimmed, null)
                } else if (!trimmed.startsWith("SOV2:")) {
                    return decryptConfig(trimmed, null)
                }
            }
        } catch (_: Exception) {}
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
