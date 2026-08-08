from unittest.mock import MagicMock, patch

import pytest

from rentivo.jobs.base import JobContext, PermanentJobError
from rentivo.jobs.handlers.pdf import _on_pdf_render_failed, handle_pdf_render
from rentivo.jobs.payloads import PdfRenderPayload

LEGACY_JOB_ULID = "01ARZ3NDEKTSV4RRFFQ69G5FAV"


def _render(payload: dict, ulid: str = LEGACY_JOB_ULID) -> None:
    """Decode a stored payload the way the registry does, then run the handler
    with the job identity the driver would have supplied."""
    handle_pdf_render(PdfRenderPayload.model_validate(payload), JobContext(ulid=ulid, attempts=1))


def _patches():
    """All collaborators the handler imports — so we can assert dispatch without DB."""
    return {
        "engine": patch("rentivo.jobs.handlers.pdf.get_engine"),
        "bill_repo": patch("rentivo.jobs.handlers.pdf.SQLAlchemyBillRepository"),
        "billing_repo": patch("rentivo.jobs.handlers.pdf.SQLAlchemyBillingRepository"),
        "user_repo": patch("rentivo.jobs.handlers.pdf.SQLAlchemyUserRepository"),
        "org_repo": patch("rentivo.jobs.handlers.pdf.SQLAlchemyOrganizationRepository"),
        "receipt_repo": patch("rentivo.jobs.handlers.pdf.SQLAlchemyReceiptRepository"),
        "theme_repo": patch("rentivo.jobs.handlers.pdf.SQLAlchemyThemeRepository"),
        "storage": patch("rentivo.jobs.handlers.pdf.get_storage"),
        "service_cls": patch("rentivo.jobs.handlers.pdf.BillService"),
    }


def test_handler_claims_legacy_pending_render_with_operation_token():
    p = _patches()
    with (
        p["engine"] as engine_mock,
        p["bill_repo"] as bill_repo_cls,
        p["billing_repo"] as billing_repo_cls,
        p["user_repo"],
        p["org_repo"],
        p["receipt_repo"],
        p["theme_repo"],
        p["storage"],
        p["service_cls"] as svc_cls,
    ):
        # Engine.connect() context-manager returns a connection.
        conn = MagicMock()
        engine_mock.return_value.connect.return_value.__enter__.return_value = conn

        bill = MagicMock(id=42, billing_id=7)
        billing = MagicMock(id=7)
        bill_repo = MagicMock()
        bill_repo.get_by_id.return_value = bill
        bill_repo.claim_pending_pdf_render.return_value = True
        bill_repo_cls.return_value = bill_repo
        billing_repo = MagicMock()
        billing_repo.get_by_id.return_value = billing
        billing_repo_cls.return_value = billing_repo

        service = MagicMock()
        svc_cls.return_value = service

        _render({"bill_id": 42})

        bill_repo.get_by_id.assert_called_once_with(42)
        billing_repo.get_by_id.assert_called_once_with(7)
        bill_repo.claim_pending_pdf_render.assert_called_once_with(
            42,
            LEGACY_JOB_ULID,
        )
        service._render_pdf_sync.assert_called_once_with(
            bill,
            billing,
            render_operation_id=LEGACY_JOB_ULID,
        )


def test_handler_discards_legacy_job_when_pending_render_claim_is_stale():
    p = _patches()
    with (
        p["engine"] as engine_mock,
        p["bill_repo"] as bill_repo_cls,
        p["billing_repo"] as billing_repo_cls,
        p["user_repo"],
        p["org_repo"],
        p["receipt_repo"],
        p["theme_repo"],
        p["storage"],
        p["service_cls"] as svc_cls,
    ):
        conn = MagicMock()
        engine_mock.return_value.connect.return_value.__enter__.return_value = conn
        bill = MagicMock(id=42, billing_id=7)
        billing = MagicMock(id=7)
        bill_repo = MagicMock()
        bill_repo.get_by_id.return_value = bill
        bill_repo.claim_pending_pdf_render.return_value = False
        bill_repo_cls.return_value = bill_repo
        billing_repo = MagicMock()
        billing_repo.get_by_id.return_value = billing
        billing_repo_cls.return_value = billing_repo

        _render({"bill_id": 42})

        bill_repo.claim_pending_pdf_render.assert_called_once_with(
            42,
            LEGACY_JOB_ULID,
        )
        svc_cls.return_value._render_pdf_sync.assert_not_called()


