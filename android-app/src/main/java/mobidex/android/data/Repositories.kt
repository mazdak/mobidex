package mobidex.android.data

import android.content.Context
import androidx.core.content.edit
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import mobidex.android.model.SSHCredential
import mobidex.android.model.ServerRecord

interface ServerRepository {
    suspend fun loadServers(): List<ServerRecord>
    suspend fun saveServers(servers: List<ServerRecord>)
}

class SharedPreferencesServerRepository(context: Context) : ServerRepository {
    private val prefs = context.getSharedPreferences("mobidex_servers", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }

    override suspend fun loadServers(): List<ServerRecord> = withContext(Dispatchers.IO) {
        prefs.getString(KEY, null)?.let { json.decodeFromString<List<ServerRecord>>(it) } ?: emptyList()
    }

    override suspend fun saveServers(servers: List<ServerRecord>) = withContext(Dispatchers.IO) {
        prefs.edit { putString(KEY, json.encodeToString(servers)) }
    }

    private companion object {
        const val KEY = "mobidex.servers.android.v1"
    }
}

interface CredentialStore {
    suspend fun loadCredential(serverID: String): SSHCredential
    suspend fun saveCredential(credential: SSHCredential, serverID: String)
    suspend fun deleteCredential(serverID: String)
}

interface HostKeyStore {
    fun loadHostKeyFingerprint(serverID: String): String?
    fun saveHostKeyFingerprint(serverID: String, host: String, port: Int, fingerprint: String)
    fun deleteHostKeyFingerprint(serverID: String)
}

class SharedPreferencesHostKeyStore(context: Context) : HostKeyStore {
    private val prefs = context.getSharedPreferences("mobidex_host_keys", Context.MODE_PRIVATE)

    override fun loadHostKeyFingerprint(serverID: String): String? =
        prefs.getString(fingerprintKey(serverID), null)

    override fun saveHostKeyFingerprint(serverID: String, host: String, port: Int, fingerprint: String) {
        prefs.edit {
            putString(fingerprintKey(serverID), fingerprint)
            putString(endpointKey(serverID), "$host:$port")
        }
    }

    override fun deleteHostKeyFingerprint(serverID: String) {
        prefs.edit {
            remove(fingerprintKey(serverID))
            remove(endpointKey(serverID))
        }
    }

    private fun fingerprintKey(serverID: String): String {
        UUID.fromString(serverID)
        return "$serverID.fingerprint"
    }

    private fun endpointKey(serverID: String): String {
        UUID.fromString(serverID)
        return "$serverID.endpoint"
    }
}

class AndroidCredentialStore(context: Context) : CredentialStore {
    private val prefs = context.getSharedPreferences("mobidex_credentials", Context.MODE_PRIVATE)
    private val valueCrypto = AndroidKeystoreValueCrypto()

    override suspend fun loadCredential(serverID: String): SSHCredential = withContext(Dispatchers.IO) {
        SSHCredential(
            password = readSecret(account(serverID, "password")),
            privateKeyPEM = readSecret(account(serverID, "private-key")),
            privateKeyPassphrase = readSecret(account(serverID, "private-key-passphrase")),
        )
    }

    override suspend fun saveCredential(credential: SSHCredential, serverID: String) = withContext(Dispatchers.IO) {
        prefs.edit {
            writeSecret(account(serverID, "password"), credential.password)
            writeSecret(account(serverID, "private-key"), credential.privateKeyPEM)
            writeSecret(account(serverID, "private-key-passphrase"), credential.privateKeyPassphrase)
        }
    }

    override suspend fun deleteCredential(serverID: String) = withContext(Dispatchers.IO) {
        prefs.edit {
            remove(account(serverID, "password"))
            remove(account(serverID, "private-key"))
            remove(account(serverID, "private-key-passphrase"))
        }
    }

    private fun android.content.SharedPreferences.Editor.writeSecret(key: String, value: String?) {
        if (value.isNullOrEmpty()) remove(key) else putString(key, valueCrypto.encrypt(value))
    }

    private fun readSecret(key: String): String? {
        val encrypted = prefs.getString(key, null) ?: return null
        return runCatching { valueCrypto.decrypt(encrypted) }
            .onFailure { prefs.edit { remove(key) } }
            .getOrNull()
    }

    private fun account(serverID: String, kind: String): String {
        UUID.fromString(serverID)
        return "$serverID.$kind"
    }
}

private class AndroidKeystoreValueCrypto {
    private val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
    private val keyLock = Any()

    fun encrypt(value: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey())
        val ciphertext = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(cipher.iv + ciphertext, Base64.NO_WRAP)
    }

    fun decrypt(encodedValue: String): String {
        val payload = Base64.decode(encodedValue, Base64.NO_WRAP)
        require(payload.size > GCM_IV_BYTES) { "Credential payload is malformed." }
        val iv = payload.copyOfRange(0, GCM_IV_BYTES)
        val ciphertext = payload.copyOfRange(GCM_IV_BYTES, payload.size)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateSecretKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
        return cipher.doFinal(ciphertext).toString(Charsets.UTF_8)
    }

    private fun getOrCreateSecretKey(): SecretKey {
        synchronized(keyLock) {
            (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
            val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
            val spec = KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build()
            generator.init(spec)
            return generator.generateKey()
        }
    }

    private companion object {
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val KEY_ALIAS = "mobidex.credentials.v1"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val GCM_IV_BYTES = 12
        const val GCM_TAG_BITS = 128
    }
}
