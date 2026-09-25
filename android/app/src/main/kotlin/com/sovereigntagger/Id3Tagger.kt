// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import android.util.Base64
import org.jaudiotagger.audio.AudioFileIO
import org.jaudiotagger.tag.FieldKey
import org.jaudiotagger.tag.TagField
import org.jaudiotagger.tag.id3.AbstractID3v2Frame
import org.jaudiotagger.tag.id3.AbstractID3v2Tag
import org.jaudiotagger.tag.id3.ID3v23Frame
import org.jaudiotagger.tag.id3.ID3v23Tag
import org.jaudiotagger.tag.id3.ID3v24Frame
import org.jaudiotagger.tag.id3.framebody.FrameBodyTXXX
import org.jaudiotagger.tag.images.ArtworkFactory
import java.io.File

object Id3Tagger {
    fun writeTags(filePath: String, metadata: Map<String, String>): Boolean {
        return try {
            val audioFile = AudioFileIO.read(File(filePath))
            val tag = audioFile.tagOrCreateAndSetDefault

            metadata.forEach { (key, value) ->
                try {
                    when (key.uppercase()) {
                        "TITLE" -> if (value.isEmpty()) tag.deleteField(FieldKey.TITLE) else tag.setField(FieldKey.TITLE, value)
                        "ARTIST" -> if (value.isEmpty()) tag.deleteField(FieldKey.ARTIST) else tag.setField(FieldKey.ARTIST, value)
                        "ALBUM" -> if (value.isEmpty()) tag.deleteField(FieldKey.ALBUM) else tag.setField(FieldKey.ALBUM, value)
                        "ALBUM_ARTIST" -> if (value.isEmpty()) tag.deleteField(FieldKey.ALBUM_ARTIST) else tag.setField(FieldKey.ALBUM_ARTIST, value)
                        "YEAR" -> if (value.isEmpty()) tag.deleteField(FieldKey.YEAR) else tag.setField(FieldKey.YEAR, value)
                        "GENRE" -> if (value.isEmpty()) tag.deleteField(FieldKey.GENRE) else tag.setField(FieldKey.GENRE, value)
                        "DISC_NO" -> if (value.isEmpty()) tag.deleteField(FieldKey.DISC_NO) else tag.setField(FieldKey.DISC_NO, value)
                        "TRACK" -> if (value.isEmpty()) tag.deleteField(FieldKey.TRACK) else tag.setField(FieldKey.TRACK, value)
                        "TRACK_TOTAL" -> if (value.isEmpty()) tag.deleteField(FieldKey.TRACK_TOTAL) else tag.setField(FieldKey.TRACK_TOTAL, value)
                        "DISC_TOTAL" -> if (value.isEmpty()) tag.deleteField(FieldKey.DISC_TOTAL) else tag.setField(FieldKey.DISC_TOTAL, value)
                        "COMMENT" -> if (value.isEmpty()) tag.deleteField(FieldKey.COMMENT) else tag.setField(FieldKey.COMMENT, value)
                        "COMPOSER" -> if (value.isEmpty()) tag.deleteField(FieldKey.COMPOSER) else tag.setField(FieldKey.COMPOSER, value)
                        "PRODUCER" -> if (value.isEmpty()) tag.deleteField(FieldKey.PRODUCER) else tag.setField(FieldKey.PRODUCER, value)
                        "LYRICS" -> if (value.isEmpty()) tag.deleteField(FieldKey.LYRICS) else tag.setField(FieldKey.LYRICS, value)
                        "ENCODER" -> if (value.isEmpty()) tag.deleteField(FieldKey.ENCODER) else tag.setField(FieldKey.ENCODER, value)
                        "LANGUAGE" -> if (value.isEmpty()) tag.deleteField(FieldKey.LANGUAGE) else tag.setField(FieldKey.LANGUAGE, value)
                        "REPLAYGAIN_TRACK_GAIN" -> setReplayGainTag(tag, "REPLAYGAIN_TRACK_GAIN", value)
                        "REPLAYGAIN_TRACK_PEAK" -> setReplayGainTag(tag, "REPLAYGAIN_TRACK_PEAK", value)
                        "REPLAYGAIN_ALBUM_GAIN" -> setReplayGainTag(tag, "REPLAYGAIN_ALBUM_GAIN", value)
                        "REPLAYGAIN_ALBUM_PEAK" -> setReplayGainTag(tag, "REPLAYGAIN_ALBUM_PEAK", value)
                        "ARTWORK_BASE64" -> {
                            if (value.isEmpty()) {
                                tag.deleteArtworkField()
                            } else {
                                val imageBytes = Base64.decode(value, Base64.DEFAULT)
                                val artwork = ArtworkFactory.getNew()
                                artwork.binaryData = imageBytes
                                artwork.mimeType = sniffImageMime(imageBytes)
                                tag.deleteArtworkField()
                                tag.setField(artwork)
                            }
                        }
                    }
                } catch (e: Exception) {
                }
            }
            audioFile.commit()
            true
        } catch (e: Exception) {
            false
        }
    }

