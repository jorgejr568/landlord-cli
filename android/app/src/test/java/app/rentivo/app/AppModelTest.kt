package app.rentivo.app

import app.rentivo.data.AppDependencies
import app.rentivo.data.AuthRepository
import app.rentivo.data.DemoSettings
import app.rentivo.data.MockRentivoStore
import app.rentivo.data.mockDependencies
import app.rentivo.domain.DemoError
import app.rentivo.domain.MFAChallenge
import app.rentivo.domain.MFAMethod
import app.rentivo.domain.MobileLoginOutcome
import app.rentivo.domain.PasskeyAssertionPayload
import app.rentivo.domain.PasskeyRequestOptions
import app.rentivo.domain.PixConfiguration
import app.rentivo.domain.UserProfile
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.plus
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Mirrors `ios/RentivoTests/AppModelSessionFlowTests.swift`, `AppModelProfileTests.swift` and the
 * `AppModel` section of `SessionExpiryTests.swift`.
 *
 * The iOS suites drive the live paths through a stubbed `URLProtocol`; here a fake [AuthRepository]
 * plays the same role, which keeps every case pure JVM (no emulator, no Android classes).
 *
 * The app model is given `backgroundScope`, matching the production `viewModelScope` that outlives
 * every screen. Work it launches is therefore driven with `runCurrent()`, not `advanceUntilIdle()` —
 * the latter deliberately stops as soon as only background work is left, and would report every
 * session-ending flow as never having run.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class AppModelTest {

  // MARK: - Demo store

  @Test
  fun `demo model starts anonymous with the store's demo settings`() = runTest {
    val app = demoModel(backgroundScope)

    assertEquals(AppModel.Session.Anonymous, app.session)
    assertEquals(AppTab.HOME, app.selectedTab)
    assertEquals(DemoSettings.standard, app.demoSettings)
    assertFalse(app.usesLiveAPI)
    assertFalse(app.isAuthenticated)
  }

  @Test
  fun `sign in authenticates, selects home and shows the demo welcome notice`() = runTest {
    val app = demoModel(backgroundScope)
    app.selectedTab = AppTab.ACCOUNT

    app.signIn()

    val session = app.session as AppModel.Session.Authenticated
    assertEquals(app.currentUser.email, session.profile.email)
    assertTrue(app.isAuthenticated)
    assertEquals(AppTab.HOME, app.selectedTab)
    assertEquals("Bem-vinda à demonstração do Rentivo.", app.notice?.message)
    assertEquals(AppNotice.Kind.SUCCESS, app.notice?.kind)
  }

  @Test
  fun `demo sign out completes without ever toggling isSigningOut`() = runTest {
    val app = demoModel(backgroundScope)
    app.signIn()
    app.selectedTab = AppTab.BILLINGS

    app.signOut()

    // The mock store reports `usesLiveAPI == false` and has no token to revoke, so `signOut()`
    // takes the `completeSignOut()` shortcut synchronously — no coroutine, so nothing to advance —
    // and never flips `isSigningOut` in between.
    assertEquals(AppModel.Session.Anonymous, app.session)
    assertFalse(app.isSigningOut)
    assertEquals(AppTab.HOME, app.selectedTab)
    assertNull(app.notice)
  }

  @Test
  fun `demo native login authenticates immediately as the demo user`() = runTest {
    val app = demoModel(backgroundScope)

    val outcome = app.signIn(email = "ana@demo.com.br", password = "irrelevante")

    assertEquals(MobileLoginOutcome.Authenticated(app.currentUser), outcome)
    assertTrue(app.isAuthenticated)
    assertEquals("Sessão conectada ao Rentivo.", app.notice?.message)
  }

  @Test
  fun `demo account deletion only returns to the signed-out screen`() = runTest {
    val app = demoModel(backgroundScope)
    app.signIn()

    app.deleteAccount(password = "irrelevant")

    // Nothing was deleted, so the success notice must not appear.
    assertEquals(AppModel.Session.Anonymous, app.session)
    assertFalse(app.isDeletingAccount)
    assertNull(app.notice)
  }

  @Test
  fun `currentUser falls back to the store profile while signed out`() = runTest {
    val store = MockRentivoStore()
    val app = demoModel(backgroundScope, store = store)

    assertEquals(store.currentUser, app.currentUser)
  }

  @Test
  fun `restoreSessionIfNeeded is a no-op for the demo store, which never starts restoring`() =
    runTest {
      val app = demoModel(backgroundScope)

      app.restoreSessionIfNeeded()

      assertEquals(AppModel.Session.Anonymous, app.session)
    }

  // MARK: - Demo toggles

  @Test
  fun `the delay toggle skips dataRevision while empty and viewer mode bump it`() = runTest {
    val app = demoModel(backgroundScope)
    val initialRevision = app.dataRevision

    // Only the delay toggle is a "how content loads" setting, not a "what content loads" setting;
    // bumping `dataRevision` for it would force every visible screen to redundantly reload.
    app.setDelayEnabled(true)
    assertTrue(app.demoSettings.delayEnabled)
    assertEquals(initialRevision, app.dataRevision)

    app.setEmptyMode(true)
    assertTrue(app.demoSettings.emptyMode)
    assertEquals(initialRevision + 1, app.dataRevision)

    app.setViewerMode(true)
    assertTrue(app.demoSettings.viewerMode)
    assertEquals(initialRevision + 2, app.dataRevision)
  }

  @Test
  fun `resetDemo restores the default settings and bumps dataRevision`() = runTest {
    val app = demoModel(backgroundScope)
    app.setDelayEnabled(true)
    app.setEmptyMode(true)
    app.setViewerMode(true)
    val revisionBeforeReset = app.dataRevision

    app.resetDemo()

    assertEquals(DemoSettings.standard, app.demoSettings)
    assertEquals(revisionBeforeReset + 1, app.dataRevision)
  }

  @Test
  fun `failNextOperation is forwarded to the demo store without a reload`() = runTest {
    val store = MockRentivoStore()
    val app = demoModel(backgroundScope, store = store)
    val revision = app.dataRevision

    app.failNextOperation()

    assertEquals(revision, app.dataRevision)
    assertEquals(DemoError.operationFailed, runCatching { store.profile() }.exceptionOrNull())
  }

  // MARK: - Notices

  @Test
  fun `showNotice defaults to the success kind`() = runTest {
    val app = demoModel(backgroundScope)

    app.showNotice("Tudo certo.")
    assertEquals(AppNotice(AppNotice.Kind.SUCCESS, "Tudo certo."), app.notice)

    app.showNotice("Cuidado.", kind = AppNotice.Kind.WARNING)
    assertEquals(AppNotice(AppNotice.Kind.WARNING, "Cuidado."), app.notice)
  }

  // MARK: - Profile

  @Test
  fun `loadProfile refreshes the authenticated session profile`() = runTest {
    val app = demoModel(backgroundScope)
    app.signIn()

    val profile = app.loadProfile()

    assertEquals(profile, (app.session as AppModel.Session.Authenticated).profile)
  }

  @Test
  fun `loadProfile leaves an anonymous session untouched`() = runTest {
    val app = demoModel(backgroundScope)

    app.loadProfile()

    assertEquals(AppModel.Session.Anonymous, app.session)
  }

  @Test
  fun `updateProfilePIX stores the saved configuration on the session profile`() = runTest {
    val app = demoModel(backgroundScope)
    app.signIn()
    val pix = PixConfiguration(
      key = "jorge@example.com",
      merchantName = "JORGE JUNIOR",
      merchantCity = "SALVADOR",
    )

    val profile = app.updateProfilePIX(pix)

    assertEquals(pix, profile.pix)
    assertEquals(pix, (app.session as AppModel.Session.Authenticated).profile.pix)
  }

  // MARK: - Live session restore

  @Test
  fun `live dependencies start out restoring`() = runTest {
    val app = liveModel(backgroundScope)

    assertEquals(AppModel.Session.Restoring, app.session)
    assertTrue(app.usesLiveAPI)
  }

  @Test
  fun `restoreSessionIfNeeded authenticates from a stored credential`() = runTest {
    val auth = FakeAuthRepository()
    val app = liveModel(backgroundScope, auth = auth)

    app.restoreSessionIfNeeded()

    assertEquals(auth.profile, (app.session as AppModel.Session.Authenticated).profile)
    assertNull(app.notice)
  }

  @Test
  fun `restoreSessionIfNeeded falls back to anonymous when there is nothing stored`() = runTest {
    val app = liveModel(backgroundScope, auth = FakeAuthRepository(restored = null))

    app.restoreSessionIfNeeded()

    assertEquals(AppModel.Session.Anonymous, app.session)
    assertNull(app.notice)
  }

  @Test
  fun `a failed restore signs out and asks the user to sign in again`() = runTest {
    val auth = FakeAuthRepository(restoreFailure = DemoError.operationFailed)
    val app = liveModel(backgroundScope, auth = auth)

    app.restoreSessionIfNeeded()

    assertEquals(AppModel.Session.Anonymous, app.session)
    assertEquals(
      AppNotice(
        AppNotice.Kind.WARNING,
        "Não foi possível restaurar sua sessão. Entre novamente.",
      ),
      app.notice,
    )
  }

  // MARK: - Live sign-in

  @Test
  fun `native login connects the session`() = runTest {
    val auth = FakeAuthRepository()
    val app = liveModel(backgroundScope, auth = auth)
    app.selectedTab = AppTab.ACCOUNT

    val outcome = app.signIn(email = "  ana@rentivo.com.br  ", password = "senha")

    assertEquals("  ana@rentivo.com.br  ", auth.loginEmail)
    assertEquals(MobileLoginOutcome.Authenticated(auth.profile), outcome)
    assertEquals(auth.profile, (app.session as AppModel.Session.Authenticated).profile)
    assertEquals(AppTab.HOME, app.selectedTab)
    assertEquals(
      AppNotice(AppNotice.Kind.SUCCESS, "Sessão conectada ao Rentivo."),
      app.notice,
    )
  }

  @Test
  fun `a login that stops at MFA hands the challenge back without authenticating`() = runTest {
    val challenge = MFAChallenge(
      challengeId = "challenge-1",
      challengeToken = "token-1",
      methods = listOf(MFAMethod.TOTP, MFAMethod.PASSKEY),
    )
    val auth = FakeAuthRepository(loginOutcome = MobileLoginOutcome.MfaRequired(challenge))
    val app = liveModel(backgroundScope, auth = auth)
    app.restoreSessionIfNeeded()
    app.signOut()
    runCurrent()

    val outcome = app.signIn(email = "ana@rentivo.com.br", password = "senha")

    assertEquals(MobileLoginOutcome.MfaRequired(challenge), outcome)
    // The challenge is screen state; the model stays anonymous until a verify call completes it.
    assertEquals(AppModel.Session.Anonymous, app.session)
    assertNull(app.notice)
  }

  @Test
  fun `a rejected login surfaces the error and leaves the session alone`() = runTest {
    val auth = FakeAuthRepository(loginFailure = DemoError("Credenciais inválidas."))
    val app = liveModel(backgroundScope, auth = auth, sessionExpired = null)
    app.restoreSessionIfNeeded()
    app.signOut()
    runCurrent()

    val thrown = runCatching {
      app.signIn(email = "ana@rentivo.com.br", password = "errada")
    }.exceptionOrNull()

    // The screen decides whether to report it; the model must not swallow it or half-authenticate.
    assertEquals("Credenciais inválidas.", (thrown as DemoError).message)
    assertEquals(AppModel.Session.Anonymous, app.session)
  }

  @Test
  fun `completing a TOTP challenge connects the session`() = runTest {
    val challenge = MFAChallenge("c", "t", listOf(MFAMethod.TOTP))
    val auth = FakeAuthRepository()
    val app = liveModel(backgroundScope, auth = auth)

    app.completeTOTP(challenge = challenge, code = "123456")

    assertEquals(challenge to "123456", auth.verifiedTotp)
    assertEquals(auth.profile, (app.session as AppModel.Session.Authenticated).profile)
    assertEquals(AppTab.HOME, app.selectedTab)
    assertEquals("Sessão conectada ao Rentivo.", app.notice?.message)
  }

  @Test
  fun `completing a recovery-code challenge connects the session`() = runTest {
    val challenge = MFAChallenge("c", "t", listOf(MFAMethod.RECOVERY))
    val auth = FakeAuthRepository()
    val app = liveModel(backgroundScope, auth = auth)

    app.completeRecoveryCode(challenge = challenge, code = "AAAA-BBBB")

    assertEquals(challenge to "AAAA-BBBB", auth.verifiedRecovery)
    assertTrue(app.isAuthenticated)
  }

  @Test
  fun `native signup connects the session`() = runTest {
    val auth = FakeAuthRepository()
    val app = liveModel(backgroundScope, auth = auth)

    app.signUp(email = "  nova@rentivo.com.br ", password = "senha-forte")

    assertEquals("  nova@rentivo.com.br ", auth.signedUpEmail)
    assertEquals(auth.profile, (app.session as AppModel.Session.Authenticated).profile)
    assertEquals("Sessão conectada ao Rentivo.", app.notice?.message)
  }

  // MARK: - Live sign-out

  @Test
  fun `live sign out revokes the token and drops local state`() = runTest {
    val auth = FakeAuthRepository()
    val app = liveModel(backgroundScope, auth = auth)
    app.restoreSessionIfNeeded()
    app.selectedTab = AppTab.BILLINGS

    app.signOut()
    runCurrent()

    assertEquals(1, auth.logoutCount)
    assertEquals(AppModel.Session.Anonymous, app.session)
    assertEquals(AppTab.HOME, app.selectedTab)
    assertFalse(app.isSigningOut)
    assertNull(app.notice)
  }

  @Test
  fun `a second sign out while one is in flight is ignored`() = runTest {
    val auth = FakeAuthRepository()
    val app = liveModel(backgroundScope, auth = auth)
    app.restoreSessionIfNeeded()
    app.isSigningOut = true

    app.signOut()
    runCurrent()

    // The guard is checked before anything is launched, so the second call starts no coroutine at
    // all rather than one that quietly does nothing.
    assertEquals(0, auth.logoutCount)
    assertTrue(app.isAuthenticated)
  }

  @Test
  fun `sign out finishes even when the calling screen's scope is cancelled`() = runTest {
    // Regression test: `signOut()` used to run on the account screen's `rememberCoroutineScope()`,
    // which `completeSignOut()` itself destroys by switching the session to anonymous and taking
    // that screen out of composition. Whether the trailing token revocation survived was then a
    // matter of frame timing, leaving the server honoring the old token at random.
    val resumeLogout = CompletableDeferred<Unit>()
    val auth = FakeAuthRepository(onLogout = { resumeLogout.await() })
    val app = liveModel(backgroundScope, auth = auth)
    app.restoreSessionIfNeeded()

    val screenScope = backgroundScope + Job()
    screenScope.launch { app.signOut() }
    runCurrent()

    // The screen goes away mid-flow, exactly as it does in the app.
    screenScope.cancel()
    resumeLogout.complete(Unit)
    runCurrent()

    assertEquals(1, auth.logoutCount)
    assertEquals(AppModel.Session.Anonymous, app.session)
    assertFalse(app.isSigningOut)
    assertNull(app.notice)
  }

  // MARK: - Account deletion

  @Test
  fun `deleting the account signs out and confirms the deletion`() = runTest {
    val auth = FakeAuthRepository()
    val app = liveModel(backgroundScope, auth = auth)
    app.restoreSessionIfNeeded()

    app.deleteAccount(password = "senha-correta")
    runCurrent()

    assertEquals("senha-correta", auth.deletedPassword)
    assertEquals(AppModel.Session.Anonymous, app.session)
    assertFalse(app.isDeletingAccount)
    assertEquals(AppNotice(AppNotice.Kind.SUCCESS, "Sua conta foi excluída."), app.notice)
  }

  @Test
  fun `a rejected deletion keeps the session and surfaces the server message`() = runTest {
    val auth = FakeAuthRepository(deleteFailure = DemoError("Senha incorreta."))
    val app = liveModel(backgroundScope, auth = auth)
    app.restoreSessionIfNeeded()

    app.deleteAccount(password = "senha-errada")
    runCurrent()

    assertTrue(app.isAuthenticated)
    assertFalse(app.isDeletingAccount)
    assertEquals(AppNotice(AppNotice.Kind.WARNING, "Senha incorreta."), app.notice)
  }

  @Test
  fun `a second deletion while one is in flight is ignored`() = runTest {
    val auth = FakeAuthRepository()
    val app = liveModel(backgroundScope, auth = auth)
    app.restoreSessionIfNeeded()
    app.isDeletingAccount = true

    app.deleteAccount(password = "senha-correta")
    runCurrent()

    assertNull(auth.deletedPassword)
    assertTrue(app.isAuthenticated)
  }

  @Test
  fun `account deletion completes even when the calling screen's scope is cancelled`() = runTest {
    // The alert that starts a deletion is dismissed the moment the session goes anonymous, so the
    // work has to belong to the app model rather than to that screen — same reasoning as sign-out.
    val resumeDelete = CompletableDeferred<Unit>()
    val auth = FakeAuthRepository(onDeleteAccount = { resumeDelete.await() })
    val app = liveModel(backgroundScope, auth = auth)
    app.restoreSessionIfNeeded()

    val screenScope = backgroundScope + Job()
    screenScope.launch { app.deleteAccount(password = "senha-correta") }
    runCurrent()

    screenScope.cancel()
    resumeDelete.complete(Unit)
    runCurrent()

    assertEquals(AppModel.Session.Anonymous, app.session)
    assertFalse(app.isDeletingAccount)
    assertEquals(AppNotice(AppNotice.Kind.SUCCESS, "Sua conta foi excluída."), app.notice)
  }

  // MARK: - Session expiry

  @Test
  fun `an expired session signs out and explains why in PT-BR`() = runTest {
    val expired = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val app = liveModel(backgroundScope, sessionExpired = expired)
    app.restoreSessionIfNeeded()
    app.selectedTab = AppTab.ACCOUNT
    runCurrent()

    expired.emit(Unit)
    runCurrent()

    assertEquals(AppModel.Session.Anonymous, app.session)
    assertEquals(AppTab.HOME, app.selectedTab)
    assertEquals(
      AppNotice(AppNotice.Kind.WARNING, "Sua sessão expirou. Entre novamente para continuar."),
      app.notice,
    )
  }

  @Test
  fun `an expiry arriving while signed out is ignored`() = runTest {
    val expired = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val app = liveModel(backgroundScope, auth = FakeAuthRepository(restored = null), sessionExpired = expired)
    app.restoreSessionIfNeeded()
    runCurrent()

    expired.emit(Unit)
    runCurrent()

    assertEquals(AppModel.Session.Anonymous, app.session)
    assertNull(app.notice)
  }

  @Test
  fun `an expiry raced by a deliberate sign out never flashes the expiry notice`() = runTest {
    // Regression test: `signOut()`'s own logout POST can itself 401 (the token it is revoking is,
    // after all, about to become invalid), which used to race the expiry signal against the
    // deliberate sign-out and briefly show "Sua sessão expirou". `isSigningOut` must make the
    // handler a no-op while the sign-out is still in flight.
    val expired = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val auth = FakeAuthRepository(onLogout = {
      expired.emit(Unit)
      // Yield so the collector runs while the sign-out is mid-flight: still authenticated, with
      // `isSigningOut` set.
      yield()
    })
    val app = liveModel(backgroundScope, auth = auth, sessionExpired = expired)
    app.restoreSessionIfNeeded()
    runCurrent()

    app.signOut()
    runCurrent()

    assertEquals(AppModel.Session.Anonymous, app.session)
    assertNull(app.notice)
  }

  @Test
  fun `an expiry arriving while isSigningOut is set leaves the session alone`() = runTest {
    val expired = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val app = liveModel(backgroundScope, sessionExpired = expired)
    app.restoreSessionIfNeeded()
    runCurrent()
    app.isSigningOut = true

    expired.emit(Unit)
    runCurrent()

    assertTrue(app.isAuthenticated)
    assertNull(app.notice)
  }

  @Test
  fun `demo dependencies never subscribe to session expiry`() = runTest {
    val expired = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val app = AppModel(
      dependencies = mockDependencies(),
      sessionExpired = expired,
      scope = backgroundScope,
    )
    app.signIn()
    runCurrent()

    expired.emit(Unit)
    runCurrent()

    assertEquals(0, expired.subscriptionCount.value)
    assertTrue(app.isAuthenticated)
  }
}

