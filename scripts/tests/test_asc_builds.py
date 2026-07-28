import asc_builds

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
