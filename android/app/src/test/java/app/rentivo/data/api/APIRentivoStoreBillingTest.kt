package app.rentivo.data.api

import app.rentivo.domain.BillID
import app.rentivo.domain.BillLineItemKind
import app.rentivo.domain.BillStatus
import app.rentivo.domain.BillingCapabilities
import app.rentivo.domain.BillingDraft
import app.rentivo.domain.BillingID
import app.rentivo.domain.BillingItem
import app.rentivo.domain.BillingItemID
import app.rentivo.domain.BillingItemType
import app.rentivo.domain.BillingOwner
import app.rentivo.domain.CommunicationType
import app.rentivo.domain.DateOnly
import app.rentivo.domain.Money
import app.rentivo.domain.PDFRenderStatus
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.UUID

private const val FULL_BILLING_CAPABILITIES =
  """{"can_edit":true,"can_read_bills":true,"can_create_bills":true,"can_manage_bills":true,""" +
    """"can_read_expenses":true,"can_write_expenses":true,"can_create_exports":true,""" +
    """"can_read_attachments":true,"can_write_attachments":true,"can_read_theme":true,""" +
    """"can_manage_theme":true,"can_upload_bill_receipts":true,"can_delete":true,""" +
    """"can_transfer":true}"""

class APIRentivoStoreBillingTest {

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

  private fun billingRoutes(): RouteDispatcher = server.routeWithSession { call ->
    when (call.path) {
      "/api/v1/billings" -> jsonResponse(
        """{"items":[{"uuid":"billing-1","name":"Apartamento","description":"Aluguel",""" +
          """"owner":{"type":"user","name":"Ana"},"capabilities":$FULL_BILLING_CAPABILITIES}],""" +
          """"user_pix_incomplete":false,"stats":{"year":2026,"expected":75000,"received":3000000000,""" +
          """"pending":20000,"overdue":5000,"paid_count":3,"pending_count":1,"overdue_count":1,""" +
          """"active_count":2,"billed_count":5,"total_expenses":8000,"net_income":2999992000}}"""
      )

      "/api/v1/billings/billing-1" -> jsonResponse(
        """{"uuid":"billing-1","name":"Apartamento","description":"Aluguel",""" +
          """"owner":{"type":"user","name":"Ana"},"items":[{"uuid":"item-1",""" +
          """"description":"Aluguel","amount":12500,"item_type":"fixed"}],"pix_key":"",""" +
          """"pix_merchant_name":"","pix_merchant_city":"","recipients":[],"reply_to":[],""" +
          """"communication_templates":[{"comm_type":"bill_ready",""" +
          """"subject":"Cobrança {{unidade}} — {{mes}}","body":"Prezado {{nome_inquilino}}"},""" +
          """{"comm_type":"payment_receipt","subject":"Recibo {{unidade}}",""" +
          """"body":"Recebemos {{total}}"},{"comm_type":"telepathy","subject":"Ignorado",""" +
          """"body":"Ignorado"}],"capabilities":$FULL_BILLING_CAPABILITIES}"""
      )

      // Deliberately omits `communication_templates`.
      "/api/v1/billings/billing-2" -> jsonResponse(
        """{"uuid":"billing-2","name":"Kitnet","description":"Aluguel",""" +
          """"owner":{"type":"organization","uuid":"organization-1","name":"Horizonte"},""" +
          """"items":[],"pix_key":"chave","pix_merchant_name":"","pix_merchant_city":"",""" +
          """"recipients":[{"uuid":"contact-1","name":"Bruno","email":"bruno@rentivo.com.br"},""" +
          """{"uuid":"contact-2","name":null,"email":null}],""" +
          """"reply_to":[{"uuid":"contact-9","name":"Resposta","email":"ana@rentivo.com.br"}],""" +
          """"capabilities":$FULL_BILLING_CAPABILITIES}"""
      )

      else -> unexpected(call)
    }
  }

  @Test
  fun `the billing list hydrates recurring items for the portfolio subtotal`() = runTest {
    billingRoutes()
    val store = authenticatedStore()

    val billing = store.listBillings().first()

    assertEquals(Money(centavos = 12_500), billing.fixedSubtotal)
    assertEquals(BillingItemID(rawValue = "item-1"), billing.items.first().id)
    assertEquals(0, billing.items.first().sortOrder)
    assertEquals(BillingItemType.FIXED, billing.items.first().type)
  }

