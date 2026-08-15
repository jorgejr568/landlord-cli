package app.rentivo.data.api

import app.rentivo.domain.BillDraft
import app.rentivo.domain.BillID
import app.rentivo.domain.BillLineItem
import app.rentivo.domain.BillLineItemID
import app.rentivo.domain.BillLineItemKind
import app.rentivo.domain.BillingID
import app.rentivo.domain.CommunicationSaveScope
import app.rentivo.domain.CommunicationType
import app.rentivo.domain.DateOnly
import app.rentivo.domain.Money
import app.rentivo.domain.RecipientID
import app.rentivo.domain.ReferenceMonth
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.UUID

private const val CREATED_BILL_BODY =
  """{"uuid":"bill-1","reference_month":"2026-07","notes":"","status":"draft",""" +
    """"due_date":"2026-07-10","status_updated_at":null,"line_items":[""" +
    """{"description":"Água","amount":4200,"item_type":"variable"},""" +
    """{"description":"Taxa extra","amount":1000,"item_type":"extra"}],"receipts":[],""" +
    """"total_amount":5200,"available_transitions":[{"target":"published",""" +
      """"label":"Publicar","style":"primary","requires_confirmation":false}]}"""

class APIRentivoStoreEncodingTest {

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

  private fun billDraft(
    dueDate: DateOnly? = DateOnly(year = 2026, month = 7, day = 10),
    lineItems: List<BillLineItem>,
  ) = BillDraft(
    billingID = BillingID(rawValue = "billing-1"),
    referenceMonth = ReferenceMonth(year = 2026, month = 7),
    dueDate = dueDate,
    notes = "",
    lineItems = lineItems,
  )

  @Test
  fun `creating a bill keys variable amounts by ULID and omits client-minted ids`() = runTest {
    // Regression test: createBill used to send only `extras`, silently dropping user-edited
    // variable line amounts. The server requires `variable_amounts` to be keyed by the billing's
    // own variable-item ULIDs; a freshly client-minted line item id must not be sent as a key.
    val dispatcher = server.routeWithSession { call ->
      if (call.route == "POST /api/v1/billings/billing-1/bills") {
        jsonResponse(CREATED_BILL_BODY)
      } else {
        unexpected(call)
      }
    }
    val store = authenticatedStore()
    val variableItemULID = "01ARZ3NDEKTSV4RRFFQ69G5FAV"

    store.createBill(
      billDraft(
        lineItems = listOf(
          BillLineItem(
            id = BillLineItemID(rawValue = variableItemULID),
            description = "Água",
            amount = Money(centavos = 4_200),
            kind = BillLineItemKind.VARIABLE,
          ),
          BillLineItem(
            id = BillLineItemID(rawValue = UUID.randomUUID().toString()),
            description = "Luz",
            amount = Money(centavos = 900),
            kind = BillLineItemKind.VARIABLE,
          ),
          BillLineItem(
            id = BillLineItemID(rawValue = UUID.randomUUID().toString()),
            description = "Taxa extra",
            amount = Money(centavos = 1_000),
            kind = BillLineItemKind.EXTRA,
          ),
        )
      )
    )

    val body = apiJson
      .parseToJsonElement(dispatcher.bodyOf("POST /api/v1/billings/billing-1/bills")).jsonObject
    val variableAmounts = body["variable_amounts"]!!.jsonObject
    assertEquals(setOf(variableItemULID), variableAmounts.keys)
    assertEquals(4_200, variableAmounts.getValue(variableItemULID).jsonPrimitive.int)
    val extras = body["extras"]!!.jsonArray
    assertEquals(1, extras.size)
    assertEquals(1_000, extras[0].jsonObject["amount"]!!.jsonPrimitive.int)
    assertEquals("2026-07", body["reference_month"]!!.jsonPrimitive.content)
  }