def test_handler_forwards_render_operation_token_for_conditional_completion():
    p = _patches()
    with (
        p["engine"] as engine_mock,
        p["bill_repo"] as bill_repo_cls,
        p["billing_repo"] as billing_repo_cls,
        p["user_repo"],
        p["org_repo"],
        p["receipt_repo"],
        p["theme_repo"],
        p["storage"],
        p["service_cls"] as svc_cls,
    ):
        conn = MagicMock()
        engine_mock.return_value.connect.return_value.__enter__.return_value = conn
        bill = MagicMock(id=42, billing_id=7)
        billing = MagicMock(id=7)
        bill_repo = MagicMock()
        bill_repo.get_by_id.return_value = bill
        bill_repo_cls.return_value = bill_repo
        billing_repo = MagicMock()
        billing_repo.get_by_id.return_value = billing
        billing_repo_cls.return_value = billing_repo
        service = MagicMock()
        svc_cls.return_value = service

        _render({"bill_id": 42, "render_operation_id": "01JRENDEROPERATION000000001"})

        service._render_pdf_sync.assert_called_once_with(
            bill,
            billing,
            render_operation_id="01JRENDEROPERATION000000001",
        )


def test_handler_retries_guarded_cleanup_while_receipt_is_active():
    p = _patches()
    with (
        p["engine"] as engine_mock,
        p["bill_repo"] as bill_repo_cls,
        p["billing_repo"] as billing_repo_cls,
        p["user_repo"],
        p["org_repo"],
        p["receipt_repo"] as receipt_repo_cls,
        p["theme_repo"],
        p["storage"] as storage_factory,
        p["service_cls"] as service_cls,
    ):
        engine_mock.return_value.connect.return_value.__enter__.return_value = MagicMock()
        bill_repo = bill_repo_cls.return_value
        bill_repo.get_by_id.return_value = MagicMock(id=42, billing_id=7)
        bill_repo.get_pdf_render_state.return_value = (
            "01JRENDEROPERATION000000001",
            "pending",
            "old.pdf",
        )
        billing_repo_cls.return_value.get_by_id.return_value = MagicMock(id=7)
        receipt_repo_cls.return_value.get_by_uuid.return_value = MagicMock(uuid="receipt-uuid")

        with pytest.raises(RuntimeError, match="still active"):
            _render(
                {
                    "bill_id": 42,
                    "render_operation_id": "01JRENDEROPERATION000000001",
                    "receipt_cleanup": {"uuid": "receipt-uuid", "storage_key": "receipts/file.pdf"},
                }
            )

        storage_factory.return_value.delete.assert_not_called()
        service_cls.return_value._render_pdf_sync.assert_not_called()


