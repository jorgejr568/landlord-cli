import argparse

import asc_builds
import pytest

PAYLOAD = {
    "data": [
        {
            "id": "build-a",
            "attributes": {
                "version": "42",
                "processingState": "VALID",
                "uploadedDate": "2026-07-28T10:00:00-07:00",
            },
            "relationships": {"preReleaseVersion": {"data": {"id": "train-1", "type": "preReleaseVersions"}}},
        },
        {
            "id": "build-b",
            "attributes": {
                "version": "43",
                "processingState": "PROCESSING",
                "uploadedDate": "2026-07-28T11:00:00-07:00",
            },
            "relationships": {"preReleaseVersion": {"data": {"id": "train-2", "type": "preReleaseVersions"}}},
        },
        {
            "id": "build-orphan",
            "attributes": {"version": "44", "processingState": "VALID"},
        },
    ],
    "included": [
        {"id": "train-1", "type": "preReleaseVersions", "attributes": {"version": "1.0.1"}},
        {"id": "train-2", "type": "preReleaseVersions", "attributes": {"version": "1.0.2"}},
        {"id": "app-1", "type": "apps", "attributes": {"name": "Rentivo"}},
    ],
}


def test_normalize_builds_joins_the_marketing_version_train():
    builds = asc_builds.normalize_builds(PAYLOAD)

    assert builds[0] == {
        "id": "build-a",
        "build": "42",
        "version": "1.0.1",
        "state": "VALID",
        "uploaded": "2026-07-28T10:00:00-07:00",
    }
    assert builds[1]["version"] == "1.0.2"
    assert builds[1]["state"] == "PROCESSING"


def test_normalize_builds_tolerates_a_missing_train_relationship():
    builds = asc_builds.normalize_builds(PAYLOAD)

    assert builds[2] == {
        "id": "build-orphan",
        "build": "44",
        "version": None,
        "state": "VALID",
        "uploaded": None,
    }


def test_normalize_builds_handles_an_empty_payload():
    assert asc_builds.normalize_builds({}) == []


def test_find_build_matches_on_marketing_version_and_build_number():
    builds = asc_builds.normalize_builds(PAYLOAD)

    assert asc_builds.find_build(builds, "1.0.1", 42)["id"] == "build-a"
    assert asc_builds.find_build(builds, "1.0.1", "42")["id"] == "build-a"


def test_find_build_returns_none_when_either_half_differs():
    builds = asc_builds.normalize_builds(PAYLOAD)

    assert asc_builds.find_build(builds, "1.0.2", 42) is None
    assert asc_builds.find_build(builds, "1.0.1", 43) is None
    assert asc_builds.find_build(builds, "9.9.9", 1) is None


def test_classify_maps_processing_states_to_outcomes():
    assert asc_builds.classify("VALID") == "valid"
    assert asc_builds.classify("FAILED") == "failed"
    assert asc_builds.classify("INVALID") == "failed"
    assert asc_builds.classify("PROCESSING") == "pending"
    assert asc_builds.classify(None) == "pending"


def test_next_page_path_strips_the_scheme_and_host_from_an_absolute_url():
    payload = {
        "links": {"next": "https://api.appstoreconnect.apple.com/v1/builds?filter[app]=app-1&limit=200&cursor=abc123"}
    }

    assert asc_builds.next_page_path(payload) == "/v1/builds?filter[app]=app-1&limit=200&cursor=abc123"


def test_next_page_path_returns_none_without_a_links_key():
    assert asc_builds.next_page_path({}) is None


def test_next_page_path_returns_none_without_a_next_key():
    assert asc_builds.next_page_path({"links": {"self": "https://example.com/v1/builds"}}) is None


def test_is_transient_status_retries_network_failures_throttling_and_server_errors():
    assert asc_builds.is_transient_status(None) is True
    assert asc_builds.is_transient_status(429) is True
    assert asc_builds.is_transient_status(500) is True
    assert asc_builds.is_transient_status(503) is True


