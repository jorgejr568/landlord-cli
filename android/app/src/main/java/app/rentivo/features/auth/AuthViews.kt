package app.rentivo.features.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Error
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import app.rentivo.app.LocalAppModel
import app.rentivo.data.api.PasskeyAuthenticator
import app.rentivo.designsystem.BrandMark
import app.rentivo.designsystem.RentivoButton
import app.rentivo.designsystem.RentivoCard
import app.rentivo.designsystem.RentivoColors
import app.rentivo.designsystem.RentivoSpacing
import app.rentivo.designsystem.RentivoTypography
import app.rentivo.designsystem.rentivoPage
import app.rentivo.domain.LocalizedError
import app.rentivo.domain.MFAChallenge
import app.rentivo.domain.MFAMethod
import app.rentivo.domain.MobileLoginOutcome
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
 * The sign-in flow: credentials, account creation, and the second factor a login can stop at.
 *
 * The pending [MFAChallenge] and the typed credentials live here rather than inside the child forms
 * because they are screen state that has to outlive the transition between them: showing the
 * challenge takes the credential form out of composition, so held one level up "Voltar" returns to
 * the form the user actually filled in. The password rides alongside the e-mail on purpose — the
 * MFA step is the same sign-in attempt — and the whole thing is discarded when the login lands.
 */
@Composable
fun LoginView() {
  var challenge by remember { mutableStateOf<MFAChallenge?>(null) }
  var isCreatingAccount by rememberSaveable { mutableStateOf(false) }
  var email by rememberSaveable { mutableStateOf("") }
  var password by remember { mutableStateOf("") }

  val currentChallenge = challenge
  when {
    currentChallenge != null -> MFAChallengeForm(
      challenge = currentChallenge,
      onCancel = { challenge = null },
    )

    isCreatingAccount -> SignUpForm(onSignIn = { isCreatingAccount = false })

    else -> SignInForm(
      email = email,
      onEmailChange = { email = it },
      password = password,
      onPasswordChange = { password = it },
      onCreateAccount = { isCreatingAccount = true },
      onChallenge = { challenge = it },
    )
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
      // The signed-out screen is not hosted by the tab shell's `Scaffold`, so nothing above it
      // insets the content: without these the wordmark is drawn straight through the status-bar
      // clock. The padding sits outside `verticalScroll` so the bars stay paper-colored and the
      // content scrolls between them rather than under them.
      .statusBarsPadding()
      .navigationBarsPadding()
      .verticalScroll(rememberScrollState()),
    horizontalAlignment = Alignment.CenterHorizontally,
  ) {
    Column(
      modifier = Modifier
        .widthIn(max = 560.dp)
        .fillMaxWidth()
        .padding(RentivoSpacing.page)
        .padding(top = AuthTopSpacing),
      verticalArrangement = Arrangement.spacedBy(RentivoSpacing.page),
    ) {
      BrandMark(modifier = Modifier.padding(bottom = RentivoSpacing.small))
      Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.small)) {
        Text(text = title, style = RentivoTypography.display, color = RentivoColors.ink)
        Text(text = subtitle, style = RentivoTypography.body, color = RentivoColors.secondaryInk)
      }
      RentivoCard { content() }
    }
  }
}

/** A labelled credential field, drawn with the ink outline the cards and buttons use. */
@Composable
private fun AuthField(
  label: String,
  value: String,
  onValueChange: (String) -> Unit,
  placeholder: String,
  modifier: Modifier = Modifier,
  keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
  keyboardActions: KeyboardActions = KeyboardActions.Default,
  visualTransformation: VisualTransformation = VisualTransformation.None,
) {
  Column(
    verticalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny),
    modifier = modifier,
  ) {
    Text(text = label, style = RentivoTypography.metadata, color = RentivoColors.secondaryInk)
    OutlinedTextField(
      value = value,
      onValueChange = onValueChange,
      modifier = Modifier.fillMaxWidth(),
      singleLine = true,
      placeholder = {
        Text(text = placeholder, style = RentivoTypography.body, color = RentivoColors.secondaryInk)
      },
      textStyle = RentivoTypography.body,
      keyboardOptions = keyboardOptions,
      keyboardActions = keyboardActions,
      visualTransformation = visualTransformation,
    )
  }
}