def test_handler_discards_cancelled_guarded_cleanup_when_receipt_is_active():
    p = _patches()
    with (
        p["engine"] as engine_mock,
        p["bill_repo"] as bill_repo_cls,
        p["billing_repo"] as billing_repo_cls,
        p["user_repo"],
        p["org_repo"],
        p["receipt_repo"] as receipt_repo_cls,
        p["theme_repo"],
        p["storage"] as storage_factory,
        p["service_cls"] as service_cls,
    ):
        engine_mock.return_value.connect.return_value.__enter__.return_value = MagicMock()
        bill_repo = bill_repo_cls.return_value
        bill_repo.get_by_id.return_value = MagicMock(id=42, billing_id=7)
        bill_repo.get_pdf_render_state.return_value = (None, "succeeded", "old.pdf")
        billing_repo_cls.return_value.get_by_id.return_value = MagicMock(id=7)
        receipt_repo_cls.return_value.get_by_uuid.return_value = MagicMock(uuid="receipt-uuid")

        _render(
            {
                "bill_id": 42,
                "render_operation_id": "01JRENDEROPERATION000000001",
                "receipt_cleanup": {"uuid": "receipt-uuid", "storage_key": "receipts/file.pdf"},
            }
        )

        storage_factory.return_value.delete.assert_not_called()
        service_cls.return_value._render_pdf_sync.assert_not_called()


def test_handler_deletes_guarded_receipt_storage_before_render():
    p = _patches()
    events = []
    with (
        p["engine"] as engine_mock,
        p["bill_repo"] as bill_repo_cls,
        p["billing_repo"] as billing_repo_cls,
        p["user_repo"],
        p["org_repo"],
        p["receipt_repo"] as receipt_repo_cls,
        p["theme_repo"],
        p["storage"] as storage_factory,
        p["service_cls"] as service_cls,
    ):
        engine_mock.return_value.connect.return_value.__enter__.return_value = MagicMock()
        bill_repo_cls.return_value.get_by_id.return_value = MagicMock(id=42, billing_id=7)
        billing_repo_cls.return_value.get_by_id.return_value = MagicMock(id=7)
        receipt_repo_cls.return_value.get_by_uuid.return_value = None
        storage_factory.return_value.delete.side_effect = lambda _key: events.append("cleanup")
        service_cls.return_value._render_pdf_sync.side_effect = lambda *_args, **_kwargs: events.append("render")

        _render(
            {
                "bill_id": 42,
                "render_operation_id": "01JRENDEROPERATION000000001",
                "receipt_cleanup": {"uuid": "receipt-uuid", "storage_key": "receipts/file.pdf"},
            }
        )

        assert events == ["cleanup", "render"]
        storage_factory.return_value.delete.assert_called_once_with("receipts/file.pdf")


def test_handler_rejects_legacy_payload_without_persistent_job_identity():
    p = _patches()
    with (
        p["engine"] as engine_mock,
        p["bill_repo"] as bill_repo_cls,
        p["billing_repo"] as billing_repo_cls,
        p["user_repo"],
        p["org_repo"],
        p["receipt_repo"],
        p["theme_repo"],
        p["storage"],
        p["service_cls"],
    ):
        engine_mock.return_value.connect.return_value.__enter__.return_value = MagicMock()
        bill_repo_cls.return_value.get_by_id.return_value = MagicMock(id=42, billing_id=7)
        billing_repo_cls.return_value.get_by_id.return_value = MagicMock(id=7)

        with pytest.raises(PermanentJobError, match="persistent job identity"):
            _render({"bill_id": 42}, ulid="")


def test_handler_dead_letters_when_bill_missing():
    p = _patches()
    with (
        p["engine"] as engine_mock,
        p["bill_repo"] as bill_repo_cls,
        p["billing_repo"],
        p["user_repo"],
        p["org_repo"],
        p["receipt_repo"],
        p["theme_repo"],
        p["storage"],
        p["service_cls"],
    ):
        conn = MagicMock()
        engine_mock.return_value.connect.return_value.__enter__.return_value = conn
        bill_repo = MagicMock()
        bill_repo.get_by_id.return_value = None
        bill_repo_cls.return_value = bill_repo

        with pytest.raises(PermanentJobError, match="bill .* not found"):
            _render({"bill_id": 42})