    fun readTags(filePath: String): Map<String, String> {
        val tags = mutableMapOf<String, String>()
        try {
            val audioFile = AudioFileIO.read(File(filePath))
            try {
                tags["DURATION_MS"] = ((audioFile.audioHeader?.preciseTrackLength ?: 0.0) * 1000).toLong().toString()
            } catch (_: Exception) {}
            val tag = audioFile.tag ?: return tags

            tags["TITLE"] = first(tag, FieldKey.TITLE)
            tags["ARTIST"] = first(tag, FieldKey.ARTIST)
            tags["ALBUM"] = first(tag, FieldKey.ALBUM)
            tags["ALBUM_ARTIST"] = first(tag, FieldKey.ALBUM_ARTIST)
            tags["YEAR"] = first(tag, FieldKey.YEAR)
            tags["GENRE"] = first(tag, FieldKey.GENRE)
            tags["DISC_NO"] = first(tag, FieldKey.DISC_NO)
            tags["TRACK"] = first(tag, FieldKey.TRACK)
            tags["TRACK_TOTAL"] = first(tag, FieldKey.TRACK_TOTAL)
            tags["DISC_TOTAL"] = first(tag, FieldKey.DISC_TOTAL)
            tags["COMMENT"] = first(tag, FieldKey.COMMENT)
            tags["COMPOSER"] = first(tag, FieldKey.COMPOSER)
            tags["PRODUCER"] = first(tag, FieldKey.PRODUCER)
            tags["LYRICS"] = first(tag, FieldKey.LYRICS)
            tags["ENCODER"] = first(tag, FieldKey.ENCODER)
            tags["LANGUAGE"] = first(tag, FieldKey.LANGUAGE)
            
            val artwork = tag.firstArtwork
            if (artwork != null && artwork.binaryData != null) {
                tags["ARTWORK_BASE64"] = Base64.encodeToString(artwork.binaryData, Base64.NO_WRAP)
            }
            
            val replayGainFields = listOf("REPLAYGAIN_TRACK_GAIN", "REPLAYGAIN_TRACK_PEAK", "REPLAYGAIN_ALBUM_GAIN", "REPLAYGAIN_ALBUM_PEAK")
            replayGainFields.forEach { fieldName ->
                val value = getReplayGainTag(tag, fieldName)
                if (value.isNotEmpty()) tags[fieldName] = value
            }
        } catch (e: Exception) {
        }
        return tags
    }

    private fun first(tag: org.jaudiotagger.tag.Tag, key: FieldKey): String {
        return try { tag.getFirst(key) ?: "" } catch (_: Exception) { "" }
    }

    private fun sniffImageMime(bytes: ByteArray): String {
        if (bytes.size > 4 && bytes[0] == 0x89.toByte() && bytes[1] == 0x50.toByte() && bytes[2] == 0x4E.toByte() && bytes[3] == 0x47.toByte()) return "image/png"
        return "image/jpeg"
    }

    private fun setReplayGainTag(tag: org.jaudiotagger.tag.Tag, fieldName: String, value: String) {
        try {
            val id3Tag = tag as? AbstractID3v2Tag ?: return
            val kept = mutableListOf<TagField>()
            for (f in id3Tag.getFields("TXXX")) {
                val body = (f as? AbstractID3v2Frame)?.body as? FrameBodyTXXX
                if (body?.description != fieldName) kept.add(f)
            }
            id3Tag.removeFrame("TXXX")
            for (f in kept) id3Tag.addField(f)
            if (value.isNotEmpty()) {
                val body = FrameBodyTXXX()
                body.description = fieldName
                body.text = value
                val frame: AbstractID3v2Frame = when (id3Tag) {
                    is ID3v23Tag -> ID3v23Frame("TXXX")
                    else -> ID3v24Frame("TXXX")
                }
                frame.body = body
                id3Tag.addField(frame)
            }
        } catch (_: Exception) {}
    }

    private fun getReplayGainTag(tag: org.jaudiotagger.tag.Tag, fieldName: String): String {
        try {
            val id3Tag = tag as? AbstractID3v2Tag ?: return ""
            val fields = id3Tag.getFields("TXXX")
            for (f in fields) {
                try {
                    val body = (f as? AbstractID3v2Frame)?.body as? FrameBodyTXXX
                    if (body?.description == fieldName) return body.text ?: ""
                } catch (_: Exception) {}
            }
        } catch (_: Exception) {}
        return ""
    }
}