// MARK: - Fakes

private fun demoModel(
  scope: CoroutineScope,
  store: MockRentivoStore = MockRentivoStore(),
): AppModel = AppModel(
  dependencies = mockDependencies(store),
  scope = scope,
)

private fun liveModel(
  scope: CoroutineScope,
  auth: FakeAuthRepository = FakeAuthRepository(),
  sessionExpired: MutableSharedFlow<Unit>? = null,
): AppModel = AppModel(
  dependencies = liveDependencies(auth),
  sessionExpired = sessionExpired,
  scope = scope,
)

/** The demo store wired behind a live-reporting auth repository, as `liveDependencies()` will be. */
private fun liveDependencies(auth: AuthRepository): AppDependencies =
  mockDependencies().copy(auth = auth)

private class FakeAuthRepository(
  val profile: UserProfile = UserProfile(id = 1, email = "ana@example.com"),
  private val restored: UserProfile? = profile,
  private val restoreFailure: Throwable? = null,
  private val loginOutcome: MobileLoginOutcome = MobileLoginOutcome.Authenticated(profile),
  private val loginFailure: Throwable? = null,
  private val deleteFailure: Throwable? = null,
  private val onLogout: suspend () -> Unit = {},
  private val onDeleteAccount: suspend () -> Unit = {},
) : AuthRepository {

  var loginEmail: String? = null
  var loginPassword: String? = null
  var signedUpEmail: String? = null
  var verifiedTotp: Pair<MFAChallenge, String>? = null
  var verifiedRecovery: Pair<MFAChallenge, String>? = null
  var logoutCount = 0
  var deletedPassword: String? = null

  override val currentUser: UserProfile get() = profile

  override val usesLiveAPI: Boolean get() = true

  override suspend fun restoreSession(): UserProfile? {
    restoreFailure?.let { throw it }
    return restored
  }

  override suspend fun mobileLogin(email: String, password: String): MobileLoginOutcome {
    loginEmail = email
    loginPassword = password
    loginFailure?.let { throw it }
    return loginOutcome
  }

  override suspend fun mobileSignup(email: String, password: String): UserProfile {
    signedUpEmail = email
    return profile
  }

  override suspend fun verifyTotp(challenge: MFAChallenge, code: String): UserProfile {
    verifiedTotp = challenge to code
    return profile
  }

  override suspend fun verifyRecoveryCode(challenge: MFAChallenge, code: String): UserProfile {
    verifiedRecovery = challenge to code
    return profile
  }

  override suspend fun beginPasskeyAssertion(challenge: MFAChallenge): PasskeyRequestOptions =
    PasskeyRequestOptions(ByteArray(0), "", emptyList(), "preferred", 60_000)

  override suspend fun completePasskeyAssertion(
    challenge: MFAChallenge,
    credential: PasskeyAssertionPayload,
  ): UserProfile = profile

  override suspend fun logout() {
    logoutCount += 1
    onLogout()
  }

  override suspend fun deleteAccount(password: String) {
    deletedPassword = password
    onDeleteAccount()
    deleteFailure?.let { throw it }
  }
}
