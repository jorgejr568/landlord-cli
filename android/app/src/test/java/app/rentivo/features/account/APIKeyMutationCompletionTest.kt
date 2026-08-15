package app.rentivo.features.account

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

class APIKeyMutationCompletionTest {

  @Test
  fun `an API key mutation reloads the list before dismissing its form`() = runTest {
    val events = mutableListOf<String>()

    completeAPIKeyMutation(
      reload = { events += "reload" },
      complete = { events += "dismiss" },
    )

    assertEquals(listOf("reload", "dismiss"), events)
  }
}
