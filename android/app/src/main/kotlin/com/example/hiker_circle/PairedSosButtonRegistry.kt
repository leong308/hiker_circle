// PairedSosButtonRegistry persists pairing credentials, replay counters, and passive presence.
package com.leongziqi.hikercircle

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.nio.ByteBuffer
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Private, device-local ownership registry for paired SOS remotes.
 *
 * The pairing secret never crosses the Flutter channel or leaves this class
 * after it has been written to the button. The stored JSON is encrypted with
 * a non-exportable Android Keystore AES key.
 */
class PairedSosButtonRegistry(context: Context) {
    companion object {
        private const val PREFS = "hiker_circle_paired_sos_buttons"
        private const val ENCRYPTED_ENTRIES = "encrypted_entries"
        private const val LEGACY_UNPAIRED_ENABLED = "legacy_unpaired_enabled"
        private const val ACTIVE_OWNER_SCOPE = "active_owner_scope"
        private const val DEFAULT_DISPLAY_NAME = "HikerCircle Button"
        private const val KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "hiker_circle_paired_sos_buttons_v1"
        private const val GCM_IV_BYTES = 12
        private const val GCM_TAG_BITS = 128
        private val random = SecureRandom()
    }

    private val appContext = context.applicationContext
    private val preferences = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    data class Button(
        val deviceIdHex: String,
        val address: String?,
        val displayName: String,
        val pairedAtMillis: Long,
        val lastSeenAtMillis: Long?,
        val lastAcceptedEventId: Long?,
        val ownerScope: String?,
        internal val pairingSecret: ByteArray,
    )

    data class NewPairing(
        val deviceId: ByteArray,
        val pairingSecret: ByteArray,
    )

    fun newPairingMaterial(): NewPairing {
        return NewPairing(
            deviceId = ByteArray(6).also(random::nextBytes),
            pairingSecret = ByteArray(32).also(random::nextBytes),
        )
    }

    fun setActiveOwnerScope(accountId: String?) {
        val scope = accountId?.trim()?.takeIf { it.isNotEmpty() }?.let(::ownerScopeFor)
        check(
            preferences.edit().apply {
                if (scope == null) {
                    remove(ACTIVE_OWNER_SCOPE)
                } else {
                    putString(ACTIVE_OWNER_SCOPE, scope)
                }
            }.commit(),
        ) { "Unable to persist the active SOS button account scope." }
    }

    fun hasActiveOwnerScope(): Boolean = activeOwnerScope() != null

    /** Reject notification-history reads from a displaced app account. */
    fun matchesActiveAccount(accountId: String?): Boolean = accountId != null && activeOwnerScope() == ownerScopeFor(accountId)

    fun activeOwnerScopeToken(): String? = activeOwnerScope()

    fun buttons(): List<Button> = readButtons()
        .filter(::belongsToActiveOwner)
        .map { it.copy(pairingSecret = ByteArray(0)) }

    fun find(deviceId: ByteArray): Button? {
        val deviceIdHex = deviceId.hex()
        return readButtons().firstOrNull {
            it.deviceIdHex == deviceIdHex && belongsToActiveOwner(it)
        }
    }

    fun find(deviceIdHex: String): Button? {
        return readButtons().firstOrNull {
            it.deviceIdHex == deviceIdHex.trim().uppercase() && belongsToActiveOwner(it)
        }
    }

