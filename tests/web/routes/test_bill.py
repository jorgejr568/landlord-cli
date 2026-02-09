from unittest.mock import patch

from landlord.storage.local import LocalStorage
from tests.web.conftest import create_billing_in_db, generate_bill_in_db


class TestBillGenerate:
    def test_generate_form(self, auth_client, test_engine):
        billing = create_billing_in_db(test_engine)
        response = auth_client.get(f"/bills/{billing.uuid}/generate")
        assert response.status_code == 200

    def test_generate_form_not_found(self, auth_client):
        response = auth_client.get("/bills/nonexistent/generate", follow_redirects=False)
        assert response.status_code == 302

    def test_generate_success(self, auth_client, test_engine, tmp_path, csrf_token):
        billing = create_billing_in_db(test_engine)
        with patch("web.deps.get_storage", return_value=LocalStorage(str(tmp_path))):
            response = auth_client.post(
                f"/bills/{billing.uuid}/generate",
                data={
                    "csrf_token": csrf_token,
                    "reference_month": "2025-03",
                    "due_date": "10/04/2025",
                    "notes": "test",
                    "extras-TOTAL_FORMS": "0",
                },
                follow_redirects=False,
            )
        assert response.status_code == 302

    def test_generate_no_reference(self, auth_client, test_engine, csrf_token):
        billing = create_billing_in_db(test_engine)
        response = auth_client.post(
            f"/bills/{billing.uuid}/generate",
            data={
                "csrf_token": csrf_token,
                "reference_month": "",
                "extras-TOTAL_FORMS": "0",
            },
            follow_redirects=False,
        )
        assert response.status_code == 302

    def test_generate_billing_not_found(self, auth_client, csrf_token):
        response = auth_client.post(
            "/bills/nonexistent/generate",
            data={"csrf_token": csrf_token, "reference_month": "2025-03", "extras-TOTAL_FORMS": "0"},
            follow_redirects=False,
        )
        assert response.status_code == 302


class TestBillDetail:
    def test_detail(self, auth_client, test_engine, tmp_path):
        billing = create_billing_in_db(test_engine)
        with patch("web.deps.get_storage", return_value=LocalStorage(str(tmp_path))):
            bill = generate_bill_in_db(test_engine, billing, tmp_path)
            response = auth_client.get(f"/bills/{bill.uuid}")
        assert response.status_code == 200

    def test_detail_not_found(self, auth_client):
        response = auth_client.get("/bills/nonexistent", follow_redirects=False)
        assert response.status_code == 302


class TestBillEdit:
    def test_edit_form(self, auth_client, test_engine, tmp_path):
        billing = create_billing_in_db(test_engine)
        with patch("web.deps.get_storage", return_value=LocalStorage(str(tmp_path))):
            bill = generate_bill_in_db(test_engine, billing, tmp_path)
            response = auth_client.get(f"/bills/{bill.uuid}/edit")
        assert response.status_code == 200

    def test_edit_form_not_found(self, auth_client):
        response = auth_client.get("/bills/nonexistent/edit", follow_redirects=False)
        assert response.status_code == 302

    def test_edit_submit(self, auth_client, test_engine, tmp_path, csrf_token):
        billing = create_billing_in_db(test_engine)
        with patch("web.deps.get_storage", return_value=LocalStorage(str(tmp_path))):
            bill = generate_bill_in_db(test_engine, billing, tmp_path)
            response = auth_client.post(
                f"/bills/{bill.uuid}/edit",
                data={
                    "csrf_token": csrf_token,
                    "due_date": "15/04/2025",
                    "notes": "updated",
                    "items-TOTAL_FORMS": "1",
                    "items-0-description": "Aluguel",
                    "items-0-amount": "285000",
                    "items-0-item_type": "fixed",
                    "extras-TOTAL_FORMS": "0",
                },
                follow_redirects=False,
            )
        assert response.status_code == 302

    def test_edit_not_found(self, auth_client, csrf_token):
        response = auth_client.post(
            "/bills/nonexistent/edit",
            data={"csrf_token": csrf_token, "items-TOTAL_FORMS": "0", "extras-TOTAL_FORMS": "0"},
            follow_redirects=False,
        )
        assert response.status_code == 302


class TestBillRegeneratePdf:
    def test_regenerate(self, auth_client, test_engine, tmp_path, csrf_token):
        billing = create_billing_in_db(test_engine)
        with patch("web.deps.get_storage", return_value=LocalStorage(str(tmp_path))):
            bill = generate_bill_in_db(test_engine, billing, tmp_path)
            response = auth_client.post(
                f"/bills/{bill.uuid}/regenerate-pdf",
                data={"csrf_token": csrf_token},
                follow_redirects=False,
            )
        assert response.status_code == 302

    def test_regenerate_not_found(self, auth_client, csrf_token):
        response = auth_client.post(
            "/bills/nonexistent/regenerate-pdf",
            data={"csrf_token": csrf_token},
            follow_redirects=False,
        )
        assert response.status_code == 302


class TestBillTogglePaid:
    def test_toggle_paid(self, auth_client, test_engine, tmp_path, csrf_token):
        billing = create_billing_in_db(test_engine)
        with patch("web.deps.get_storage", return_value=LocalStorage(str(tmp_path))):
            bill = generate_bill_in_db(test_engine, billing, tmp_path)
            response = auth_client.post(
                f"/bills/{bill.uuid}/toggle-paid",
                data={"csrf_token": csrf_token},
                follow_redirects=False,
            )
        assert response.status_code == 302

    def test_toggle_paid_not_found(self, auth_client, csrf_token):
        response = auth_client.post(
            "/bills/nonexistent/toggle-paid",
            data={"csrf_token": csrf_token},
            follow_redirects=False,
        )
        assert response.status_code == 302


class TestBillDelete:
    def test_delete(self, auth_client, test_engine, tmp_path, csrf_token):
        billing = create_billing_in_db(test_engine)
        with patch("web.deps.get_storage", return_value=LocalStorage(str(tmp_path))):
            bill = generate_bill_in_db(test_engine, billing, tmp_path)
            response = auth_client.post(
                f"/bills/{bill.uuid}/delete",
                data={"csrf_token": csrf_token},
                follow_redirects=False,
            )
        assert response.status_code == 302

    def test_delete_not_found(self, auth_client, csrf_token):
        response = auth_client.post(
            "/bills/nonexistent/delete",
            data={"csrf_token": csrf_token},
            follow_redirects=False,
        )
        assert response.status_code == 302


class TestBillInvoice:
    def test_invoice_local_file(self, auth_client, test_engine, tmp_path):
        billing = create_billing_in_db(test_engine)
        with patch("web.deps.get_storage", return_value=LocalStorage(str(tmp_path))):
            bill = generate_bill_in_db(test_engine, billing, tmp_path)
            response = auth_client.get(
                f"/bills/{bill.uuid}/invoice",
                follow_redirects=False,
            )
        assert response.status_code == 200
        assert response.headers.get("content-type", "").startswith("application/pdf")

    def test_invoice_not_found(self, auth_client):
        response = auth_client.get(
            "/bills/nonexistent/invoice",
            follow_redirects=False,
        )
        assert response.status_code == 302
