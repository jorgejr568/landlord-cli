import json

from rentivo.api.errors import ProblemException, problem, problem_response


def test_problem_response_uses_rfc_7807_content_type():
    value = problem(
        status=403,
        code="forbidden",
        title="Acesso negado",
        detail="Você não pode acessar este recurso.",
        fields={"organization_id": "required"},
    )

    response = problem_response(value)

    assert response.status_code == 403
    assert response.media_type == "application/problem+json"
    assert json.loads(response.body) == {
        "type": "https://rentivo.com.br/problems/forbidden",
        "title": "Acesso negado",
        "status": 403,
        "code": "forbidden",
        "detail": "Você não pode acessar este recurso.",
        "fields": {"organization_id": "required"},
        "request_id": "",
    }


def test_not_found_problem_exception_has_stable_problem_shape():
    error = ProblemException.not_found()

    assert error.problem.status == 404
    assert error.problem.code == "not_found"
    assert error.problem.fields == {}


def test_conflict_problem_exception_carries_the_pt_br_title_and_detail():
    error = ProblemException.conflict("recibo_not_ready", "O recibo ainda está sendo gerado.")

    assert error.problem.status == 409
    assert error.problem.code == "recibo_not_ready"
    assert error.problem.title == "Conflito"
    assert error.problem.detail == "O recibo ainda está sendo gerado."
    assert error.problem.fields == {}


def test_invalid_problem_exception_keeps_the_supplied_fields():
    error = ProblemException.invalid(
        "validation_error",
        "Os dados da fatura são inválidos.",
        fields={"reference_month": "obrigatório"},
    )

    assert error.problem.status == 422
    assert error.problem.title == "Dados inválidos"
    assert error.problem.fields == {"reference_month": "obrigatório"}


def test_invalid_field_problem_exception_mirrors_the_detail_into_the_field():
    error = ProblemException.invalid_field("invalid_billing", "Chave PIX inválida.", "pix_key")

    assert error.problem.status == 422
    assert error.problem.code == "invalid_billing"
    assert error.problem.detail == "Chave PIX inválida."
    assert error.problem.fields == {"pix_key": "Chave PIX inválida."}
