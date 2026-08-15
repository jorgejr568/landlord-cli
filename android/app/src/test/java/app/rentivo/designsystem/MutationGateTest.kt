package app.rentivo.designsystem

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MutationGateTest {

  @Test
  fun overlappingMutationsAreDroppedAndTheGateReopensAfterCompletion() = runBlocking {
    val gate = MutationGate()
    val started = CompletableDeferred<Unit>()
    val release = CompletableDeferred<Unit>()
    var calls = 0

    val first = launch {
      gate.run {
        calls += 1
        started.complete(Unit)
        release.await()
      }
    }
    started.await()

    gate.run { calls += 1 }
    assertTrue(gate.isRunning)
    assertEquals(1, calls)

    release.complete(Unit)
    first.join()
    assertFalse(gate.isRunning)

    gate.run { calls += 1 }
    assertEquals(2, calls)
  }

  @Test
  fun failuresAlwaysReopenTheGate() = runBlocking {
    val gate = MutationGate()

    runCatching { gate.run { error("boom") } }

    assertFalse(gate.isRunning)
  }
}
