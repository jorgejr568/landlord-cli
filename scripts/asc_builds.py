"""App Store Connect build queries for the iOS release workflow.

Usage:
    uv run --quiet --with pyjwt --with cryptography python scripts/asc_builds.py \
        list --bundle-id br.com.rentivo.ios
    uv run --quiet --with pyjwt --with cryptography python scripts/asc_builds.py \
        check --bundle-id br.com.rentivo.ios --version 1.0.2 --build 42
    uv run --quiet --with pyjwt --with cryptography python scripts/asc_builds.py \
        wait --bundle-id br.com.rentivo.ios --version 1.0.2 --build 42

The account is configured with ASC_KEY_ID and ASC_ISSUER_ID; the private key is
read from ~/.appstoreconnect/private_keys/AuthKey_<key id>.p8 and is never
printed. `jwt` is imported lazily so the pure helpers stay importable under the
backend test environment, which does not carry pyjwt.
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

API_ROOT = "https://api.appstoreconnect.apple.com"
FAILED_STATES = frozenset({"FAILED", "INVALID"})
# App Store Connect rejects a bearer token older than ten minutes, and `wait`
# polls for far longer than that, so it re-mints one between polls.
TOKEN_LIFETIME_SECONDS = 600


class AppStoreConnectError(Exception):
    """A failed App Store Connect request.

    `status` is the HTTP status code, or None when the request never produced
    an HTTP response at all (DNS failure, reset connection, timeout).
    """

    def __init__(self, message, status=None):
        super().__init__(message)
        self.status = status


def is_transient_status(status):
    """Return True when a failed request is worth re-polling rather than failing.

    Only `wait` consults this: it runs after an irreversible upload, so dying on
    one bad request would send an operator to re-dispatch and burn a second
    build number for an identical binary. `check` and `list` still fail fast.
    """
    if status is None:
        return True
    if status == 429:
        return True
    return 500 <= status < 600


def normalize_builds(payload):
    """Flatten an ASC /v1/builds response into marketing-version-aware rows.

    ASC calls CFBundleVersion `version` on a build and keeps the marketing
    version on the related preReleaseVersion, so the two have to be joined.
    """
    trains = {
        item["id"]: item.get("attributes", {}).get("version")
        for item in payload.get("included", [])
        if item.get("type") == "preReleaseVersions"
    }
    builds = []
    for item in payload.get("data", []):
        attributes = item.get("attributes", {})
        related = item.get("relationships", {}).get("preReleaseVersion", {}).get("data") or {}
        builds.append(
            {
                "id": item.get("id"),
                "build": attributes.get("version"),
                "version": trains.get(related.get("id")),
                "state": attributes.get("processingState"),
                "uploaded": attributes.get("uploadedDate"),
            }
        )
    return builds


def find_build(builds, version, build_number):
    """Return the row for a marketing version and build number, or None."""
    wanted = str(build_number)
    for build in builds:
        if build["version"] == version and build["build"] == wanted:
            return build
    return None


def classify(state):
    """Reduce a processingState to valid / failed / pending."""
    if state == "VALID":
        return "valid"
    if state in FAILED_STATES:
        return "failed"
    return "pending"


def next_page_path(payload):
    """Return the path+query for the next page of results, or None.

    ASC returns an absolute URL in links.next; `_get` prepends API_ROOT, so the
    scheme and host are stripped here to leave the path+query `_get` expects.
    """
    next_url = payload.get("links", {}).get("next")
    if not next_url:
        return None
    return next_url.removeprefix(API_ROOT)


def _token():
    import jwt

    key_id = os.environ.get("ASC_KEY_ID")
    issuer_id = os.environ.get("ASC_ISSUER_ID")
    if not key_id or not issuer_id:
        sys.exit("ASC_KEY_ID and ASC_ISSUER_ID must be set.")
    key_path = Path.home() / ".appstoreconnect/private_keys" / f"AuthKey_{key_id}.p8"
    if not key_path.exists():
        sys.exit(f"No App Store Connect API key at {key_path}.")
    now = int(time.time())
    return jwt.encode(
        {
            "iss": issuer_id,
            "iat": now,
            "exp": now + TOKEN_LIFETIME_SECONDS,
            "aud": "appstoreconnect-v1",
        },
        key_path.read_text(),
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


def _get(path, bearer):
    """Fetch a JSON document, raising AppStoreConnectError on any failure.

    Raising rather than exiting lets `wait` decide which failures are worth
    re-polling; `main` turns anything that reaches it into a clean exit.
    """
    request = urllib.request.Request(f"{API_ROOT}{path}", headers={"Authorization": f"Bearer {bearer}"})
    try:
        with urllib.request.urlopen(request) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        body = error.read().decode(errors="replace")[:400]
        raise AppStoreConnectError(f"App Store Connect API error {error.code}: {body}", status=error.code) from error
    except urllib.error.URLError as error:
        raise AppStoreConnectError(f"App Store Connect request failed: {error.reason}") from error


def _app_id(bundle_id, bearer):
    apps = _get(f"/v1/apps?filter[bundleId]={bundle_id}", bearer)
    if not apps["data"]:
        sys.exit(f"No App Store Connect app record exists for {bundle_id}.")
    return apps["data"][0]["id"]


def _builds(bundle_id, bearer):
    app_id = _app_id(bundle_id, bearer)
    path = f"/v1/builds?filter[app]={app_id}&include=preReleaseVersion&limit=200"
    builds = []
    while path is not None:
        payload = _get(path, bearer)
        builds.extend(normalize_builds(payload))
        path = next_page_path(payload)
    return builds


def _describe(build):
    return f"{build['version']} ({build['build']}) state={build['state']} uploaded={build['uploaded']}"


def command_list(arguments, bearer):
    builds = _builds(arguments.bundle_id, bearer)
    if not builds:
        print("No builds uploaded yet.")
        return 0
    for build in builds:
        print(f"  {_describe(build)}")
    return 0


def command_check(arguments, bearer):
    builds = _builds(arguments.bundle_id, bearer)
    existing = find_build(builds, arguments.version, arguments.build)
    if existing is None:
        print(f"Build {arguments.version} ({arguments.build}) is free.")
        return 0
    print(
        f"Build {arguments.version} ({arguments.build}) is already consumed: {_describe(existing)}",
        file=sys.stderr,
    )
    return 1


def command_wait(arguments, bearer):
    """Poll until the build reports VALID, its own deadline, or a hard failure.

    This runs after the upload has already consumed the build number, so a
    transient App Store Connect failure must not end the run: it is logged and
    the next poll tries again.
    """
    deadline = time.monotonic() + arguments.timeout
    while True:
        try:
            builds = _builds(arguments.bundle_id, bearer)
        except AppStoreConnectError as error:
            if not is_transient_status(error.status):
                raise
            print(f"  App Store Connect is unavailable, still polling: {error}", file=sys.stderr)
        else:
            build = find_build(builds, arguments.version, arguments.build)
            if build is not None:
                outcome = classify(build["state"])
                print(f"  {_describe(build)}")
                if outcome == "valid":
                    return 0
                if outcome == "failed":
                    print(f"Build processing failed: {build['state']}", file=sys.stderr)
                    return 1
        if time.monotonic() >= deadline:
            print(
                f"Build {arguments.version} ({arguments.build}) did not reach VALID within {arguments.timeout}s.",
                file=sys.stderr,
            )
            return 1
        time.sleep(arguments.interval)
        bearer = _token()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    for name in ("list", "check", "wait"):
        subparser = subparsers.add_parser(name)
        subparser.add_argument("--bundle-id", required=True)
        if name != "list":
            subparser.add_argument("--version", required=True)
            subparser.add_argument("--build", required=True)
        if name == "wait":
            subparser.add_argument("--timeout", type=int, default=1800)
            subparser.add_argument("--interval", type=int, default=30)

    arguments = parser.parse_args(argv)
    handlers = {"list": command_list, "check": command_check, "wait": command_wait}
    try:
        return handlers[arguments.command](arguments, _token())
    except AppStoreConnectError as error:
        sys.exit(str(error))


if __name__ == "__main__":
    raise SystemExit(main())
