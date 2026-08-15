package app.rentivo.data.api

import app.rentivo.domain.OrganizationDraft
import app.rentivo.domain.OrganizationID
import app.rentivo.domain.OrganizationRole
import app.rentivo.domain.PixConfiguration
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

private const val FULL_ORGANIZATION_CAPABILITIES =
  """{"can_manage":true,"can_invite":true,"can_create_billing":true,""" +
    """"can_view_billing_stats":true}"""

class APIRentivoStoreOrganizationTest {

  private val server = MockWebServer()

  @Before
  fun start() {
    server.start()
  }

  @After
  fun stop() {
    server.shutdown()
  }

  private suspend fun authenticatedStore(): APIRentivoStore {
    val store = APIRentivoStore(liveClient(server))
    assertNotNull(store.restoreSession())
    return store
  }

  private fun organizationRoutes(): RouteDispatcher = server.routeWithSession { call ->
    when (call.route) {
      "GET /api/v1/organizations" -> jsonResponse(
        """{"items":[{"uuid":"organization-1","name":"Horizonte","enforce_mfa":false,""" +
          """"current_role":"admin","capabilities":$FULL_ORGANIZATION_CAPABILITIES}]}"""
      )

      "GET /api/v1/organizations/organization-1" -> jsonResponse(
        """{"uuid":"organization-1","name":"Horizonte","enforce_mfa":false,""" +
          """"current_role":"admin","capabilities":$FULL_ORGANIZATION_CAPABILITIES,""" +
          """"settings":null,"members":[{"user_id":7,"email":"ana@rentivo.com.br",""" +
          """"role":"admin"},{"user_id":11,"email":"bruno@rentivo.com.br",""" +
          """"role":"teleporter"}]}"""
      )

      "POST /api/v1/organizations/organization-1/invites" -> jsonResponse(
        """{"uuid":"invite-1","invited_email":"bruno@rentivo.com.br","role":"viewer",""" +
          """"status":"pending"}"""
      )

      "POST /api/v1/organizations" -> jsonResponse(
        """{"uuid":"organization-2","name":"Nova Org","enforce_mfa":false,""" +
          """"current_role":"admin","capabilities":$FULL_ORGANIZATION_CAPABILITIES}"""
      )

      "PATCH /api/v1/organizations/organization-2" -> jsonResponse(
        """{"uuid":"organization-2","name":"Nova Org","enforce_mfa":false,""" +
          """"current_role":"admin","capabilities":$FULL_ORGANIZATION_CAPABILITIES,""" +
          """"settings":{"pix_key":"chave-pix","pix_merchant_name":"Nova Org",""" +
          """"pix_merchant_city":"Sao Paulo"},"members":[{"user_id":7,""" +
          """"email":"ana@rentivo.com.br","role":"admin"}]}"""
      )

      else -> unexpected(call)
    }
  }

  @Test
  fun `the organization list hydrates members for the card count`() = runTest {
    organizationRoutes()
    val store = authenticatedStore()

    val organization = store.listOrganizations().first()

    assertEquals(listOf(7, 11), organization.members.map { it.userID })
    // An unknown role falls back to the least privileged one rather than failing the decode.
    assertEquals(OrganizationRole.VIEWER, organization.members[1].role)
    assertEquals(OrganizationRole.ADMIN, organization.currentUserRole)
    assertNull(organization.pix)
  }

  @Test
  fun `inviting a member uses the real organization name instead of a placeholder`() = runTest {
    organizationRoutes()
    val store = authenticatedStore()

    val invitation = store.inviteMember(
      organizationID = OrganizationID(rawValue = "organization-1"),
      email = "bruno@rentivo.com.br",
      role = OrganizationRole.VIEWER,
    )

    assertEquals("Horizonte", invitation.organizationName)
    assertEquals("bruno@rentivo.com.br", invitation.email)
    assertEquals(OrganizationRole.VIEWER, invitation.role)
  }

  @Test
  fun `a failed name lookup still returns the invitation the server already created`() = runTest {
    server.routeWithSession { call ->
      when (call.route) {
        "POST /api/v1/organizations/organization-1/invites" -> jsonResponse(
          """{"uuid":"invite-1","invited_email":"bruno@rentivo.com.br","role":"viewer",""" +
            """"status":"pending"}"""
        )
        // The best-effort enrichment lookup fails.
        else -> jsonResponse("""{"detail":"Indisponível."}""", code = 500)
      }
    }
    val store = authenticatedStore()

    val invitation = store.inviteMember(
      organizationID = OrganizationID(rawValue = "organization-1"),
      email = "bruno@rentivo.com.br",
      role = OrganizationRole.VIEWER,
    )

    assertEquals("Organização", invitation.organizationName)
    assertEquals("invite-1", invitation.id.rawValue)
  }