    fun saveConfirmedPairing(
        deviceId: ByteArray,
        pairingSecret: ByteArray,
        displayName: String,
        address: String? = null,
        expectedOwnerScope: String? = null,
    ) {
        require(deviceId.size == 6) { "Paired SOS device IDs must be six bytes." }
        require(pairingSecret.size == 32) { "Paired SOS secrets must be 32 bytes." }
        val ownerScope = requireNotNull(activeOwnerScope()) {
            "An app account must be active before an SOS button can be paired."
        }
        require(expectedOwnerScope == null || expectedOwnerScope == ownerScope) {
            "The signed-in account changed during SOS button pairing."
        }
        val normalizedAddress = address?.trim()?.uppercase()
        val current = readButtons().filterNot {
            it.deviceIdHex == deviceId.hex() ||
                (normalizedAddress != null && it.address == normalizedAddress)
        }.toMutableList()
        current += Button(
            deviceIdHex = deviceId.hex(),
            address = normalizedAddress,
            displayName = displayName.trim().ifBlank { DEFAULT_DISPLAY_NAME },
            pairedAtMillis = System.currentTimeMillis(),
            lastSeenAtMillis = null,
            lastAcceptedEventId = null,
            ownerScope = ownerScope,
            pairingSecret = pairingSecret.copyOf(),
        )
        writeButtons(current)
    }

    fun remove(deviceIdHex: String): Boolean {
        val current = readButtons()
        val updated = current.filterNot {
            it.deviceIdHex == deviceIdHex.uppercase() && belongsToActiveOwner(it)
        }
        if (updated.size == current.size) return false
        writeButtons(updated)
        return true
    }

    fun markSeen(deviceId: ByteArray, eventId: Long? = null, accepted: Boolean = false) {
        val deviceIdHex = deviceId.hex()
        val updated = readButtons().map { button ->
            if (button.deviceIdHex != deviceIdHex || !belongsToActiveOwner(button)) {
                button
            } else {
                button.copy(
                    lastSeenAtMillis = System.currentTimeMillis(),
                    lastAcceptedEventId = if (accepted && eventId != null) eventId
                        else button.lastAcceptedEventId,
                )
            }
        }
        writeButtons(updated)
    }

    /** Updates passive presence without exposing pairing material to callers. */
    fun markSeenByAddress(address: String): String? {
        val normalizedAddress = address.trim().uppercase()
        if (normalizedAddress.isEmpty()) return null
        var matchedDeviceId: String? = null
        val updated = readButtons().map { button ->
            if (button.address != normalizedAddress || !belongsToActiveOwner(button)) {
                button
            } else {
                matchedDeviceId = button.deviceIdHex
                button.copy(lastSeenAtMillis = System.currentTimeMillis())
            }
        }
        if (matchedDeviceId != null) writeButtons(updated)
        return matchedDeviceId
    }

    fun isReplay(button: Button, eventId: Long): Boolean {
        val last = button.lastAcceptedEventId ?: return false
        // RFC-1982-style uint32 serial arithmetic permits the legitimate
        // 0xffffffff -> 0 wrap, while a firmware reset back to a small value
        // remains rejected. A reset button must be physically re-paired so an
        // old authenticated advertisement can never become valid again.
        val forwardDistance = (eventId - last).and(0xffffffffL)
        return forwardDistance == 0L || forwardDistance >= 0x80000000L
    }

    fun hasValidTag(button: Button, packet: HikerBleProtocol.PairedSosRemotePacket): Boolean {
        if (button.pairingSecret.size != 32 || packet.messageTag.size != 8) return false
        val tag = Mac.getInstance("HmacSHA256")
            .apply { init(javax.crypto.spec.SecretKeySpec(button.pairingSecret, "HmacSHA256")) }
            .doFinal(packet.signedPayload)
            .copyOfRange(0, 8)
        return MessageDigest.isEqual(tag, packet.messageTag)
    }

    /**
     * Drops only device-local pairing material so a registry restored without
     * its Keystore key can recover in-app. The active account scope is kept so
     * the user can immediately pair the physical button again.
     */
    fun resetRegistry() {
        val editor = preferences.edit()
            .remove(ENCRYPTED_ENTRIES)
            .remove(LEGACY_UNPAIRED_ENABLED)
        preferences.all.keys.filter { it.startsWith(LEGACY_UNPAIRED_ENABLED) }.forEach(editor::remove)
        check(
            editor.commit(),
        ) { "Unable to clear the paired SOS button registry." }

        val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        if (keyStore.containsAlias(KEY_ALIAS)) {
            keyStore.deleteEntry(KEY_ALIAS)
        }
    }