  @Test
  fun `the dashboard summary maps the billing list aggregate stats`() = runTest {
    val dispatcher = billingRoutes()
    val store = authenticatedStore()

    val summary = store.dashboardSummary()

    assertEquals(Money(centavos = 3_000_000_000L), summary.received)
    assertEquals(Money(centavos = 8_000), summary.expenses)
    assertEquals(Money(centavos = 2_999_992_000L), summary.netIncome)
    assertEquals(Money(centavos = 5_000), summary.overdue)
    assertEquals(Money(centavos = 20_000), summary.upcoming)
    // paid_count / billed_count * 100, matching the mock's integer-math formula.
    assertEquals(60, summary.collectionRatePercent)
    // One request, not a per-billing fan-out.
    assertEquals(listOf("GET /api/v1/auth/session", "GET /api/v1/billings"), dispatcher.routes)
  }

  @Test
  fun `the billing detail decodes the server communication templates`() = runTest {
    billingRoutes()
    val store = authenticatedStore()

    val billing = store.billing(BillingID(rawValue = "billing-1"))

    assertEquals(2, billing.communicationTemplates.size)
    assertEquals(
      "Cobrança {{unidade}} — {{mes}}",
      billing.template(CommunicationType.BILL_READY)?.subject,
    )
    assertEquals(
      "Prezado {{nome_inquilino}}",
      billing.template(CommunicationType.BILL_READY)?.body,
    )
    assertEquals("Recibo {{unidade}}", billing.template(CommunicationType.PAYMENT_RECEIPT)?.subject)
    assertEquals("Recebemos {{total}}", billing.template(CommunicationType.PAYMENT_RECEIPT)?.body)
  }

  @Test
  fun `a billing without templates decodes an empty template list`() = runTest {
    billingRoutes()
    val store = authenticatedStore()

    val billing = store.billing(BillingID(rawValue = "billing-2"))

    assertTrue(billing.communicationTemplates.isEmpty())
    assertNull(billing.template(CommunicationType.BILL_READY))
  }

  @Test
  fun `a billing decodes its owner, contacts and partial pix override`() = runTest {
    billingRoutes()
    val store = authenticatedStore()

    val billing = store.billing(BillingID(rawValue = "billing-2"))

    assertEquals(
      BillingOwner.Organization(
        id = app.rentivo.domain.OrganizationID(rawValue = "organization-1"),
        name = "Horizonte",
      ),
      billing.owner,
    )
    // A contact missing a name or an e-mail is dropped rather than failing the decode.
    assertEquals(listOf("Bruno"), billing.recipients.map { it.name })
    assertEquals("ana@rentivo.com.br", billing.replyTo)
    // One non-empty field is enough for the override to exist.
    assertEquals("chave", billing.pixOverride?.key)
    assertEquals(BillingCapabilities.full, billing.capabilities)
  }

  @Test
  fun `personal billings with no pix data carry no override at all`() = runTest {
    billingRoutes()
    val store = authenticatedStore()

    val billing = store.billing(BillingID(rawValue = "billing-1"))

    assertNull(billing.pixOverride)
    assertEquals(BillingOwner.User(id = 7, name = "Ana"), billing.owner)
  }

