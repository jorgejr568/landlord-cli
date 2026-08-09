package app.rentivo.data.api

import app.rentivo.data.DemoRepository
import app.rentivo.data.DemoSettings
import app.rentivo.domain.AttachmentID
import app.rentivo.domain.BillID
import app.rentivo.domain.BillingID
import app.rentivo.domain.DateOnly
import app.rentivo.domain.ExpenseCategory
import app.rentivo.domain.ExpenseID
import app.rentivo.domain.InvitationID
import app.rentivo.domain.Money
import app.rentivo.domain.OrganizationID
import app.rentivo.domain.PasskeyID
import app.rentivo.domain.ReceiptID
import app.rentivo.domain.ThemeSource
import app.rentivo.domain.ThemeTarget
import app.rentivo.domain.ThemeValues
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * The endpoint map: every remaining repository call must reach exactly the path, verb and body the
 * `/api/v1` contract defines, and decode the parts of the response the domain models.
 */
class APIRentivoStoreEndpointTest {

  private val server = MockWebServer()
  private val downloads = makeIsolatedDownloadsStore()

  @Before
  fun start() {
    server.start()
  }

  @After
  fun stop() {
    server.shutdown()
    downloads.purge()
  }

  private suspend fun authenticatedStore(): APIRentivoStore {
    val store = APIRentivoStore(liveClient(server, downloads = downloads))
    assertNotNull(store.restoreSession())
    return store
  }

  @Test
  fun `expenses decode their category, date and amount`() = runTest {
    val dispatcher = server.routeWithSession { call ->
      when (call.route) {
        "GET /api/v1/billings/billing-1/expenses" -> jsonResponse(
          """{"items":[{"uuid":"expense-1","description":"Reparo","category":"manutencao",""" +
            """"incurred_on":"2026-07-03","amount":15000},{"uuid":"expense-2",""" +
            """"description":"Outro","category":"teleporte","incurred_on":"2026-07-04",""" +
            """"amount":100}]}"""
        )

        "POST /api/v1/billings/billing-1/expenses" -> jsonResponse(
          """{"uuid":"expense-3","description":"IPTU","category":"iptu",""" +
            """"incurred_on":"2026-07-05","amount":9900}"""
        )

        else -> unexpected(call)
      }
    }
    val store = authenticatedStore()

    val listed = store.listExpenses(BillingID(rawValue = "billing-1"))
    val created = store.createExpense(
      billingID = BillingID(rawValue = "billing-1"),
      description = "IPTU",
      category = ExpenseCategory.PROPERTY_TAX,
      incurredOn = DateOnly(year = 2026, month = 7, day = 5),
      amount = Money(centavos = 9_900),
    )

    assertEquals(ExpenseCategory.MAINTENANCE, listed[0].category)
    assertEquals(DateOnly(year = 2026, month = 7, day = 3), listed[0].incurredOn)
    assertEquals(Money(centavos = 15_000), listed[0].amount)
    // An unknown category falls back rather than failing the whole list.
    assertEquals(ExpenseCategory.OTHER, listed[1].category)
    assertEquals(ExpenseID(rawValue = "expense-3"), created.id)
    assertEquals(BillingID(rawValue = "billing-1"), created.billingID)
    assertEquals(
      """{"description":"IPTU","category":"iptu","incurred_on":"2026-07-05","amount":9900}""",
      dispatcher.bodyOf("POST /api/v1/billings/billing-1/expenses"),
    )
  }

  @Test
  fun `attachments decode their media type and size`() = runTest {
    server.routeWithSession {
      jsonResponse(
        """{"items":[{"uuid":"attachment-1","name":"contrato.pdf",""" +
          """"content_type":"application/pdf","file_size":2048}]}"""
      )
    }
    val store = authenticatedStore()

    val attachment = store.listAttachments(BillingID(rawValue = "billing-1")).single()

    assertEquals(AttachmentID(rawValue = "attachment-1"), attachment.id)
    assertEquals("application/pdf", attachment.mediaType)
    assertEquals(2048, attachment.byteCount)
  }