    private fun readButtons(): List<Button> {
        val encrypted = preferences.getString(ENCRYPTED_ENTRIES, null) ?: return emptyList()
        return runCatching {
            val plain = decrypt(encrypted)
            val array = JSONArray(plain)
            buildList {
                for (index in 0 until array.length()) {
                    val item = array.getJSONObject(index)
                    add(
                        Button(
                            deviceIdHex = item.getString("deviceId").uppercase(),
                            address = item.optString("address", "").trim()
                                .takeIf { it.isNotEmpty() },
                            displayName = item.optString("displayName", DEFAULT_DISPLAY_NAME)
                                .trim()
                                .ifBlank { DEFAULT_DISPLAY_NAME },
                            pairedAtMillis = item.optLong("pairedAtMillis", 0),
                            lastSeenAtMillis = item.optLong("lastSeenAtMillis", 0).takeIf { it > 0 },
                            lastAcceptedEventId = item.optLong("lastAcceptedEventId", -1)
                                .takeIf { it >= 0 },
                            ownerScope = item.optString("ownerScope", "").trim()
                                .takeIf { it.isNotEmpty() },
                            pairingSecret = Base64.decode(item.getString("pairingSecret"), Base64.NO_WRAP),
                        ),
                    )
                }
            }
        }.getOrElse { error ->
            throw IllegalStateException(
                "Unable to decrypt the paired SOS button registry.",
                error,
            )
        }
    }

    private fun writeButtons(buttons: List<Button>) {
        val array = JSONArray()
        buttons.forEach { button ->
            array.put(
                JSONObject()
                    .put("deviceId", button.deviceIdHex)
                    .put("address", button.address ?: "")
                    .put("displayName", button.displayName)
                    .put("pairedAtMillis", button.pairedAtMillis)
                    .put("lastSeenAtMillis", button.lastSeenAtMillis ?: 0)
                    .put("lastAcceptedEventId", button.lastAcceptedEventId ?: -1)
                    .put("ownerScope", button.ownerScope ?: "")
                    .put("pairingSecret", Base64.encodeToString(button.pairingSecret, Base64.NO_WRAP)),
            )
        }
        check(
            preferences.edit()
                .putString(ENCRYPTED_ENTRIES, encrypt(array.toString()))
                .commit(),
        ) { "Unable to persist the paired SOS button registry." }
    }

    private fun activeOwnerScope(): String? =
        preferences.getString(ACTIVE_OWNER_SCOPE, null)?.takeIf { it.isNotBlank() }

    private fun belongsToActiveOwner(button: Button): Boolean {
        val active = activeOwnerScope() ?: return false
        return button.ownerScope == active
    }

    private fun ownerScopeFor(accountId: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(accountId.trim().lowercase().toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02X".format(it.toInt().and(0xff)) }

    private fun encrypt(value: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        // Let Android Keystore generate the randomized IV. Supplying our own
        // IV is rejected on devices enforcing randomized-encryption keys.
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val iv = cipher.iv
        val combined = ByteBuffer.allocate(iv.size + cipher.getOutputSize(value.toByteArray().size))
            .put(iv)
            .put(cipher.doFinal(value.toByteArray(Charsets.UTF_8)))
            .array()
        return Base64.encodeToString(combined, Base64.NO_WRAP)
    }

    private fun decrypt(value: String): String {
        val combined = Base64.decode(value, Base64.NO_WRAP)
        require(combined.size > GCM_IV_BYTES) { "Invalid paired-button registry." }
        val iv = combined.copyOfRange(0, GCM_IV_BYTES)
        val encrypted = combined.copyOfRange(GCM_IV_BYTES, combined.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(GCM_TAG_BITS, iv))
        return cipher.doFinal(encrypted).toString(Charsets.UTF_8)
    }

    private fun key(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE).apply {
            init(
                KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setRandomizedEncryptionRequired(true)
                    .build(),
            )
        }.generateKey()
    }

    private fun ByteArray.hex(): String = joinToString("") {
        "%02X".format(it.toInt().and(0xff))
    }
}