def test_handler_dead_letters_when_billing_missing():
    p = _patches()
    with (
        p["engine"] as engine_mock,
        p["bill_repo"] as bill_repo_cls,
        p["billing_repo"] as billing_repo_cls,
        p["user_repo"],
        p["org_repo"],
        p["receipt_repo"],
        p["theme_repo"],
        p["storage"],
        p["service_cls"],
    ):
        conn = MagicMock()
        engine_mock.return_value.connect.return_value.__enter__.return_value = conn
        bill = MagicMock(id=42, billing_id=7)
        bill_repo = MagicMock()
        bill_repo.get_by_id.return_value = bill
        bill_repo_cls.return_value = bill_repo
        billing_repo = MagicMock()
        billing_repo.get_by_id.return_value = None
        billing_repo_cls.return_value = billing_repo

        with pytest.raises(PermanentJobError, match="billing .* not found"):
            _render({"bill_id": 42})


def test_handler_translates_pix_not_configured_to_permanent_and_marks_failed():
    from rentivo.services.bill_service import PIX_NOT_CONFIGURED_MESSAGE

    p = _patches()
    with (
        p["engine"] as engine_mock,
        p["bill_repo"] as bill_repo_cls,
        p["billing_repo"] as billing_repo_cls,
        p["user_repo"],
        p["org_repo"],
        p["receipt_repo"],
        p["theme_repo"],
        p["storage"],
        p["service_cls"] as svc_cls,
    ):
        conn = MagicMock()
        engine_mock.return_value.connect.return_value.__enter__.return_value = conn
        bill = MagicMock(id=42, billing_id=7)
        billing = MagicMock(id=7)
        bill_repo = MagicMock()
        bill_repo.get_by_id.return_value = bill
        bill_repo.claim_pending_pdf_render.return_value = True
        bill_repo_cls.return_value = bill_repo
        billing_repo = MagicMock()
        billing_repo.get_by_id.return_value = billing
        billing_repo_cls.return_value = billing_repo

        service = MagicMock()
        service._render_pdf_sync.side_effect = ValueError(PIX_NOT_CONFIGURED_MESSAGE)
        svc_cls.return_value = service

        with pytest.raises(PermanentJobError, match="Configure a chave PIX"):
            _render({"bill_id": 42})

        bill_repo.finish_pdf_render.assert_called_once_with(
            42,
            LEGACY_JOB_ULID,
            "failed",
        )
        bill_repo.update_pdf_render_status.assert_not_called()


def test_handler_pix_failure_only_marks_owned_operation_failed():
    from rentivo.services.bill_service import PIX_NOT_CONFIGURED_MESSAGE

    p = _patches()
    with (
        p["engine"] as engine_mock,
        p["bill_repo"] as bill_repo_cls,
        p["billing_repo"] as billing_repo_cls,
        p["user_repo"],
        p["org_repo"],
        p["receipt_repo"],
        p["theme_repo"],
        p["storage"],
        p["service_cls"] as svc_cls,
    ):
        conn = MagicMock()
        engine_mock.return_value.connect.return_value.__enter__.return_value = conn
        bill = MagicMock(id=42, billing_id=7)
        billing = MagicMock(id=7)
        bill_repo = MagicMock()
        bill_repo.get_by_id.return_value = bill
        bill_repo_cls.return_value = bill_repo
        billing_repo = MagicMock()
        billing_repo.get_by_id.return_value = billing
        billing_repo_cls.return_value = billing_repo
        service = MagicMock()
        service._render_pdf_sync.side_effect = ValueError(PIX_NOT_CONFIGURED_MESSAGE)
        svc_cls.return_value = service

        with pytest.raises(PermanentJobError, match="Configure a chave PIX"):
            _render({"bill_id": 42, "render_operation_id": "01JRENDEROPERATION000000001"})

        bill_repo.finish_pdf_render.assert_called_once_with(
            42,
            "01JRENDEROPERATION000000001",
            "failed",
        )
        bill_repo.update_pdf_render_status.assert_not_called()