  @Test
  fun `receipt ordering and deletion reach their own endpoints`() = runTest {
    val dispatcher = server.routeWithSession { call ->
      if (call.method == "PUT") jsonResponse("""{"items":[]}""") else MockResponse()
        .setResponseCode(204)
    }
    val store = authenticatedStore()

    store.reorderReceipts(
      billingID = BillingID(rawValue = "billing-1"),
      billID = BillID(rawValue = "bill-1"),
      receiptIDs = listOf(ReceiptID(rawValue = "r2"), ReceiptID(rawValue = "r1")),
    )
    store.deleteReceipt(
      billingID = BillingID(rawValue = "billing-1"),
      billID = BillID(rawValue = "bill-1"),
      receiptID = ReceiptID(rawValue = "r1"),
    )

    assertEquals(
      """{"order":["r2","r1"]}""",
      dispatcher.bodyOf("PUT /api/v1/billings/billing-1/bills/bill-1/receipt-order"),
    )
    assertTrue(
      dispatcher.routes.contains("DELETE /api/v1/billings/billing-1/bills/bill-1/receipts/r1")
    )
  }

  @Test
  fun `an export request posts the chosen format`() = runTest {
    val dispatcher = server.routeWithSession {
      jsonResponse("""{"format":"csv","status":"queued"}""")
    }
    val store = authenticatedStore()

    store.requestExport(BillingID(rawValue = "billing-1"), format = "csv")

    assertEquals(
      """{"format":"csv"}""",
      dispatcher.bodyOf("POST /api/v1/billings/billing-1/exports"),
    )
  }

  @Test
  fun `a communication preview decodes both warning severities`() = runTest {
    server.routeWithSession {
      jsonResponse(
        """{"html":"<p>Olá</p>","severe":["Sem PIX"],"mild":["Assunto curto"]}"""
      )
    }
    val store = authenticatedStore()

    val preview = store.previewCommunication(
      billingID = BillingID(rawValue = "billing-1"),
      subject = "Fatura",
      message = "Olá",
    )

    assertEquals("<p>Olá</p>", preview.html)
    assertEquals(listOf("Sem PIX"), preview.severeWarnings)
    assertEquals(listOf("Assunto curto"), preview.mildWarnings)
  }

  @Test
  fun `every download names its own file and endpoint`() = runTest {
    val dispatcher = server.routeWithSession {
      MockResponse()
        .setResponseCode(200)
        .setHeader("Content-Type", "application/pdf")
        .setBody("%PDF-1.4")
    }
    val store = authenticatedStore()
    val billingID = BillingID(rawValue = "billing-1")
    val billID = BillID(rawValue = "bill-1")

    val invoice = store.downloadInvoice(billingID, billID)
    val recibo = store.downloadRecibo(billingID, billID)
    val receipt = store.downloadReceipt(billingID, billID, ReceiptID(rawValue = "receipt-1"))
    val attachment = store.downloadAttachment(billingID, AttachmentID(rawValue = "attachment-1"))

    assertEquals("fatura-bill-1.pdf", invoice.filename)
    assertEquals("recibo-bill-1.pdf", recibo.filename)
    assertEquals("comprovante-receipt-1.pdf", receipt.filename)
    assertEquals("arquivo-attachment-1.pdf", attachment.filename)
    assertEquals(
      listOf(
        "GET /api/v1/auth/session",
        "GET /api/v1/billings/billing-1/bills/bill-1/invoice",
        "GET /api/v1/billings/billing-1/bills/bill-1/recibo",
        "GET /api/v1/billings/billing-1/bills/bill-1/receipts/receipt-1",
        "GET /api/v1/billings/billing-1/attachments/attachment-1",
      ),
      dispatcher.routes,
    )
  }

