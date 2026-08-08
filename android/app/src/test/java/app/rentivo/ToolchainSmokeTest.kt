package app.rentivo

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Smoke test for the pure-JVM half of the toolchain the domain and data layers
 * are going to be built on: coroutines, kotlinx-serialization, OkHttp and
 * MockWebServer all have to work under `:app:testDebugUnitTest`.
 */
class ToolchainSmokeTest {

    @Serializable
    private data class Billing(val id: String, val amountCentavos: Long)

    @Test
    fun `decodes a json payload served over http`() = runTest {
        val server = MockWebServer()
        server.enqueue(
            MockResponse().setBody("""{"id":"bil_1","amountCentavos":125000}"""),
        )
        server.start()

        try {
            val request = Request.Builder().url(server.url("/api/v1/billings/bil_1")).build()
            val body = withContext(Dispatchers.IO) {
                OkHttpClient().newCall(request).execute().use { checkNotNull(it.body).string() }
            }

            val billing = Json.decodeFromString<Billing>(body)

            assertEquals("bil_1", billing.id)
            assertEquals(125_000L, billing.amountCentavos)
        } finally {
            server.shutdown()
        }
    }
}