  @Test
  fun `creating a bill always writes due_date, as an explicit null when there is none`() =
    runTest {
      val dispatcher = server.routeWithSession { jsonResponse(CREATED_BILL_BODY) }
      val store = authenticatedStore()

      store.createBill(billDraft(dueDate = null, lineItems = emptyList()))

      val body = apiJson
        .parseToJsonElement(dispatcher.bodyOf("POST /api/v1/billings/billing-1/bills")).jsonObject
      assertTrue("due_date must be present on the wire", body.containsKey("due_date"))
      assertEquals(JsonNull, body["due_date"])
    }

  @Test
  fun `updating a bill always writes due_date so it can be cleared`() = runTest {
    // The server's PATCH handler treats an *absent* `due_date` as "leave unchanged" and an
    // explicit `null` as "clear it", so omitting it would make clearing a due date impossible.
    val dispatcher = server.routeWithSession { jsonResponse(CREATED_BILL_BODY) }
    val store = authenticatedStore()

    store.updateBill(
      billingID = BillingID(rawValue = "billing-1"),
      billID = BillID(rawValue = "bill-1"),
      draft = billDraft(
        dueDate = null,
        lineItems = listOf(
          BillLineItem(
            id = BillLineItemID(rawValue = "bill-1-0"),
            description = "Aluguel",
            amount = Money(centavos = 10_000),
            kind = BillLineItemKind.FIXED,
          )
        ),
      ),
    )

    val route = "PATCH /api/v1/billings/billing-1/bills/bill-1"
    val body = apiJson.parseToJsonElement(dispatcher.bodyOf(route)).jsonObject
    assertTrue(body.containsKey("due_date"))
    assertEquals(JsonNull, body["due_date"])
    val lineItems = body["line_items"]!!.jsonArray
    assertEquals(1, lineItems.size)
    assertEquals("fixed", lineItems[0].jsonObject["item_type"]!!.jsonPrimitive.content)
    assertEquals(10_000, lineItems[0].jsonObject["amount"]!!.jsonPrimitive.int)
  }

  @Test
  fun `updating a bill writes a real due_date unchanged`() = runTest {
    val dispatcher = server.routeWithSession { jsonResponse(CREATED_BILL_BODY) }
    val store = authenticatedStore()

    store.updateBill(
      billingID = BillingID(rawValue = "billing-1"),
      billID = BillID(rawValue = "bill-1"),
      draft = billDraft(lineItems = emptyList()),
    )

    val route = "PATCH /api/v1/billings/billing-1/bills/bill-1"
    val body = apiJson.parseToJsonElement(dispatcher.bodyOf(route)).jsonObject
    assertEquals("2026-07-10", body["due_date"]!!.jsonPrimitive.content)
  }

  @Test
  fun `sending a communication posts recipient uuids without touching the contact list`() =
    runTest {
      // Regression test: sendCommunication used to full-replace the billing's recipients via
      // PUT /recipients as a side effect of every send. It must send the chosen recipient uuids
      // directly and never call any other mutating endpoint.
      val dispatcher = server.routeWithSession { call ->
        if (call.route == "POST /api/v1/billings/billing-1/communications/send") {
          jsonResponse("""{"queued_count":2}""")
        } else {
          unexpected(call)
        }
      }
      val store = authenticatedStore()

      val queued = store.sendCommunication(
        billingID = BillingID(rawValue = "billing-1"),
        billID = BillID(rawValue = "bill-1"),
        commType = CommunicationType.PAYMENT_RECEIPT,
        recipientIDs = listOf(
          RecipientID(rawValue = "contact-1"),
          RecipientID(rawValue = "contact-2"),
        ),
        subject = "Recibo de julho",
        message = "Segue o recibo.",
        acknowledgeWarning = true,
        saveScope = CommunicationSaveScope.BILLING,
      )

      assertEquals(2, queued)
      assertEquals(
        listOf(
          "GET /api/v1/auth/session",
          "POST /api/v1/billings/billing-1/communications/send",
        ),
        dispatcher.routes,
      )
      val body = apiJson
        .parseToJsonElement(
          dispatcher.bodyOf("POST /api/v1/billings/billing-1/communications/send")
        ).jsonObject
      assertEquals("bill-1", body["bill_uuid"]!!.jsonPrimitive.content)
      assertEquals("payment_receipt", body["comm_type"]!!.jsonPrimitive.content)
      assertEquals("Recibo de julho", body["subject"]!!.jsonPrimitive.content)
      assertEquals("Segue o recibo.", body["body"]!!.jsonPrimitive.content)
      assertEquals(
        listOf("contact-1", "contact-2"),
        body["recipient_uuids"]!!.jsonArray.map { it.jsonPrimitive.content },
      )
      assertEquals("true", body["acknowledge_warning"]!!.jsonPrimitive.content)
      assertEquals("billing", body["save_scope"]!!.jsonPrimitive.content)
    }

