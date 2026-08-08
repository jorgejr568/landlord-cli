from unittest.mock import MagicMock, patch

from rentivo.models.bill import Bill, BillLineItem, BillStatus
from rentivo.models.billing import Billing, BillingItem, ItemType


class TestRegenerateRecibos:
    def _make_billing(self):
        return Billing(
            id=1,
            uuid="billing-uuid",
            name="Apt 101",
            items=[BillingItem(description="Rent", amount=100000, item_type=ItemType.FIXED)],
        )

    def _make_bill(self, status=BillStatus.PAID.value, recibo_pdf_path=None):
        return Bill(
            id=1,
            uuid="bill-uuid",
            billing_id=1,
            reference_month="2025-03",
            total_amount=100000,
            status=status,
            pdf_path="bills/billing-uuid/bill-uuid.pdf",
            recibo_pdf_path=recibo_pdf_path,
            line_items=[
                BillLineItem(description="Rent", amount=100000, item_type=ItemType.FIXED, sort_order=0),
            ],
        )

    @patch("rentivo.scripts._cli.initialize_db")
    @patch("rentivo.scripts.regenerate_recibos.get_billing_repository")
    @patch("rentivo.scripts.regenerate_recibos.get_bill_repository")
    @patch("rentivo.scripts.regenerate_recibos.get_audit_log_repository")
    @patch("rentivo.scripts.regenerate_recibos.get_job_repository")
    @patch("rentivo.scripts._cli.get_connection")
    @patch("rentivo.scripts.regenerate_recibos.get_job_backend")
    def test_dry_run(
        self,
        mock_job_backend,
        mock_get_connection,
        mock_job_repo,
        mock_audit_repo,
        mock_bill_repo,
        mock_billing_repo,
        mock_init_db,
    ):
        from rentivo.scripts.regenerate_recibos import main

        mock_billing_repo.return_value.list_all.return_value = [self._make_billing()]
        mock_bill_repo.return_value.list_by_billing.return_value = [self._make_bill()]

        with patch("sys.argv", ["prog", "--dry-run"]):
            main()

        mock_job_backend.return_value.enqueue.assert_not_called()

    @patch("rentivo.scripts._cli.initialize_db")
    @patch("rentivo.scripts.regenerate_recibos.get_billing_repository")
    @patch("rentivo.scripts.regenerate_recibos.get_bill_repository")
    @patch("rentivo.scripts.regenerate_recibos.get_audit_log_repository")
    @patch("rentivo.scripts.regenerate_recibos.get_job_repository")
    @patch("rentivo.scripts._cli.get_connection")
    @patch("rentivo.scripts.regenerate_recibos.get_job_backend")
    def test_enqueues_one_job_per_paid_bill(
        self,
        mock_job_backend,
        mock_get_connection,
        mock_job_repo,
        mock_audit_repo,
        mock_bill_repo,
        mock_billing_repo,
        mock_init_db,
    ):
        from rentivo.jobs.base import Job
        from rentivo.scripts.regenerate_recibos import main

        billing = self._make_billing()
        bill = self._make_bill()
        mock_billing_repo.return_value.list_all.return_value = [billing]
        mock_bill_repo.return_value.list_by_billing.return_value = [bill]
        mock_job_backend.return_value.enqueue.return_value = Job(
            id=1,
            ulid="01HXYZ",
            job_type="recibo.render",
            payload={"bill_id": 1},
            attempts=0,
            max_attempts=3,
        )
        mock_job_repo.return_value.count_by_type_and_statuses.return_value = 1

        operation_id = "01ARZ3NDEKTSV4RRFFQ69G5FAW"
        with (
            patch("sys.argv", ["prog"]),
            patch("rentivo.scripts.regenerate_recibos.ULID", return_value=operation_id),
        ):
            main()

        assert mock_job_backend.return_value.enqueue.call_count == 1
        call_args = mock_job_backend.return_value.enqueue.call_args
        assert call_args.args[0] == "recibo.render"
        # The script mints its own render operation id, like every other
        # recibo.render producer. Omitting it would push the handler onto the
        # legacy "_job_ulid" fallback.
        assert call_args.args[1] == {"bill_id": 1, "render_operation_id": operation_id}

        # The script's payload must be accepted by the real handler contract
        # without taking the legacy identity path.
        with (
            patch("rentivo.jobs.handlers.recibo.get_engine") as engine,
            patch("rentivo.jobs.handlers.recibo.SQLAlchemyBillRepository") as handler_bill_repo_cls,
            patch("rentivo.jobs.handlers.recibo.SQLAlchemyBillingRepository") as handler_billing_repo_cls,
            patch("rentivo.jobs.handlers.recibo.SQLAlchemyUserRepository"),
            patch("rentivo.jobs.handlers.recibo.SQLAlchemyOrganizationRepository"),
            patch("rentivo.jobs.handlers.recibo.SQLAlchemyThemeRepository"),
            patch("rentivo.jobs.handlers.recibo.get_storage"),
            patch("rentivo.jobs.handlers.recibo.BillService") as service_cls,
        ):
            engine.return_value.connect.return_value.__enter__.return_value = MagicMock()
            handler_bill_repo_cls.return_value.get_by_id.return_value = bill
            handler_billing_repo_cls.return_value.get_by_id.return_value = billing

            from rentivo.jobs.handlers.recibo import handle_recibo_render

            handle_recibo_render(call_args.args[1])

        service_cls.return_value.store_recibo.assert_called_once_with(
            bill,
            billing,
            render_operation_id=operation_id,
        )

    @patch("rentivo.scripts._cli.initialize_db")
    @patch("rentivo.scripts.regenerate_recibos.get_billing_repository")
    @patch("rentivo.scripts.regenerate_recibos.get_bill_repository")
    @patch("rentivo.scripts.regenerate_recibos.get_audit_log_repository")
    @patch("rentivo.scripts.regenerate_recibos.get_job_repository")
    @patch("rentivo.scripts._cli.get_connection")
    @patch("rentivo.scripts.regenerate_recibos.get_job_backend")
    def test_no_billings(
        self,
        mock_job_backend,
        mock_get_connection,
        mock_job_repo,
        mock_audit_repo,
        mock_bill_repo,
        mock_billing_repo,
        mock_init_db,
    ):
        from rentivo.scripts.regenerate_recibos import main

        mock_billing_repo.return_value.list_all.return_value = []

        with patch("sys.argv", ["prog"]):
            main()

        mock_job_backend.return_value.enqueue.assert_not_called()

    @patch("rentivo.scripts._cli.initialize_db")
    @patch("rentivo.scripts.regenerate_recibos.get_billing_repository")
    @patch("rentivo.scripts.regenerate_recibos.get_bill_repository")
    @patch("rentivo.scripts.regenerate_recibos.get_audit_log_repository")
    @patch("rentivo.scripts.regenerate_recibos.get_job_repository")
    @patch("rentivo.scripts._cli.get_connection")
    @patch("rentivo.scripts.regenerate_recibos.get_job_backend")
    def test_no_paid_bills_when_billing_has_no_bills(
        self,
        mock_job_backend,
        mock_get_connection,
        mock_job_repo,
        mock_audit_repo,
        mock_bill_repo,
        mock_billing_repo,
        mock_init_db,
    ):
        from rentivo.scripts.regenerate_recibos import main

        mock_billing_repo.return_value.list_all.return_value = [self._make_billing()]
        mock_bill_repo.return_value.list_by_billing.return_value = []

        with patch("sys.argv", ["prog"]):
            main()

        mock_job_backend.return_value.enqueue.assert_not_called()

    @patch("rentivo.scripts._cli.initialize_db")
    @patch("rentivo.scripts.regenerate_recibos.get_billing_repository")
    @patch("rentivo.scripts.regenerate_recibos.get_bill_repository")
    @patch("rentivo.scripts.regenerate_recibos.get_audit_log_repository")
    @patch("rentivo.scripts.regenerate_recibos.get_job_repository")
    @patch("rentivo.scripts._cli.get_connection")
    @patch("rentivo.scripts.regenerate_recibos.get_job_backend")
    def test_skips_non_paid_bills(
        self,
        mock_job_backend,
        mock_get_connection,
        mock_job_repo,
        mock_audit_repo,
        mock_bill_repo,
        mock_billing_repo,
        mock_init_db,
    ):
        """Only PAID bills get a recibo — unpaid bills must be ignored."""
        from rentivo.scripts.regenerate_recibos import main

        mock_billing_repo.return_value.list_all.return_value = [self._make_billing()]
        mock_bill_repo.return_value.list_by_billing.return_value = [
            self._make_bill(status=BillStatus.PUBLISHED.value),
        ]

        with patch("sys.argv", ["prog"]):
            main()

        mock_job_backend.return_value.enqueue.assert_not_called()

    @patch("rentivo.scripts._cli.initialize_db")
    @patch("rentivo.scripts.regenerate_recibos.get_billing_repository")
    @patch("rentivo.scripts.regenerate_recibos.get_bill_repository")
    @patch("rentivo.scripts.regenerate_recibos.get_audit_log_repository")
    @patch("rentivo.scripts.regenerate_recibos.get_job_repository")
    @patch("rentivo.scripts._cli.get_connection")
    @patch("rentivo.scripts.regenerate_recibos.get_job_backend")
    def test_summary_reports_pending_running_count_and_stored_status(
        self,
        mock_job_backend,
        mock_get_connection,
        mock_job_repo,
        mock_audit_repo,
        mock_bill_repo,
        mock_billing_repo,
        mock_init_db,
        capsys,
    ):
        from rentivo.jobs.base import Job
        from rentivo.scripts.regenerate_recibos import main

        mock_billing_repo.return_value.list_all.return_value = [self._make_billing()]
        # A paid bill that already has a stored recibo — exercises the "armazenado" row.
        mock_bill_repo.return_value.list_by_billing.return_value = [
            self._make_bill(recibo_pdf_path="bills/billing-uuid/bill-uuid.recibo.pdf"),
        ]
        mock_job_backend.return_value.enqueue.return_value = Job(
            id=1,
            ulid="01HXYZ",
            job_type="recibo.render",
            payload={"bill_id": 1},
            attempts=0,
            max_attempts=3,
        )
        mock_job_repo.return_value.count_by_type_and_statuses.return_value = 7

        with patch("sys.argv", ["prog"]):
            main()

        mock_job_repo.return_value.count_by_type_and_statuses.assert_called_once_with(
            "recibo.render", ("pending", "running")
        )
        assert "7" in capsys.readouterr().out