def test_handler_propagates_other_exceptions_for_retry():
    p = _patches()
    with (
        p["engine"] as engine_mock,
        p["bill_repo"] as bill_repo_cls,
        p["billing_repo"] as billing_repo_cls,
        p["user_repo"],
        p["org_repo"],
        p["receipt_repo"],
        p["theme_repo"],
        p["storage"],
        p["service_cls"] as svc_cls,
    ):
        conn = MagicMock()
        engine_mock.return_value.connect.return_value.__enter__.return_value = conn
        bill = MagicMock(id=42, billing_id=7)
        billing = MagicMock(id=7)
        bill_repo = MagicMock()
        bill_repo.get_by_id.return_value = bill
        bill_repo.claim_pending_pdf_render.return_value = True
        bill_repo_cls.return_value = bill_repo
        billing_repo = MagicMock()
        billing_repo.get_by_id.return_value = billing
        billing_repo_cls.return_value = billing_repo

        service = MagicMock()
        service._render_pdf_sync.side_effect = RuntimeError("S3 throttled")
        svc_cls.return_value = service

        with pytest.raises(RuntimeError, match="S3 throttled"):
            _render({"bill_id": 42})

        bill_repo.finish_pdf_render.assert_called_once_with(
            42,
            LEGACY_JOB_ULID,
            "pending",
        )


def test_handler_unrelated_value_error_propagates_for_retry():
    """Only the PIX message is permanent. Other ValueErrors retry."""
    p = _patches()
    with (
        p["engine"] as engine_mock,
        p["bill_repo"] as bill_repo_cls,
        p["billing_repo"] as billing_repo_cls,
        p["user_repo"],
        p["org_repo"],
        p["receipt_repo"],
        p["theme_repo"],
        p["storage"],
        p["service_cls"] as svc_cls,
    ):
        conn = MagicMock()
        engine_mock.return_value.connect.return_value.__enter__.return_value = conn
        bill = MagicMock(id=42, billing_id=7)
        billing = MagicMock(id=7)
        bill_repo = MagicMock()
        bill_repo.get_by_id.return_value = bill
        bill_repo_cls.return_value = bill_repo
        billing_repo = MagicMock()
        billing_repo.get_by_id.return_value = billing
        billing_repo_cls.return_value = billing_repo

        service = MagicMock()
        service._render_pdf_sync.side_effect = ValueError("Cannot update pdf_path for bill without an id")
        svc_cls.return_value = service

        with pytest.raises(ValueError, match="pdf_path"):
            _render({"bill_id": 42})


def test_legacy_handler_reclaims_same_operation_after_worker_crash():
    p = _patches()
    with (
        p["engine"] as engine_mock,
        p["bill_repo"] as bill_repo_cls,
        p["billing_repo"] as billing_repo_cls,
        p["user_repo"],
        p["org_repo"],
        p["receipt_repo"],
        p["theme_repo"],
        p["storage"],
        p["service_cls"] as svc_cls,
    ):
        engine_mock.return_value.connect.return_value.__enter__.return_value = MagicMock()
        bill = MagicMock(id=42, billing_id=7)
        billing = MagicMock(id=7)
        bill_repo = bill_repo_cls.return_value
        bill_repo.get_by_id.return_value = bill
        bill_repo.claim_pending_pdf_render.return_value = True
        billing_repo_cls.return_value.get_by_id.return_value = billing
        service = svc_cls.return_value
        service._render_pdf_sync.side_effect = [KeyboardInterrupt(), None]

        payload = {"bill_id": 42}
        with pytest.raises(KeyboardInterrupt):
            _render(payload)
        _render(payload)

        assert [item.args for item in bill_repo.claim_pending_pdf_render.call_args_list] == [
            (42, LEGACY_JOB_ULID),
            (42, LEGACY_JOB_ULID),
        ]
        assert service._render_pdf_sync.call_args_list[0].kwargs["render_operation_id"] == LEGACY_JOB_ULID
        assert service._render_pdf_sync.call_args_list[1].kwargs["render_operation_id"] == LEGACY_JOB_ULID


