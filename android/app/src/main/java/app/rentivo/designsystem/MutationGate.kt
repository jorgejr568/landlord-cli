package app.rentivo.designsystem

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Serializes a screen's mutations and exposes observable state for disabling its controls.
 * Compose event handlers run on the main thread, so the check-and-set before the first suspension
 * makes rapid taps single-flight without a mutex that could queue an obsolete second request.
 */
@Stable
internal class MutationGate {
  var isRunning: Boolean by mutableStateOf(false)
    private set

  suspend fun run(block: suspend () -> Unit) {
    if (isRunning) return
    isRunning = true
    try {
      block()
    } finally {
      isRunning = false
    }
  }
}
