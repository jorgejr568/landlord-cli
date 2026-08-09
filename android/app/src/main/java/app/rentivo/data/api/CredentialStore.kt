package app.rentivo.data.api

import app.rentivo.domain.LocalizedError
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * The access token's storage boundary. The production implementation is hardware-backed; unit
 * tests substitute [MemoryCredentialStore].
 */
interface CredentialStore {
  suspend fun readAccessToken(): String?

  suspend fun saveAccessToken(token: String)

  suspend fun deleteAccessToken()
}

/** Raised when the platform-backed store cannot be reached. */
class CredentialStoreError(cause: Throwable? = null) :
  Exception("Não foi possível acessar a sessão segura neste dispositivo.", cause),
  LocalizedError {
  override val errorDescription: String
    get() = "Não foi possível acessar a sessão segura neste dispositivo."
}

/**
 * In-memory store, serialized through a [Mutex] so it behaves like the Swift `actor` it mirrors.
 */
class MemoryCredentialStore(token: String? = null) : CredentialStore {
  private val mutex = Mutex()
  private var token: String? = token

  override suspend fun readAccessToken(): String? = mutex.withLock { token }

  override suspend fun saveAccessToken(token: String) {
    mutex.withLock { this.token = token }
  }

  override suspend fun deleteAccessToken() {
    mutex.withLock { token = null }
  }
}