/** An inline text action ("Criar conta", "Usar código de recuperação") that reads as a link. */
@Composable
private fun AuthLinkButton(title: String, onClick: () -> Unit, enabled: Boolean = true) {
  TextButton(onClick = onClick, enabled = enabled) {
    Text(
      text = title,
      style = RentivoTypography.metadata,
      color = if (enabled) RentivoColors.blue else RentivoColors.secondaryInk,
    )
  }
}

@Composable
private fun AuthErrorLabel(message: String, modifier: Modifier = Modifier) {
  Row(
    horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny),
    verticalAlignment = Alignment.CenterVertically,
    modifier = modifier,
  ) {
    Icon(
      imageVector = Icons.Filled.Error,
      contentDescription = null,
      tint = RentivoColors.coral,
      modifier = Modifier.size(FootnoteIconSize),
    )
    Text(text = message, style = RentivoTypography.metadata, color = RentivoColors.coral)
  }
}

@Composable
private fun SubmitButton(
  text: String,
  onClick: () -> Unit,
  enabled: Boolean,
  isBusy: Boolean,
  modifier: Modifier = Modifier,
  color: Color = RentivoColors.emerald,
) {
  RentivoButton(onClick = onClick, enabled = enabled, color = color, modifier = modifier) {
    if (isBusy) {
      CircularProgressIndicator(
        color = Color.White,
        strokeWidth = 2.dp,
        modifier = Modifier.size(FootnoteIconSize),
      )
      Spacer(modifier = Modifier.width(RentivoSpacing.small))
    }
    Text(text = text, style = RentivoTypography.cardTitle, color = Color.White)
  }
}

@Composable
private fun SignInForm(
  email: String,
  onEmailChange: (String) -> Unit,
  password: String,
  onPasswordChange: (String) -> Unit,
  onCreateAccount: () -> Unit,
  onChallenge: (MFAChallenge) -> Unit,
) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  var validationMessage by remember { mutableStateOf<String?>(null) }
  var isAuthenticating by remember { mutableStateOf(false) }

  val canSubmit = !isAuthenticating && email.trim().isNotEmpty() && password.isNotEmpty()

  fun submit() {
    if (!canSubmit) return
    validationMessage = null
    isAuthenticating = true
    scope.launch {
      try {
        val outcome = app.signIn(email = email.trim(), password = password)
        if (outcome is MobileLoginOutcome.MfaRequired) onChallenge(outcome.challenge)
      } catch (cancellation: CancellationException) {
        throw cancellation
      } catch (throwable: Throwable) {
        validationMessage = ptBRDescription(throwable)
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
      AuthField(
        label = "E-MAIL",
        value = email,
        onValueChange = onEmailChange,
        placeholder = "voce@exemplo.com.br",
        keyboardOptions = KeyboardOptions(
          keyboardType = KeyboardType.Email,
          imeAction = ImeAction.Next,
        ),
        modifier = Modifier.testTag("login.email"),
      )
      AuthField(
        label = "SENHA",
        value = password,
        onValueChange = onPasswordChange,
        placeholder = "Sua senha",
        keyboardOptions = KeyboardOptions(
          keyboardType = KeyboardType.Password,
          imeAction = ImeAction.Go,
        ),
        keyboardActions = KeyboardActions(onGo = { submit() }),
        visualTransformation = PasswordVisualTransformation(),
        modifier = Modifier.testTag("login.password"),
      )
      validationMessage?.let { AuthErrorLabel(it, modifier = Modifier.testTag("login.error")) }
      SubmitButton(
        text = "Entrar",
        onClick = ::submit,
        enabled = canSubmit,
        isBusy = isAuthenticating,
        modifier = Modifier.testTag("login.submit"),
      )
      Row(
        horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        Text(
          text = "Ainda não tem uma conta?",
          style = RentivoTypography.caption,
          color = RentivoColors.secondaryInk,
        )
        AuthLinkButton(title = "Criar conta", onClick = onCreateAccount)
      }
    }
  }
}

