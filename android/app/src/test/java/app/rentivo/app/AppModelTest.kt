package app.rentivo.app

import app.rentivo.data.AppDependencies
import app.rentivo.data.AuthRepository
import app.rentivo.data.DemoSettings
import app.rentivo.data.MockRentivoStore
import app.rentivo.data.mockDependencies
import app.rentivo.domain.DemoError
import app.rentivo.domain.PixConfiguration
import app.rentivo.domain.UserProfile
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableSharedFlow
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
    // takes the `completeSignOut()` shortcut and never flips `isSigningOut` in between.
    assertEquals(AppModel.Session.Anonymous, app.session)
    assertFalse(app.isSigningOut)
    assertEquals(AppTab.HOME, app.selectedTab)
    assertNull(app.notice)
  }

  @Test
  fun `demo web authorization takes the local sign-in shortcut`() = runTest {
    val authenticator = FakeWebAuthenticator()
    val app = demoModel(backgroundScope, authenticator = authenticator)

    app.signInWithWebAuthorization()

    assertTrue(app.isAuthenticated)
    assertEquals("Bem-vinda à demonstração do Rentivo.", app.notice?.message)
    assertEquals(0, authenticator.authorizeCount)
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
  fun `web authorization exchanges the code and connects the session`() = runTest {
    val auth = FakeAuthRepository()
    val authenticator = FakeWebAuthenticator(code = "one-time-code")
    val app = liveModel(backgroundScope, auth = auth, authenticator = authenticator)
    app.selectedTab = AppTab.ACCOUNT

    app.signInWithWebAuthorization()

    assertEquals("one-time-code", auth.exchangedCode)
    assertEquals(auth.exchanged, (app.session as AppModel.Session.Authenticated).profile)
    assertEquals(AppTab.HOME, app.selectedTab)
    assertEquals(
      AppNotice(AppNotice.Kind.SUCCESS, "Sessão conectada ao Rentivo."),
      app.notice,
    )
  }

  @Test
  fun `a cancelled browser authorization leaves the session alone`() = runTest {
    val authenticator = FakeWebAuthenticator(authorizeFailure = FakeCancellation())
    val app = liveModel(backgroundScope, authenticator = authenticator)
    app.restoreSessionIfNeeded()
    app.signOut()

    val thrown = runCatching { app.signInWithWebAuthorization() }.exceptionOrNull()

    // The screen decides whether to report it; the model must not swallow it or half-authenticate.
    assertTrue(thrown is FakeCancellation)
    assertEquals(AppModel.Session.Anonymous, app.session)
  }

  // MARK: - Live sign-out

  @Test
  fun `live sign out revokes the token, drops local state and closes the browser session`() =
    runTest {
      val auth = FakeAuthRepository()
      val authenticator = FakeWebAuthenticator()
      val app = liveModel(backgroundScope, auth = auth, authenticator = authenticator)
      app.restoreSessionIfNeeded()
      app.selectedTab = AppTab.BILLINGS

      app.signOut()

      assertEquals(1, auth.logoutCount)
      assertEquals(1, authenticator.logoutCount)
      assertEquals(AppModel.Session.Anonymous, app.session)
      assertEquals(AppTab.HOME, app.selectedTab)
      assertFalse(app.isSigningOut)
      assertNull(app.notice)
    }

  @Test
  fun `a failed browser logout still signs out but warns about the browser session`() = runTest {
    val auth = FakeAuthRepository()
    val authenticator = FakeWebAuthenticator(logoutFailure = DemoError.operationFailed)
    val app = liveModel(backgroundScope, auth = auth, authenticator = authenticator)
    app.restoreSessionIfNeeded()

    app.signOut()

    assertEquals(AppModel.Session.Anonymous, app.session)
    assertEquals(
      AppNotice(
        AppNotice.Kind.WARNING,
        "Você saiu do Rentivo, mas não foi possível encerrar a sessão do navegador.",
      ),
      app.notice,
    )
  }

  @Test
  fun `dismissing the logout browser tab is a silent, expected outcome`() = runTest {
    val authenticator = FakeWebAuthenticator(logoutFailure = FakeCancellation())
    val app = liveModel(backgroundScope, authenticator = authenticator)
    app.restoreSessionIfNeeded()

    app.signOut()

    assertEquals(AppModel.Session.Anonymous, app.session)
    assertNull(app.notice)
  }

  @Test
  fun `a second sign out while one is in flight is ignored`() = runTest {
    val auth = FakeAuthRepository()
    val app = liveModel(backgroundScope, auth = auth)
    app.restoreSessionIfNeeded()
    app.isSigningOut = true

    app.signOut()

    assertEquals(0, auth.logoutCount)
    assertTrue(app.isAuthenticated)
  }

  // MARK: - Account deletion

  @Test
  fun `deleting the account signs out and confirms the deletion`() = runTest {
    val auth = FakeAuthRepository()
    val app = liveModel(backgroundScope, auth = auth)
    app.restoreSessionIfNeeded()

    app.deleteAccount(password = "senha-correta")

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

    assertNull(auth.deletedPassword)
    assertTrue(app.isAuthenticated)
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
  authenticator: WebAuthenticating? = null,
): AppModel = AppModel(
  dependencies = mockDependencies(store),
  authenticator = authenticator,
  scope = scope,
)

private fun liveModel(
  scope: CoroutineScope,
  auth: FakeAuthRepository = FakeAuthRepository(),
  authenticator: WebAuthenticating = FakeWebAuthenticator(),
  sessionExpired: MutableSharedFlow<Unit>? = null,
): AppModel = AppModel(
  dependencies = liveDependencies(auth),
  authenticator = authenticator,
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
  private val deleteFailure: Throwable? = null,
  private val onLogout: suspend () -> Unit = {},
) : AuthRepository {

  val exchanged = UserProfile(id = 1, email = "ana@rentivo.com.br")
  var exchangedCode: String? = null
  var logoutCount = 0
  var deletedPassword: String? = null

  override val currentUser: UserProfile get() = profile

  override val usesLiveAPI: Boolean get() = true

  override suspend fun restoreSession(): UserProfile? {
    restoreFailure?.let { throw it }
    return restored
  }

  override suspend fun exchangeMobileAuthorization(code: String): UserProfile {
    exchangedCode = code
    return exchanged
  }

  override suspend fun logout() {
    logoutCount += 1
    onLogout()
  }

  override suspend fun deleteAccount(password: String) {
    deletedPassword = password
    deleteFailure?.let { throw it }
  }
}

private class FakeWebAuthenticator(
  private val code: String = "authorization-code",
  private val authorizeFailure: Throwable? = null,
  private val logoutFailure: Throwable? = null,
) : WebAuthenticating {

  var authorizeCount = 0
  var logoutCount = 0

  override suspend fun authorize(): String {
    authorizeCount += 1
    authorizeFailure?.let { throw it }
    return code
  }

  override suspend fun logout() {
    logoutCount += 1
    logoutFailure?.let { throw it }
  }

  override fun isUserCancellation(throwable: Throwable): Boolean = throwable is FakeCancellation
}

/** Stands in for `UserCancelledException`, which is bound to the Android authenticator. */
private class FakeCancellation : Exception("Autenticação cancelada.")