  @Test
  fun `creating a billing nulls client-minted item uuids but keeps server-issued ULIDs`() =
    runTest {
      val dispatcher = server.routeWithSession { call ->
        if (call.route == "POST /api/v1/billings") {
          jsonResponse(
            """{"uuid":"billing-new","name":"Apartamento","description":"Aluguel",""" +
              """"owner":{"type":"user","name":"Ana"},"items":[],"pix_key":"",""" +
              """"pix_merchant_name":"","pix_merchant_city":"","recipients":[],"reply_to":[],""" +
              """"capabilities":$FULL_BILLING_CAPABILITIES}"""
          )
        } else {
          unexpected(call)
        }
      }
      val store = authenticatedStore()
      val serverULID = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
      val draft = BillingDraft(
        name = "Apartamento",
        description = "Aluguel",
        owner = BillingOwner.User(id = 1, name = "Ana"),
        items = listOf(
          BillingItem(
            id = BillingItemID(rawValue = UUID.randomUUID().toString()),
            description = "Aluguel",
            amount = Money(centavos = 1_000),
            type = BillingItemType.FIXED,
            sortOrder = 0,
          ),
          BillingItem(
            id = BillingItemID(rawValue = serverULID),
            description = "Água",
            amount = Money(centavos = 500),
            type = BillingItemType.VARIABLE,
            sortOrder = 1,
          ),
        ),
      )

      store.createBilling(draft)

      val items = apiJson.parseToJsonElement(dispatcher.bodyOf("POST /api/v1/billings"))
        .jsonObject["items"]!!.jsonArray
      assertEquals(2, items.size)
      val clientMinted = items[0].jsonObject["uuid"]
      assertTrue(clientMinted == null || clientMinted == JsonNull)
      assertEquals(serverULID, items[1].jsonObject["uuid"]!!.jsonPrimitive.content)
    }

  @Test
  fun `a billing draft flattens pix and encodes reply-to as a single named contact`() = runTest {
    val dispatcher = server.routeWithSession { call ->
      if (call.route == "POST /api/v1/billings") {
        jsonResponse(
          """{"uuid":"billing-new","name":"Casa","description":"","owner":{"type":"user"},""" +
            """"items":[],"pix_key":"","pix_merchant_name":"","pix_merchant_city":"",""" +
            """"recipients":[],"reply_to":[],"capabilities":$FULL_BILLING_CAPABILITIES}"""
        )
      } else {
        unexpected(call)
      }
    }
    val store = authenticatedStore()

    store.createBilling(
      BillingDraft(
        name = "Casa",
        description = "",
        owner = BillingOwner.Organization(
          id = app.rentivo.domain.OrganizationID(rawValue = "organization-1"),
          name = "Horizonte",
        ),
        items = emptyList(),
        replyTo = "ana@rentivo.com.br",
      )
    )

    val body = apiJson.parseToJsonElement(dispatcher.bodyOf("POST /api/v1/billings")).jsonObject
    assertEquals("organization", body["owner"]!!.jsonObject["type"]!!.jsonPrimitive.content)
    assertEquals("organization-1", body["owner"]!!.jsonObject["uuid"]!!.jsonPrimitive.content)
    assertEquals("", body["pix_key"]!!.jsonPrimitive.content)
    val replyTo = body["reply_to"]!!.jsonArray
    assertEquals(1, replyTo.size)
    assertEquals("Resposta", replyTo[0].jsonObject["name"]!!.jsonPrimitive.content)
    assertEquals("ana@rentivo.com.br", replyTo[0].jsonObject["email"]!!.jsonPrimitive.content)
  }