def test_is_transient_status_fails_fast_on_everything_else():
    assert asc_builds.is_transient_status(400) is False
    assert asc_builds.is_transient_status(401) is False
    assert asc_builds.is_transient_status(403) is False
    assert asc_builds.is_transient_status(404) is False
    assert asc_builds.is_transient_status(200) is False


def _wait_arguments(timeout=120):
    return argparse.Namespace(
        bundle_id="br.com.rentivo.ios",
        version="1.0.2",
        build="42",
        timeout=timeout,
        interval=0,
    )


VALID_BUILD = {"id": "build-a", "build": "42", "version": "1.0.2", "state": "VALID", "uploaded": None}


def test_command_wait_keeps_polling_through_a_transient_failure(monkeypatch):
    tokens = []

    def fake_builds(bundle_id, bearer):
        tokens.append(bearer)
        if len(tokens) == 1:
            raise asc_builds.AppStoreConnectError("App Store Connect request failed: connection reset")
        return [VALID_BUILD]

    monkeypatch.setattr(asc_builds, "_builds", fake_builds)
    monkeypatch.setattr(asc_builds, "_token", lambda: "refreshed")

    assert asc_builds.command_wait(_wait_arguments(), "initial") == 0
    # The second poll also proves the bearer is re-minted: the original expires
    # in ten minutes and the wait runs for thirty.
    assert tokens == ["initial", "refreshed"]


def test_command_wait_fails_fast_on_a_non_transient_error(monkeypatch):
    def fake_builds(bundle_id, bearer):
        raise asc_builds.AppStoreConnectError("App Store Connect API error 401: bad token", status=401)

    monkeypatch.setattr(asc_builds, "_builds", fake_builds)
    monkeypatch.setattr(asc_builds, "_token", lambda: "refreshed")

    with pytest.raises(asc_builds.AppStoreConnectError):
        asc_builds.command_wait(_wait_arguments(), "initial")


GROUPS = [
    {"id": "group-internal", "attributes": {"name": "RentivoTestGroup", "isInternalGroup": True}},
    {"id": "group-external", "attributes": {"name": "Beta Publico", "isInternalGroup": False}},
]


def test_select_beta_group_matches_an_explicit_name():
    group, reason = asc_builds.select_beta_group(GROUPS, "Beta Publico")

    assert group["id"] == "group-external"
    assert reason is None


def test_select_beta_group_reports_the_available_names_when_the_requested_one_is_absent():
    group, reason = asc_builds.select_beta_group(GROUPS, "Missing")

    assert group is None
    assert "Beta Publico, RentivoTestGroup" in reason


def test_select_beta_group_derives_the_single_internal_group():
    group, reason = asc_builds.select_beta_group(GROUPS)

    assert group["id"] == "group-internal"
    assert reason is None


def test_select_beta_group_refuses_to_guess_between_internal_groups():
    groups = GROUPS + [{"id": "group-other", "attributes": {"name": "Interno 2", "isInternalGroup": True}}]

    group, reason = asc_builds.select_beta_group(groups)

    assert group is None
    assert "2 internal beta groups" in reason


def test_select_beta_group_reports_an_app_with_no_internal_group():
    group, reason = asc_builds.select_beta_group([GROUPS[1]])

    assert group is None
    assert "no internal beta group" in reason


def test_is_pending_association_status_retries_the_not_yet_materialized_404():
    # A build ASC returns from /v1/builds but 404s as a relationship target is
    # still being wired up on the TestFlight side, not permanently missing.
    assert asc_builds.is_pending_association_status(404) is True
    assert asc_builds.is_pending_association_status(503) is True
    assert asc_builds.is_pending_association_status(None) is True
    assert asc_builds.is_pending_association_status(401) is False


def _distribute_arguments(timeout=120, group=None):
    return argparse.Namespace(
        bundle_id="br.com.rentivo.ios",
        version="1.0.2",
        build="42",
        timeout=timeout,
        interval=0,
        group=group,
    )


def _fake_get(assigned_builds):
    def fake_get(path, bearer):
        if "/betaGroups?" in path:
            return {"data": GROUPS}
        if "/builds?" in path:
            return {"data": assigned_builds}
        raise AssertionError(f"unexpected GET {path}")

    return fake_get


