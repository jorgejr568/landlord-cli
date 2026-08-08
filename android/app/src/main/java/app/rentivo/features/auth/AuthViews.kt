package app.rentivo.features.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Error
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import app.rentivo.app.LocalAppModel
import app.rentivo.data.api.MobileWebAuthenticator
import app.rentivo.designsystem.BrandMark
import app.rentivo.designsystem.RentivoButton
import app.rentivo.designsystem.RentivoCard
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoSpacing
import app.rentivo.designsystem.RentivoTypography
import app.rentivo.designsystem.rentivoPage
import app.rentivo.domain.LocalizedError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/** The signed-out screen. Port of `ios/Rentivo/Features/Auth/AuthViews.swift`. */
@Composable
fun AuthenticationView() {
  Box(modifier = Modifier.fillMaxSize().background(RentivoColors.paper)) {
    LoginView()
  }
}

/**
 * The shared frame for the auth screens: brand mark, headline pair, and a single card of content,
 * centered inside a readable measure on wide screens.
 */
@Composable
private fun AuthScaffold(
  title: String,
  subtitle: String,
  content: @Composable () -> Unit,
) {
  Column(
    modifier = Modifier
      .rentivoPage()
      .verticalScroll(rememberScrollState()),
    horizontalAlignment = Alignment.CenterHorizontally,
  ) {
    Column(
      // The iOS `.frame(maxWidth: 560)` sits outside `.padding(page)`, so the cap covers the
      // padding too.
      modifier = Modifier
        .widthIn(max = 560.dp)
        .fillMaxWidth()
        .padding(RentivoSpacing.page),
      verticalArrangement = Arrangement.spacedBy(RentivoSpacing.page),
    ) {
      BrandMark(modifier = Modifier.padding(bottom = RentivoSpacing.small))
      Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.small)) {
        Text(
          text = title,
          style = RentivoTypography.display,
          color = RentivoColors.ink,
        )
        Text(
          text = subtitle,
          style = RentivoTypography.body,
          color = RentivoColors.secondaryInk,
        )
      }
      RentivoCard { content() }
    }
  }
}

/**
 * Sign-in. The credentials themselves are collected by the Rentivo web site, so the screen is a
 * single button that hands off to the browser flow and reports back whatever comes out of it.
 */
@Composable
fun LoginView() {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  var validationMessage by remember { mutableStateOf<String?>(null) }
  var isAuthenticating by remember { mutableStateOf(false) }

  fun submit() {
    if (isAuthenticating) return
    validationMessage = null
    isAuthenticating = true
    scope.launch {
      try {
        app.signInWithWebAuthorization()
      } catch (cancellation: CancellationException) {
        throw cancellation
      } catch (throwable: Throwable) {
        // Backing out of the browser sheet is a decision, not a failure: it leaves the screen as
        // the user found it.
        if (!MobileWebAuthenticator.isUserCancellation(throwable)) {
          validationMessage = ptBRDescription(throwable)
        }
      } finally {
        isAuthenticating = false
      }
    }
  }

  AuthScaffold(
    title = "Boas-vindas",
    subtitle = "Entre com sua conta Rentivo para acessar seus dados.",
  ) {
    Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.large)) {
      validationMessage?.let { message ->
        Row(
          horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny),
          verticalAlignment = Alignment.CenterVertically,
          modifier = Modifier.testTag("login.error"),
        ) {
          Icon(
            imageVector = Icons.Filled.Error,
            contentDescription = null,
            tint = RentivoColors.coral,
            modifier = Modifier.size(FootnoteIconSize),
          )
          Text(
            text = message,
            // The design system has no `footnote` token; `metadata` is its semibold small style.
            style = RentivoTypography.metadata,
            color = RentivoColors.coral,
          )
        }
      }
      RentivoButton(
        onClick = ::submit,
        enabled = !isAuthenticating,
        modifier = Modifier.testTag("login.submit"),
      ) {
        if (isAuthenticating) {
          CircularProgressIndicator(
            color = Color.White,
            strokeWidth = 2.dp,
            modifier = Modifier.size(FootnoteIconSize),
          )
          Spacer(modifier = Modifier.width(RentivoSpacing.small))
        }
        Text(
          text = "Entrar",
          style = RentivoTypography.cardTitle,
          color = Color.White,
        )
      }
      Text(
        text = "O login continua no site seguro do Rentivo para concluir a verificação de segurança.",
        style = RentivoTypography.caption,
        color = RentivoColors.secondaryInk,
      )
    }
  }
}

/** Everything carrying PT-BR copy states its own case; anything else gets the generic line. */
private fun ptBRDescription(error: Throwable): String =
  (error as? LocalizedError)?.errorDescription
    ?: "Não foi possível concluir o login. Tente novamente."

private val FootnoteIconSize = 18.dp
