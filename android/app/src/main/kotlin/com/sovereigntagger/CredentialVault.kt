// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.io.IOException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal class CredentialVault(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(
        "sovereign_credentials_v1", Context.MODE_PRIVATE
    )

    companion object {
        private const val KEY_ALIAS = "SovereignCredentialsAES256_v1"
        private const val KEY_STORE = "AndroidKeyStore"
        private val VALID_KEYS = setOf(
            "pcloud_token", "genius_key", "acr_key", "acr_secret", "hf_token"
        )
    }

    private fun validate(name: String) {
        require(name in VALID_KEYS) { "Unknown credential name" }
    }

    private fun secretKey(): SecretKey {
        val store = KeyStore.getInstance(KEY_STORE).apply { load(null) }
        val existing = store.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry
        if (existing != null) return existing.secretKey
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEY_STORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setKeySize(256)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build()
        )
        return generator.generateKey()
    }

    @Synchronized
    fun read(name: String): String? {
        validate(name)
        val record = prefs.getString(name, null) ?: return null
        val parts = record.split(':')
        if (parts.size != 3 || parts[0] != "v1") {
            throw IOException("Credential vault format mismatch")
        }
        try {
            val nonce = Base64.decode(parts[1], Base64.NO_WRAP)
            val encrypted = Base64.decode(parts[2], Base64.NO_WRAP)
            if (nonce.size != 12 || encrypted.size < 16 || encrypted.size > 131088) {
                throw IOException("Credential vault payload rejected")
            }
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, nonce))
            cipher.updateAAD(name.toByteArray(Charsets.UTF_8))
            return cipher.doFinal(encrypted).toString(Charsets.UTF_8)
        } catch (e: Exception) {
            throw IOException("Credential vault decrypt failed; sign in again or recover key", e)
        }
    }

    @Synchronized
    fun write(name: String, value: String) {
        validate(name)
        if (value.isEmpty()) {
            delete(name)
            return
        }
        require(value.length <= 65536) { "Credential payload too long" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        cipher.updateAAD(name.toByteArray(Charsets.UTF_8))
        val nonce = Base64.encodeToString(cipher.iv, Base64.NO_WRAP)
        val ciphertext = Base64.encodeToString(
            cipher.doFinal(value.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP
        )
        val record = "v1:$nonce:$ciphertext"
        if (!prefs.edit().putString(name, record).commit()) {
            throw IOException("Credential vault persistence failed")
        }
        if (read(name) != value) throw IOException("Credential vault verification failed")
    }

    @Synchronized
    fun delete(name: String) {
        validate(name)
        if (!prefs.edit().remove(name).commit()) {
            throw IOException("Credential vault deletion failed")
        }
    }
}