  @Test
  fun `the totp enrollment flow decodes the setup payload and the recovery codes`() = runTest {
    val dispatcher = server.routeWithSession { call ->
      when (call.route) {
        "POST /api/v1/security/totp/setup" -> jsonResponse(
          """{"secret":"S3CR3T","provisioning_uri":"otpauth://totp/Rentivo",""" +
            """"qr_code_base64":"QUJD"}"""
        )

        "POST /api/v1/security/totp/confirm",
        "POST /api/v1/security/recovery-codes/regenerate",
        -> jsonResponse("""{"recovery_codes":["aaa-111","bbb-222"]}""")

        else -> MockResponse().setResponseCode(204)
      }
    }
    val store = authenticatedStore()

    val enrollment = store.beginTOTPEnrollment()
    val confirmed = store.confirmTOTPEnrollment("123456")
    val regenerated = store.regenerateRecoveryCodes()
    store.disableTOTP("s3cret")
    store.deletePasskey(PasskeyID(rawValue = "passkey-1"))

    assertEquals("S3CR3T", enrollment.secret)
    assertEquals("otpauth://totp/Rentivo", enrollment.provisioningURI)
    assertEquals("QUJD", enrollment.qrCodeBase64)
    assertEquals(listOf("aaa-111", "bbb-222"), confirmed)
    assertEquals(listOf("aaa-111", "bbb-222"), regenerated)
    assertEquals(
      """{"code":"123456"}""",
      dispatcher.bodyOf("POST /api/v1/security/totp/confirm"),
    )
    assertEquals(
      """{"password":"s3cret"}""",
      dispatcher.bodyOf("POST /api/v1/security/totp/disable"),
    )
    assertTrue(dispatcher.routes.contains("DELETE /api/v1/security/passkeys/passkey-1"))
  }

  @Test
  fun `accepting and declining an invitation hit their own endpoints`() = runTest {
    val dispatcher = server.routeWithSession { MockResponse().setResponseCode(204) }
    val store = authenticatedStore()

    store.acceptInvitation(InvitationID(rawValue = "invite-1"))
    store.declineInvitation(InvitationID(rawValue = "invite-2"))

    assertEquals(
      listOf(
        "GET /api/v1/auth/session",
        "POST /api/v1/invites/invite-1/accept",
        "POST /api/v1/invites/invite-2/decline",
      ),
      dispatcher.routes,
    )
  }

  @Test
  fun `each theme target resolves to its own path`() = runTest {
    val dispatcher = server.routeWithSession { call ->
      if (call.method == "GET") {
        jsonResponse(
          """{"owner_name":"Ana","effective_source":"organization","stored":null,""" +
            """"effective":{"header_font":"Lora","text_font":"Roboto","primary":"#07875F",""" +
            """"primary_light":"#DDF6EC","secondary":"#252635","secondary_dark":"#171822",""" +
            """"text_color":"#252635","text_contrast":"#FFFFFF"},""" +
            """"capabilities":{"can_edit":true,"can_reset":false}}"""
        )
      } else {
        MockResponse().setResponseCode(204)
      }
    }
    val store = authenticatedStore()

    val record = store.theme(ThemeTarget.User)
    store.updateTheme(
      ThemeTarget.Organization(OrganizationID(rawValue = "organization-1")),
      ThemeValues.rentivo,
    )
    store.resetTheme(ThemeTarget.Billing(BillingID(rawValue = "billing-1")))

    assertEquals("Ana", record.ownerName)
    assertNull(record.stored)
    assertEquals(ThemeSource.ORGANIZATION, record.effectiveSource)
    assertEquals(app.rentivo.domain.ThemeFont.LORA, record.effective.headerFont)
    assertTrue(record.canEdit)
    assertEquals(
      listOf(
        "GET /api/v1/auth/session",
        "GET /api/v1/themes/user",
        "PUT /api/v1/themes/organizations/organization-1",
        "DELETE /api/v1/themes/billings/billing-1",
      ),
      dispatcher.routes,
    )
  }

  @Test
  fun `an unknown theme source falls back to the default`() = runTest {
    server.routeWithSession {
      jsonResponse(
        """{"owner_name":"Ana","effective_source":"telepathy","effective":{""" +
          """"header_font":"Lora","text_font":"Roboto","primary":"#07875F",""" +
          """"primary_light":"#DDF6EC","secondary":"#252635","secondary_dark":"#171822",""" +
          """"text_color":"#252635","text_contrast":"#FFFFFF"},""" +
          """"capabilities":{"can_edit":false,"can_reset":false}}"""
      )
    }
    val store = authenticatedStore()

    assertEquals(ThemeSource.DEFAULT, store.theme(ThemeTarget.User).effectiveSource)
  }

