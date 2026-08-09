package app.rentivo.data

import app.rentivo.data.api.MemoryCredentialStore
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CredentialStoreTest {

  @Test
  fun memoryCredentialStoreRoundTripsAndDeletesToken() = runTest {
    val credentials = MemoryCredentialStore()

    assertNull(credentials.readAccessToken())

    credentials.saveAccessToken("session-token")
    assertEquals("session-token", credentials.readAccessToken())

    credentials.deleteAccessToken()
    assertNull(credentials.readAccessToken())
  }

  @Test
  fun memoryCredentialStoreSeedsFromItsInitialToken() = runTest {
    val credentials = MemoryCredentialStore(token = "stored-token")

    assertEquals("stored-token", credentials.readAccessToken())
  }
}
