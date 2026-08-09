package app.rentivo.data.api

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The production [CredentialStore], backed by `EncryptedSharedPreferences` over a hardware-backed
 * AES-256-GCM master key.
 *
 * Android counterpart of the iOS `KeychainCredentialStore`: same single-entry contract, same
 * failure translation into [CredentialStoreError], and the token likewise never leaves the device.
 * Reads and writes hop to [ioDispatcher] because both the keystore unwrap and the backing file are
 * blocking. The preferences handle is created lazily so a keystore failure surfaces as a
 * [CredentialStoreError] from a suspend function rather than from the constructor.
 */
class EncryptedCredentialStore(
  context: Context,
  private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) : CredentialStore {

  private val appContext = context.applicationContext

  private val preferences: SharedPreferences by lazy {
    val masterKey = MasterKey.Builder(appContext)
      .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
      .build()
    EncryptedSharedPreferences.create(
      appContext,
      FILE_NAME,
      masterKey,
      EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
      EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )
  }

  override suspend fun readAccessToken(): String? = guarded {
    preferences.getString(TOKEN_KEY, null)
  }

  override suspend fun saveAccessToken(token: String) {
    guarded { preferences.edit().putString(TOKEN_KEY, token).commit() }
  }

  override suspend fun deleteAccessToken() {
    guarded { preferences.edit().remove(TOKEN_KEY).commit() }
  }

  private suspend fun <T> guarded(block: () -> T): T = withContext(ioDispatcher) {
    try {
      block()
    } catch (cancellation: CancellationException) {
      // Cancellation is how a coroutine unwinds, not a keystore failure: wrapping it would make
      // the caller's `catch (error: CredentialStoreError)` swallow its own cancellation.
      throw cancellation
    } catch (exception: Exception) {
      throw CredentialStoreError(exception)
    }
  }

  private companion object {
    const val FILE_NAME = "rentivo.credentials"
    const val TOKEN_KEY = "rentivo.access-token"
  }
}