  @Test
  fun `member management posts the role and removes by user id`() = runTest {
    val dispatcher = server.routeWithSession { MockResponse().setResponseCode(204) }
    val store = authenticatedStore()

    store.updateMemberRole(
      organizationID = OrganizationID(rawValue = "organization-1"),
      userID = 11,
      role = app.rentivo.domain.OrganizationRole.MANAGER,
    )
    store.removeMember(OrganizationID(rawValue = "organization-1"), userID = 11)
    store.deleteOrganization(OrganizationID(rawValue = "organization-1"))
    store.deleteBilling(BillingID(rawValue = "billing-1"))
    store.deleteBill(BillingID(rawValue = "billing-1"), BillID(rawValue = "bill-1"))
    store.deleteExpense(BillingID(rawValue = "billing-1"), ExpenseID(rawValue = "expense-1"))
    store.deleteAttachment(
      BillingID(rawValue = "billing-1"),
      AttachmentID(rawValue = "attachment-1"),
    )
    store.revokeAPIKey(app.rentivo.domain.APIKeyID(rawValue = "key-1"))

    assertEquals(
      """{"role":"manager"}""",
      dispatcher.bodyOf("PATCH /api/v1/organizations/organization-1/members/11"),
    )
    assertEquals(
      listOf(
        "GET /api/v1/auth/session",
        "PATCH /api/v1/organizations/organization-1/members/11",
        "DELETE /api/v1/organizations/organization-1/members/11",
        "DELETE /api/v1/organizations/organization-1",
        "DELETE /api/v1/billings/billing-1",
        "DELETE /api/v1/billings/billing-1/bills/bill-1",
        "DELETE /api/v1/billings/billing-1/expenses/expense-1",
        "DELETE /api/v1/billings/billing-1/attachments/attachment-1",
        "DELETE /api/v1/api-keys/key-1",
      ),
      dispatcher.routes,
    )
  }

  @Test
  fun `listing bills decodes every row through the same bill mapping`() = runTest {
    server.routeWithSession {
      jsonResponse(
        """{"items":[{"uuid":"bill-1","reference_month":"2026-07","notes":"","status":"paid",""" +
          """"due_date":"2026-07-10","status_updated_at":"2026-07-11T08:00:00Z",""" +
          """"line_items":[],"receipts":[],"total_amount":1000,""" +
          """"available_transitions":[]}]}"""
      )
    }
    val store = authenticatedStore()

    val bill = store.listBills(BillingID(rawValue = "billing-1")).single()

    assertEquals(BillID(rawValue = "bill-1"), bill.id)
    assertEquals(BillingID(rawValue = "billing-1"), bill.billingID)
    assertEquals(DateOnly(year = 2026, month = 7, day = 11), bill.paidAt)
  }

  @Test
  fun `live dependencies resolve every repository to the same live store`() {
    val store = APIRentivoStore(liveClient(server, downloads = downloads))
    val demo = InertDemoRepository()

    val dependencies = liveDependencies(store, demo)

    assertSame(store, dependencies.auth)
    assertSame(store, dependencies.profile)
    assertSame(store, dependencies.billings)
    assertSame(store, dependencies.bills)
    assertSame(store, dependencies.expenses)
    assertSame(store, dependencies.attachments)
    assertSame(store, dependencies.communications)
    assertSame(store, dependencies.downloads)
    assertSame(store, dependencies.exports)
    assertSame(store, dependencies.dashboard)
    assertSame(store, dependencies.activities)
    assertSame(store, dependencies.organizations)
    assertSame(store, dependencies.invitations)
    assertSame(store, dependencies.security)
    assertSame(store, dependencies.apiKeys)
    assertSame(store, dependencies.themes)
    // Callers must never need to know the concrete store: `usesLiveAPI` is what separates this
    // wiring from the mock one, and demo settings stay on a separate repository.
    assertTrue(dependencies.auth.usesLiveAPI)
    assertSame(demo, dependencies.demo)
  }

  private class InertDemoRepository : DemoRepository {
    override val demoSettings: DemoSettings = DemoSettings.standard
    override fun failNextOperation() = Unit
    override fun setEmptyMode(enabled: Boolean) = Unit
    override fun setViewerMode(enabled: Boolean) = Unit
    override fun setDelayEnabled(enabled: Boolean) = Unit
    override fun reset() = Unit
  }
}