  @Test
  fun `sending to nobody fails locally without reaching the server`() = runTest {
    val dispatcher = server.routeWithSession { unexpected(it) }
    val store = authenticatedStore()

    val error = runCatching {
      store.sendCommunication(
        billingID = BillingID(rawValue = "billing-1"),
        billID = BillID(rawValue = "bill-1"),
        commType = CommunicationType.BILL_READY,
        recipientIDs = emptyList(),
        subject = "Fatura",
        message = "Olá",
        acknowledgeWarning = false,
        saveScope = null,
      )
    }.exceptionOrNull()

    assertTrue(error is LiveAPIError.Server)
    assertEquals("Informe ao menos um destinatário.", error!!.message)
    assertEquals(listOf("GET /api/v1/auth/session"), dispatcher.routes)
  }

  @Test
  fun `a send that queues nothing is an invalid response`() = runTest {
    server.routeWithSession { jsonResponse("""{"queued_count":0}""") }
    val store = authenticatedStore()

    val error = runCatching {
      store.sendCommunication(
        billingID = BillingID(rawValue = "billing-1"),
        billID = BillID(rawValue = "bill-1"),
        commType = CommunicationType.BILL_READY,
        recipientIDs = listOf(RecipientID(rawValue = "contact-1")),
        subject = "Fatura",
        message = "Olá",
        acknowledgeWarning = false,
        saveScope = null,
      )
    }.exceptionOrNull()

    assertEquals(LiveAPIError.InvalidResponse, error)
  }

  @Test
  fun `an omitted save scope is left out of the body entirely`() = runTest {
    val dispatcher = server.routeWithSession { jsonResponse("""{"queued_count":1}""") }
    val store = authenticatedStore()

    store.sendCommunication(
      billingID = BillingID(rawValue = "billing-1"),
      billID = BillID(rawValue = "bill-1"),
      commType = CommunicationType.BILL_READY,
      recipientIDs = listOf(RecipientID(rawValue = "contact-1")),
      subject = "Fatura",
      message = "Olá",
      acknowledgeWarning = false,
      saveScope = null,
    )

    val body = apiJson
      .parseToJsonElement(
        dispatcher.bodyOf("POST /api/v1/billings/billing-1/communications/send")
      ).jsonObject
    assertTrue(!body.containsKey("save_scope"))
  }

  @Test
  fun `transitioning a bill posts the target status wire value`() = runTest {
    val dispatcher = server.routeWithSession { MockResponse().setResponseCode(204) }
    val store = authenticatedStore()

    store.transitionBill(
      billingID = BillingID(rawValue = "billing-1"),
      billID = BillID(rawValue = "bill-1"),
      currentStatus = app.rentivo.domain.BillStatus.SENT,
      status = app.rentivo.domain.BillStatus.DELAYED_PAYMENT,
    )

    val route = "POST /api/v1/billings/billing-1/bills/bill-1/transitions"
    assertEquals(
      """{"target":"delayed_payment","current_status":"sent"}""",
      dispatcher.bodyOf(route),
    )
  }
}