  private fun billDetailRoutes(): RouteDispatcher = server.routeWithSession { call ->
    when (call.path) {
      "/api/v1/billings/billing-1/bills/bill-1" -> jsonResponse(
        """{"uuid":"bill-1","reference_month":"2026-07","notes":"","status":"sent",""" +
          """"due_date":"2026-07-10","status_updated_at":null,"line_items":[""" +
          """{"description":"Aluguel","amount":10000,"item_type":"fixed"},""" +
          """{"description":"Água","amount":0,"item_type":"variable"}],"receipts":[],""" +
          """"total_amount":10000,"pdf_render_status":"pending","has_invoice":true,""" +
          """"has_recibo":false,"capabilities":{"can_download_invoice":false,""" +
          """"can_download_recibo":false,"can_compose":true,"can_send_invoice":false,""" +
          """"can_send_recibo":true,"can_regenerate":true,"can_edit":true,""" +
          """"can_delete":true,"can_transition":true,"can_upload_receipts":true,""" +
          """"can_delete_receipts":true,"can_reorder_receipts":true},"available_transitions":[""" +
          """{"target":"paid","label":"Marcar como paga","style":"primary",""" +
          """"requires_confirmation":false},{"target":"delayed_payment","label":"Atrasada",""" +
          """"style":"secondary","requires_confirmation":true},{"target":"teleported"}]}"""
      )

      // An older payload that predates `pdf_render_status`/`capabilities` on the wire.
      "/api/v1/billings/billing-1/bills/bill-legacy" -> jsonResponse(
        """{"uuid":"bill-legacy","reference_month":"2026-07","notes":"","status":"sent",""" +
          """"due_date":null,"status_updated_at":null,"line_items":[],"receipts":[],""" +
          """"total_amount":0,"pdf_render_status":null,"available_transitions":[]}"""
      )

      "/api/v1/billings/billing-1/bills/bill-paid" -> jsonResponse(
        """{"uuid":"bill-paid","reference_month":"2026-07","notes":"","status":"paid",""" +
          """"due_date":"2026-07-10","status_updated_at":"2026-07-12T09:30:00+00:00",""" +
          """"line_items":[],"receipts":[{"uuid":"receipt-1","filename":"nota.pdf",""" +
          """"content_type":"application/pdf","file_size":8,"sort_order":0}],"total_amount":0,""" +
          """"available_transitions":[]}"""
      )

      "/api/v1/billings/billing-1/bills/bill-1/regenerate" -> jsonResponse(
        """{"uuid":"bill-1","reference_month":"2026-07","notes":"","status":"sent",""" +
          """"due_date":"2026-07-10","status_updated_at":null,"line_items":[],"receipts":[],""" +
          """"total_amount":10000,"pdf_render_status":"pending","has_invoice":true,""" +
          """"has_recibo":false,"capabilities":{"can_download_invoice":false,""" +
          """"can_download_recibo":false,"can_send_invoice":false,"can_send_recibo":false,""" +
          """"can_regenerate":true,"can_edit":true,"can_delete":true,"can_transition":true,""" +
          """"can_upload_receipts":true,"can_delete_receipts":true,""" +
          """"can_reorder_receipts":true,"can_compose":true},"available_transitions":[]}""",
        code = 202,
      )

      else -> unexpected(call)
    }
  }

  @Test
  fun `a bill decodes the server available transitions and total amount`() = runTest {
    billDetailRoutes()
    val store = authenticatedStore()

    val bill = store.bill(BillingID(rawValue = "billing-1"), BillID(rawValue = "bill-1"))

    // An unrecognized transition target is dropped, not fatal.
    assertEquals(listOf(BillStatus.PAID, BillStatus.DELAYED_PAYMENT), bill.availableTransitions)
    assertEquals(Money(centavos = 10_000), bill.serverTotal)
    assertEquals(Money(centavos = 10_000), bill.effectiveTotal)
    assertEquals(setOf(BillStatus.PAID, BillStatus.DELAYED_PAYMENT), bill.effectiveTransitions)
  }

  @Test
  fun `a bill decodes the pdf render status and per-bill capabilities`() = runTest {
    billDetailRoutes()
    val store = authenticatedStore()

    val bill = store.bill(BillingID(rawValue = "billing-1"), BillID(rawValue = "bill-1"))

    assertEquals(PDFRenderStatus.PENDING, bill.pdfRenderStatus)
    assertTrue(bill.isRenderingPDF)
    assertTrue(bill.hasInvoice)
    assertFalse(bill.hasRecibo)
    assertTrue(bill.capabilities.canEdit)
    assertTrue(bill.capabilities.canDelete)
    assertTrue(bill.capabilities.canTransition)
    assertTrue(bill.capabilities.canUploadReceipts)
    assertTrue(bill.capabilities.canDeleteReceipts)
    assertTrue(bill.capabilities.canReorderReceipts)
    assertFalse(bill.capabilities.canDownloadInvoice)
    assertFalse(bill.capabilities.canDownloadRecibo)
    assertFalse(bill.capabilities.canOpenRecibo)
    assertTrue(bill.capabilities.canCompose)
    assertFalse(bill.capabilities.canSendInvoice)
    assertTrue(bill.capabilities.canSendRecibo)
    assertTrue(bill.capabilities.canRegenerate)
  }

  @Test
  fun `bill line items get stable synthetic ids because the server issues none`() = runTest {
    billDetailRoutes()
    val store = authenticatedStore()

    val bill = store.bill(BillingID(rawValue = "billing-1"), BillID(rawValue = "bill-1"))

    assertEquals(listOf("bill-1-0", "bill-1-1"), bill.lineItems.map { it.id.rawValue })
    assertEquals(
      listOf(BillLineItemKind.FIXED, BillLineItemKind.VARIABLE),
      bill.lineItems.map { it.kind },
    )
  }