def test_handler_legacy_success_does_not_use_unconditional_status_update():
    p = _patches()
    with (
        p["engine"] as engine_mock,
        p["bill_repo"] as bill_repo_cls,
        p["billing_repo"] as billing_repo_cls,
        p["user_repo"],
        p["org_repo"],
        p["receipt_repo"],
        p["theme_repo"],
        p["storage"],
        p["service_cls"] as svc_cls,
    ):
        conn = MagicMock()
        engine_mock.return_value.connect.return_value.__enter__.return_value = conn
        bill = MagicMock(id=42, billing_id=7)
        billing = MagicMock(id=7)
        bill_repo = MagicMock()
        bill_repo.get_by_id.return_value = bill
        bill_repo.claim_pending_pdf_render.return_value = True
        bill_repo_cls.return_value = bill_repo
        billing_repo = MagicMock()
        billing_repo.get_by_id.return_value = billing
        billing_repo_cls.return_value = billing_repo

        service = MagicMock()
        svc_cls.return_value = service

        _render({"bill_id": 42})

        service._render_pdf_sync.assert_called_once_with(
            bill,
            billing,
            render_operation_id=LEGACY_JOB_ULID,
        )
        bill_repo.update_pdf_render_status.assert_not_called()


def test_on_pdf_render_failed_only_marks_unowned_legacy_pending_render():
    p = _patches()
    with (
        p["engine"] as engine_mock,
        p["bill_repo"] as bill_repo_cls,
        p["billing_repo"],
        p["user_repo"],
        p["org_repo"],
        p["receipt_repo"],
        p["theme_repo"],
        p["storage"],
        p["service_cls"],
    ):
        conn = MagicMock()
        engine_mock.return_value.connect.return_value.__enter__.return_value = conn
        bill_repo = MagicMock()
        bill_repo_cls.return_value = bill_repo

        _on_pdf_render_failed({"bill_id": 42})

        bill_repo.fail_pending_pdf_render_without_operation.assert_called_once_with(42)
        bill_repo.update_pdf_render_status.assert_not_called()


def test_on_pdf_render_failed_only_marks_owned_operation_failed():
    p = _patches()
    with (
        p["engine"] as engine_mock,
        p["bill_repo"] as bill_repo_cls,
        p["billing_repo"],
        p["user_repo"],
        p["org_repo"],
        p["receipt_repo"],
        p["theme_repo"],
        p["storage"],
        p["service_cls"],
    ):
        conn = MagicMock()
        engine_mock.return_value.connect.return_value.__enter__.return_value = conn
        bill_repo = MagicMock()
        bill_repo_cls.return_value = bill_repo

        _on_pdf_render_failed({"bill_id": 42, "render_operation_id": "01JRENDEROPERATION000000001"})

        bill_repo.finish_pdf_render.assert_called_once_with(
            42,
            "01JRENDEROPERATION000000001",
            "failed",
        )
        bill_repo.update_pdf_render_status.assert_not_called()


def test_on_pdf_render_failed_ignores_missing_bill_id():
    p = _patches()
    with (
        p["engine"] as engine_mock,
        p["bill_repo"],
        p["billing_repo"],
        p["user_repo"],
        p["org_repo"],
        p["receipt_repo"],
        p["theme_repo"],
        p["storage"],
        p["service_cls"],
    ):
        _on_pdf_render_failed({})  # missing bill_id
        _on_pdf_render_failed({"bill_id": "not-int"})

        # Engine should not even be touched on bad payload.
        engine_mock.assert_not_called()


def test_handler_registers_under_pdf_render_key():
    """Importing the module side-effects-registers the handler."""
    from rentivo.jobs import registry
    from rentivo.jobs.handlers import pdf as _  # noqa: F401

    handler = registry.get("pdf.render")
    assert handler is not None
    fail_hook = registry.get_fail_hook("pdf.render")
    assert fail_hook is not None
