package app.rentivo.features.bills

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CommunicationSendReadinessTest {
  @Test
  fun `sending readiness depends only on active send recipients and pdf rendering`() {
    assertFalse(
      communicationSendIsDisabled(
        isSending = false,
        hasSelectedRecipients = true,
        isRenderingPDF = false,
      )
    )
    assertTrue(
      communicationSendIsDisabled(
        isSending = true,
        hasSelectedRecipients = true,
        isRenderingPDF = false,
      )
    )
    assertTrue(
      communicationSendIsDisabled(
        isSending = false,
        hasSelectedRecipients = false,
        isRenderingPDF = false,
      )
    )
    assertTrue(
      communicationSendIsDisabled(
        isSending = false,
        hasSelectedRecipients = true,
        isRenderingPDF = true,
      )
    )
  }
}
