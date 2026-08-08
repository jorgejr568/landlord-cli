package app.rentivo.features.auth

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.rentivo.designsystem.BrandMark
import app.rentivo.designsystem.RentivoButton
import app.rentivo.designsystem.RentivoSpacing

/**
 * Placeholder for the signed-out screen; replaced by the ported `AuthenticationView`.
 *
 * The real screen drives `AppModel.signInWithWebAuthorization()`, so the button stays disabled here
 * rather than taking a shortcut the port would have to unpick.
 */
@Composable
fun AuthenticationView() {
  Column(
    modifier = Modifier.fillMaxSize().padding(RentivoSpacing.page),
    verticalArrangement = Arrangement.spacedBy(
      space = RentivoSpacing.large,
      alignment = Alignment.CenterVertically,
    ),
    horizontalAlignment = Alignment.CenterHorizontally,
  ) {
    BrandMark()
    RentivoButton(
      text = "Entrar",
      onClick = {},
      enabled = false,
      modifier = Modifier.widthIn(max = 320.dp),
    )
  }
}
