#!/usr/bin/env python3
"""Require the exact Codemagic commit to have passed GitHub backend CI."""

import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


DEFAULT_REPOSITORY = "peteratwork/BhargavaFamilyApp"
WORKFLOW_FILE = "backend-tests.yml"
POLL_SECONDS = 30
DEFAULT_TIMEOUT_SECONDS = 20 * 60


def evaluate_runs(runs, commit_sha):
    """Return (state, URL) for the newest workflow run at commit_sha."""
    matching_runs = [run for run in runs if run.get("head_sha") == commit_sha]
    if not matching_runs:
        return "pending", None

    newest = matching_runs[0]
    url = newest.get("html_url")
    if newest.get("status") != "completed":
        return "pending", url
    if newest.get("conclusion") == "success":
        return "success", url
    return "failure", url


def fetch_runs(repository, commit_sha):
    workflow = urllib.parse.quote(WORKFLOW_FILE, safe="")
    query = urllib.parse.urlencode({"head_sha": commit_sha, "per_page": 10})
    url = (
        f"https://api.github.com/repos/{repository}/actions/workflows/"
        f"{workflow}/runs?{query}"
    )
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "BhargavaFamilyApp-Codemagic",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"

    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=20) as response:
        payload = json.load(response)
    return payload.get("workflow_runs", [])


def main():
    repository = os.environ.get("GITHUB_REPOSITORY", DEFAULT_REPOSITORY)
    commit_sha = os.environ.get("CM_COMMIT", "").strip()
    timeout_seconds = int(
        os.environ.get("BACKEND_CI_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS)
    )

    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise SystemExit("GITHUB_REPOSITORY must use owner/repository format")
    if not re.fullmatch(r"[0-9a-fA-F]{40}", commit_sha):
        raise SystemExit("CM_COMMIT must contain the full 40-character commit SHA")
    if timeout_seconds <= 0:
        raise SystemExit("BACKEND_CI_TIMEOUT_SECONDS must be positive")

    deadline = time.monotonic() + timeout_seconds
    last_url = None
    while True:
        try:
            state, run_url = evaluate_runs(fetch_runs(repository, commit_sha), commit_sha)
            last_url = run_url or last_url
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
            state = "pending"
            print(f"GitHub Actions lookup is temporarily unavailable: {error}")

        if state == "success":
            print(f"Backend Tests passed for {commit_sha}: {last_url}")
            return 0
        if state == "failure":
            raise SystemExit(
                f"Backend Tests did not pass for {commit_sha}: {last_url or 'run URL unavailable'}"
            )
        if time.monotonic() >= deadline:
            raise SystemExit(
                f"Timed out waiting for Backend Tests at {commit_sha}: "
                f"{last_url or 'no run found'}"
            )

        print(f"Waiting for Backend Tests at {commit_sha}...")
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    sys.exit(main())