@Composable
private fun SignUpForm(onSignIn: () -> Unit) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  var email by rememberSaveable { mutableStateOf("") }
  var password by remember { mutableStateOf("") }
  var confirmPassword by remember { mutableStateOf("") }
  var validationMessage by remember { mutableStateOf<String?>(null) }
  var isAuthenticating by remember { mutableStateOf(false) }

  val canSubmit = !isAuthenticating &&
    email.trim().isNotEmpty() && password.isNotEmpty() && confirmPassword.isNotEmpty()

  fun submit() {
    if (!canSubmit) return
    // The API takes only e-mail and password; the confirmation exists to catch a mistyped password
    // here, before an account is created with it.
    if (password != confirmPassword) {
      validationMessage = "As senhas não coincidem."
      return
    }
    validationMessage = null
    isAuthenticating = true
    scope.launch {
      try {
        app.signUp(email = email.trim(), password = password)
      } catch (cancellation: CancellationException) {
        throw cancellation
      } catch (throwable: Throwable) {
        validationMessage = ptBRDescription(throwable)
      } finally {
        isAuthenticating = false
      }
    }
  }

  AuthScaffold(
    title = "Criar conta",
    subtitle = "Crie sua conta Rentivo para organizar as cobranças dos seus imóveis.",
  ) {
    Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.large)) {
      AuthField(
        label = "E-MAIL",
        value = email,
        onValueChange = { email = it },
        placeholder = "voce@exemplo.com.br",
        keyboardOptions = KeyboardOptions(
          keyboardType = KeyboardType.Email,
          imeAction = ImeAction.Next,
        ),
        modifier = Modifier.testTag("signup.email"),
      )
      AuthField(
        label = "SENHA",
        value = password,
        onValueChange = { password = it },
        placeholder = "Crie uma senha",
        keyboardOptions = KeyboardOptions(
          keyboardType = KeyboardType.Password,
          imeAction = ImeAction.Next,
        ),
        visualTransformation = PasswordVisualTransformation(),
        modifier = Modifier.testTag("signup.password"),
      )
      AuthField(
        label = "CONFIRMAR SENHA",
        value = confirmPassword,
        onValueChange = { confirmPassword = it },
        placeholder = "Repita a senha",
        keyboardOptions = KeyboardOptions(
          keyboardType = KeyboardType.Password,
          imeAction = ImeAction.Go,
        ),
        keyboardActions = KeyboardActions(onGo = { submit() }),
        visualTransformation = PasswordVisualTransformation(),
        modifier = Modifier.testTag("signup.confirm"),
      )
      validationMessage?.let { AuthErrorLabel(it, modifier = Modifier.testTag("signup.error")) }
      SubmitButton(
        text = "Criar Conta",
        onClick = ::submit,
        enabled = canSubmit,
        isBusy = isAuthenticating,
        modifier = Modifier.testTag("signup.submit"),
      )
      Row(
        horizontalArrangement = Arrangement.spacedBy(RentivoSpacing.tiny),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        Text(
          text = "Já tem uma conta?",
          style = RentivoTypography.caption,
          color = RentivoColors.secondaryInk,
        )
        AuthLinkButton(title = "Entrar", onClick = onSignIn)
      }
    }
  }
}

/**
 * The second factor a login stopped at. Which factors appear is decided by the challenge: the
 * server lists exactly what it will accept, and a factor the app cannot present (or one this build
 * does not know) is simply not offered.
 */
private enum class CodeKind(val label: String, val placeholder: String) {
  TOTP("CÓDIGO DO APLICATIVO AUTENTICADOR", "000000"),
  RECOVERY("CÓDIGO DE RECUPERAÇÃO", "XXXX-XXXX"),
}