  @Test
  fun `a bill without render metadata stays permissive`() = runTest {
    billDetailRoutes()
    val store = authenticatedStore()

    val bill = store.bill(BillingID(rawValue = "billing-1"), BillID(rawValue = "bill-legacy"))

    assertNull(bill.pdfRenderStatus)
    assertFalse(bill.isRenderingPDF)
    assertFalse(bill.hasInvoice)
    assertFalse(bill.hasRecibo)
    // A null due date stays null rather than collapsing to an epoch sentinel.
    assertNull(bill.dueDate)
    assertEquals(app.rentivo.domain.BillCapabilities.permissive, bill.capabilities)
  }

  @Test
  fun `only a paid bill derives its payment date from the last status change`() = runTest {
    billDetailRoutes()
    val store = authenticatedStore()

    val paid = store.bill(BillingID(rawValue = "billing-1"), BillID(rawValue = "bill-paid"))
    val sent = store.bill(BillingID(rawValue = "billing-1"), BillID(rawValue = "bill-1"))

    assertEquals(DateOnly(year = 2026, month = 7, day = 12), paid.paidAt)
    assertEquals(DateOnly(year = 2026, month = 7, day = 10), paid.dueDate)
    assertEquals(listOf("nota.pdf"), paid.receipts.map { it.name })
    assertNull(sent.paidAt)
  }

  @Test
  fun `regenerating a bill returns the queued pending bill`() = runTest {
    billDetailRoutes()
    val store = authenticatedStore()

    val bill = store.regenerateBill(
      BillingID(rawValue = "billing-1"),
      BillID(rawValue = "bill-1"),
    )

    assertEquals(PDFRenderStatus.PENDING, bill.pdfRenderStatus)
    assertTrue(bill.isRenderingPDF)
    assertFalse(bill.capabilities.canDownloadInvoice)
    assertTrue(bill.capabilities.canRegenerate)
  }

  @Test
  fun `a malformed reference month is a decode error rather than a crash`() = runTest {
    server.routeWithSession {
      // Out-of-range month (13): the failable wire parser must turn this into a decode error
      // instead of reaching the `require`-enforcing constructor.
      jsonResponse(
        """{"uuid":"bill-1","reference_month":"2026-13","notes":"","status":"draft",""" +
          """"due_date":"2026-07-10","status_updated_at":null,"line_items":[],"receipts":[],""" +
          """"total_amount":0,"available_transitions":[]}"""
      )
    }
    val store = authenticatedStore()

    val error = runCatching {
      store.bill(BillingID(rawValue = "billing-1"), BillID(rawValue = "bill-1"))
    }.exceptionOrNull()

    assertEquals(LiveAPIError.InvalidResponse, error)
  }

  @Test
  fun `a malformed due date is a decode error rather than a silent epoch`() = runTest {
    server.routeWithSession {
      jsonResponse(
        """{"uuid":"bill-1","reference_month":"2026-07","notes":"","status":"draft",""" +
          """"due_date":"ontem","status_updated_at":null,"line_items":[],"receipts":[],""" +
          """"total_amount":0,"available_transitions":[]}"""
      )
    }
    val store = authenticatedStore()

    val error = runCatching {
      store.bill(BillingID(rawValue = "billing-1"), BillID(rawValue = "bill-1"))
    }.exceptionOrNull()

    assertEquals(LiveAPIError.InvalidResponse, error)
  }

  @Test
  fun `an unknown bill status falls back to draft instead of failing`() = runTest {
    server.routeWithSession {
      jsonResponse(
        """{"uuid":"bill-1","reference_month":"2026-07","notes":"","status":"teleported",""" +
          """"due_date":null,"status_updated_at":null,"line_items":[],"receipts":[],""" +
          """"total_amount":0,"available_transitions":[]}"""
      )
    }
    val store = authenticatedStore()

    val bill = store.bill(BillingID(rawValue = "billing-1"), BillID(rawValue = "bill-1"))

    assertEquals(BillStatus.DRAFT, bill.status)
  }
}