  @Test
  fun `creating an organization follows up with a patch when the draft includes pix`() = runTest {
    // Regression test: OrganizationCreateRequest only accepts `name`, so PIX collected on the
    // creation form used to be silently dropped.
    val dispatcher = organizationRoutes()
    val store = authenticatedStore()

    val organization = store.createOrganization(
      OrganizationDraft(
        name = "Nova Org",
        pix = PixConfiguration(
          key = "chave-pix",
          merchantName = "Nova Org",
          merchantCity = "Sao Paulo",
        ),
      )
    )

    assertEquals(OrganizationID(rawValue = "organization-2"), organization.id)
    assertEquals(
      PixConfiguration(key = "chave-pix", merchantName = "Nova Org", merchantCity = "Sao Paulo"),
      organization.pix,
    )
    assertEquals("""{"name":"Nova Org"}""", dispatcher.bodyOf("POST /api/v1/organizations"))
  }

  @Test
  fun `creating an organization without pix skips the follow-up patch entirely`() = runTest {
    val dispatcher = organizationRoutes()
    val store = authenticatedStore()

    store.createOrganization(OrganizationDraft(name = "Nova Org", pix = null))

    assertEquals(
      listOf("GET /api/v1/auth/session", "POST /api/v1/organizations"),
      dispatcher.routes,
    )
  }

  @Test
  fun `a failing pix patch still returns the organization that was created`() = runTest {
    // Regression test: the org already exists on the server once the POST succeeds, so a failing
    // follow-up PATCH must not throw — throwing used to surface as a failure to the caller, who
    // would retry `createOrganization` and create a duplicate organization.
    server.routeWithSession { call ->
      when (call.route) {
        "POST /api/v1/organizations" -> jsonResponse(
          """{"uuid":"organization-3","name":"Nova Org","enforce_mfa":false,""" +
            """"current_role":"admin","capabilities":$FULL_ORGANIZATION_CAPABILITIES}"""
        )

        else -> jsonResponse(
          """{"detail":"Falha ao salvar as configurações de PIX."}""",
          code = 500,
        )
      }
    }
    val store = authenticatedStore()

    val organization = store.createOrganization(
      OrganizationDraft(
        name = "Nova Org",
        pix = PixConfiguration(
          key = "chave-pix",
          merchantName = "Nova Org",
          merchantCity = "Sao Paulo",
        ),
      )
    )

    assertEquals(OrganizationID(rawValue = "organization-3"), organization.id)
    assertNull(organization.pix)
  }

  @Test
  fun `pending invitations fill the email from the cached profile and are always pending`() =
    runTest {
      server.routeWithSession {
        jsonResponse(
          """{"items":[{"uuid":"invite-1","organization_uuid":"organization-1",""" +
            """"organization_name":"Horizonte","role":"manager"}]}"""
        )
      }
      val store = authenticatedStore()

      val invitation = store.listPendingInvitations().single()

      assertEquals("ana@rentivo.com.br", invitation.email)
      assertEquals(app.rentivo.domain.InvitationStatus.PENDING, invitation.status)
      assertEquals(OrganizationRole.MANAGER, invitation.role)
      assertEquals(OrganizationID(rawValue = "organization-1"), invitation.organizationID)
    }

  @Test
  fun `the mfa policy request maps whether the current user still needs setup`() = runTest {
    val dispatcher = server.routeWithSession {
      jsonResponse("""{"enforce_mfa":true,"mfa_setup_required":true}""")
    }
    val store = authenticatedStore()

    val policy = store.setOrganizationMFA(
      OrganizationID(rawValue = "organization-1"),
      required = true,
    )

    assertEquals(
      """{"enforce_mfa":true}""",
      dispatcher.bodyOf("PUT /api/v1/organizations/organization-1/mfa-policy"),
    )
    assertEquals(true, policy.enforceMFA)
    assertEquals(true, policy.mfaSetupRequired)
  }

  @Test
  fun `transferring a billing names the destination organization uuid`() = runTest {
    val dispatcher = server.routeWithSession { MockResponse().setResponseCode(204) }
    val store = authenticatedStore()

    store.transferBilling(
      billingID = app.rentivo.domain.BillingID(rawValue = "billing-1"),
      toOrganizationID = OrganizationID(rawValue = "organization-1"),
    )

    assertEquals(
      """{"organization_uuid":"organization-1"}""",
      dispatcher.bodyOf("POST /api/v1/billings/billing-1/transfer"),
    )
  }
}