@Composable
private fun MFAChallengeForm(challenge: MFAChallenge, onCancel: () -> Unit) {
  val app = LocalAppModel.current
  val scope = rememberCoroutineScope()
  val context = LocalContext.current
  val passkeyAuthenticator = remember { PasskeyAuthenticator() }

  val offersPasskey = MFAMethod.PASSKEY in challenge.methods
  val offersTOTP = MFAMethod.TOTP in challenge.methods
  val offersRecovery = MFAMethod.RECOVERY in challenge.methods
  val offersCode = offersTOTP || offersRecovery

  var code by remember { mutableStateOf("") }
  // The authenticator app is the everyday factor; recovery codes are the fallback the user asks
  // for, so the form only starts there when TOTP is not on offer at all.
  var codeKind by remember { mutableStateOf(if (offersTOTP) CodeKind.TOTP else CodeKind.RECOVERY) }
  var validationMessage by remember { mutableStateOf<String?>(null) }
  var isAuthenticating by remember { mutableStateOf(false) }

  val canSubmitCode = !isAuthenticating && code.trim().isNotEmpty()

  fun verify(operation: suspend () -> Unit) {
    validationMessage = null
    isAuthenticating = true
    scope.launch {
      try {
        operation()
      } catch (cancellation: CancellationException) {
        throw cancellation
      } catch (throwable: Throwable) {
        code = ""
        validationMessage = ptBRDescription(throwable)
      } finally {
        isAuthenticating = false
      }
    }
  }

  fun submitCode() {
    if (!canSubmitCode) return
    val submitted = code.trim()
    verify {
      when (codeKind) {
        CodeKind.TOTP -> app.completeTOTP(challenge = challenge, code = submitted)
        CodeKind.RECOVERY -> app.completeRecoveryCode(challenge = challenge, code = submitted)
      }
    }
  }

  fun submitPasskey() {
    if (isAuthenticating) return
    verify {
      val options = app.dependencies.auth.beginPasskeyAssertion(challenge = challenge)
      val payload = try {
        passkeyAuthenticator.assert(context = context, options = options)
      } catch (throwable: Throwable) {
        // Closing the system sheet is a choice, not a failure — the challenge stays on screen with
        // its other factors. A device that cannot present a passkey degrades to a soft message.
        if (PasskeyAuthenticator.isUserCancellation(throwable)) return@verify
        if (PasskeyAuthenticator.isUnavailable(throwable)) {
          throw PasskeyUnavailable()
        }
        throw throwable
      }
      app.completePasskey(challenge = challenge, credential = payload)
    }
  }

  AuthScaffold(
    title = "Verificação em duas etapas",
    subtitle = "Confirme que é você para concluir a entrada.",
  ) {
    Column(verticalArrangement = Arrangement.spacedBy(RentivoSpacing.large)) {
      if (offersPasskey) {
        SubmitButton(
          text = "Usar chave de acesso",
          onClick = ::submitPasskey,
          enabled = !isAuthenticating,
          isBusy = isAuthenticating,
          color = RentivoColors.blue,
          modifier = Modifier.testTag("login.mfa.passkey"),
        )
      }
      if (offersCode) {
        AuthField(
          label = codeKind.label,
          value = code,
          onValueChange = { code = it },
          placeholder = codeKind.placeholder,
          keyboardOptions = KeyboardOptions(
            keyboardType = if (codeKind == CodeKind.TOTP) KeyboardType.NumberPassword
            else KeyboardType.Ascii,
            capitalization = KeyboardCapitalization.Characters,
            imeAction = ImeAction.Go,
          ),
          keyboardActions = KeyboardActions(onGo = { submitCode() }),
          modifier = Modifier.testTag("login.mfa.code"),
        )
      }
      validationMessage?.let { AuthErrorLabel(it, modifier = Modifier.testTag("login.mfa.error")) }
      if (offersCode) {
        SubmitButton(
          text = "Confirmar",
          onClick = ::submitCode,
          enabled = canSubmitCode,
          isBusy = isAuthenticating,
          modifier = Modifier.testTag("login.mfa.submit"),
        )
      }
      if (offersRecovery && offersTOTP) {
        AuthLinkButton(
          title = if (codeKind == CodeKind.TOTP) "Usar código de recuperação"
          else "Usar código do aplicativo autenticador",
          onClick = {
            codeKind = if (codeKind == CodeKind.TOTP) CodeKind.RECOVERY else CodeKind.TOTP
            code = ""
            validationMessage = null
          },
        )
      }
      if (!offersCode && !offersPasskey) {
        Text(
          text = "Nenhuma verificação disponível para este dispositivo.",
          style = RentivoTypography.caption,
          color = RentivoColors.secondaryInk,
        )
      }
      AuthLinkButton(title = "Voltar", onClick = onCancel, enabled = !isAuthenticating)
    }
  }
}

/**
 * The server already answers in PT-BR (`detail` on the problem document), so any [LocalizedError]'s
 * message is preferred over anything invented here; everything else falls back to one generic
 * sentence rather than leaking a system error string in English.
 */
private fun ptBRDescription(error: Throwable): String =
  (error as? LocalizedError)?.errorDescription
    ?: "Não foi possível concluir o login. Tente novamente."

/** Shown when the Credential Manager has no passkey to offer on this device. */
private class PasskeyUnavailable :
  Exception("Passkey indisponível."), LocalizedError {
  override val errorDescription: String
    get() = "Nenhuma chave de acesso disponível neste dispositivo. Use outro método."
}

private val FootnoteIconSize = 18.dp

/**
 * Extra breathing room above the wordmark, on top of the status-bar inset and the page padding, so
 * the card's top edge lands roughly a quarter of the way down the screen as it does on iOS.
 */
private val AuthTopSpacing = 32.dp