def _patch_distribute(monkeypatch, assigned_builds):
    monkeypatch.setattr(asc_builds, "_app_id", lambda bundle_id, bearer: "app-1")
    monkeypatch.setattr(asc_builds, "_get", _fake_get(assigned_builds))
    monkeypatch.setattr(asc_builds, "_builds", lambda bundle_id, bearer: [VALID_BUILD])
    monkeypatch.setattr(asc_builds, "_token", lambda: "refreshed")


def test_command_distribute_attaches_the_build_to_the_derived_group(monkeypatch):
    posted = []
    _patch_distribute(monkeypatch, assigned_builds=[])
    monkeypatch.setattr(asc_builds, "_post", lambda path, document, bearer: posted.append((path, document)))

    assert asc_builds.command_distribute(_distribute_arguments(), "initial") == 0
    assert posted == [
        (
            "/v1/betaGroups/group-internal/relationships/builds",
            {"data": [{"type": "builds", "id": "build-a"}]},
        )
    ]


def test_command_distribute_is_idempotent_when_the_build_is_already_in_the_group(monkeypatch):
    _patch_distribute(monkeypatch, assigned_builds=[{"id": "build-a"}])

    def refuse(path, document, bearer):
        raise AssertionError("must not re-post an existing association")

    monkeypatch.setattr(asc_builds, "_post", refuse)

    assert asc_builds.command_distribute(_distribute_arguments(), "initial") == 0


def test_command_distribute_retries_while_testflight_still_404s_the_build(monkeypatch):
    attempts = []
    _patch_distribute(monkeypatch, assigned_builds=[])

    def flaky_post(path, document, bearer):
        attempts.append(bearer)
        if len(attempts) == 1:
            raise asc_builds.AppStoreConnectError("App Store Connect API error 404: NOT_FOUND", status=404)
        return 204

    monkeypatch.setattr(asc_builds, "_post", flaky_post)

    assert asc_builds.command_distribute(_distribute_arguments(), "initial") == 0
    assert attempts == ["initial", "refreshed"]


def test_command_distribute_fails_fast_on_a_non_retryable_error(monkeypatch):
    _patch_distribute(monkeypatch, assigned_builds=[])

    def unauthorized(path, document, bearer):
        raise asc_builds.AppStoreConnectError("App Store Connect API error 401: bad token", status=401)

    monkeypatch.setattr(asc_builds, "_post", unauthorized)

    with pytest.raises(asc_builds.AppStoreConnectError):
        asc_builds.command_distribute(_distribute_arguments(), "initial")


def test_command_distribute_stops_at_its_deadline(monkeypatch):
    _patch_distribute(monkeypatch, assigned_builds=[])

    def always_404(path, document, bearer):
        raise asc_builds.AppStoreConnectError("App Store Connect API error 404: NOT_FOUND", status=404)

    monkeypatch.setattr(asc_builds, "_post", always_404)

    assert asc_builds.command_distribute(_distribute_arguments(timeout=0), "initial") == 1


def test_command_distribute_reports_an_unresolvable_group_without_polling(monkeypatch):
    _patch_distribute(monkeypatch, assigned_builds=[])

    def refuse(bundle_id, bearer):
        raise AssertionError("must not poll for a build it can never place")

    monkeypatch.setattr(asc_builds, "_builds", refuse)

    assert asc_builds.command_distribute(_distribute_arguments(group="Missing"), "initial") == 1


def test_command_wait_stops_at_its_deadline_when_the_api_stays_unavailable(monkeypatch):
    calls = []

    def fake_builds(bundle_id, bearer):
        calls.append(bearer)
        raise asc_builds.AppStoreConnectError("App Store Connect API error 503: unavailable", status=503)

    monkeypatch.setattr(asc_builds, "_builds", fake_builds)
    monkeypatch.setattr(asc_builds, "_token", lambda: "refreshed")

    assert asc_builds.command_wait(_wait_arguments(timeout=0), "initial") == 1
    assert calls == ["initial"]
