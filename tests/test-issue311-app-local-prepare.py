#!/usr/bin/env python3
"""Negative auth/source-kind tests, no external dispatch or tokens."""
import copy
import importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location(
    "app_local", Path("scripts/issue311-app-local-prepare.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
env = {
    "GITHUB_REPOSITORY": m.REPO, "GITHUB_WORKFLOW": m.WORKFLOW,
    "GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REF": "refs/heads/main",
    "GITHUB_ACTOR": m.BOT, "GITHUB_RUN_ATTEMPT": "1",
    "GITHUB_SHA": "a" * 40, "GITHUB_RUN_ID": "1234"
}
ev = {
    "repository": {"full_name": m.REPO}, "ref": "refs/heads/main",
    "sender": {"login": m.BOT, "id": m.BOT_ID, "type": "Bot"},
    "inputs": {
        "request_id": m.REQUEST_ID, "source_run_id": "123",
        "source_head_sha": "b" * 40, "source_artifact_id": "456",
        "source_zip_sha256": "c" * 64,
        "central_request_id": "r-20261030-r06preparecoord001",
        "local_main_sha": "a" * 40
    }
}
assert m.authenticate_event(ev, env)["source_run_id"] == "123"
def reject(event, context):
    try:
        m.authenticate_event(event, context)
    except m.Denied:
        return
    raise AssertionError("unsafe App event/source accepted")
for key, value in (
    ("GITHUB_ACTOR", "ShutenOishi"),
    ("GITHUB_REPOSITORY", "pgextwin/build"),
    ("GITHUB_WORKFLOW", "Issue 311 unrelated"),
    ("GITHUB_EVENT_NAME", "push"),
    ("GITHUB_REF", "refs/tags/v1"),
    ("GITHUB_RUN_ATTEMPT", "2"),
    ("GITHUB_SHA", "d" * 40),
):
    reject(ev, dict(env, **{key: value}))
for key, value in (
    ("sender", {"login": m.BOT, "id": 1, "type": "Bot"}),
    ("repository", {"full_name": "evil/repo"}),
    ("ref", "refs/heads/dev"),
):
    bad = copy.deepcopy(ev)
    bad[key] = value
    reject(bad, env)
for key, value in (
    ("request_id", "r-20261030-r06coordactorpilot01"),
    ("source_run_id", "0"),
    ("source_artifact_id", "abc"),
    ("source_zip_sha256", "f" * 63),
    ("source_head_sha", "f" * 39),
    ("central_request_id", "r-20261029-fake"),
    ("local_main_sha", "f" * 40),
    ("mode", "PUBLISH"),
):
    bad = copy.deepcopy(ev)
    bad["inputs"][key] = value
    reject(bad, env)
body = Path("scripts/issue311-app-local-prepare.py").read_text()
for required in ("authenticate_original(", "remote_branch(", "centralOriginalOuterZipSha256Verified",
                 "publisherSourceKindAuthorized", "candidateAdmissionAuthorized"):
    assert required in body
assert "release create" not in body and "git push" not in body
print("ISSUE311_APP_BOT_LOCAL_PREPARE_NEGATIVE_TESTS_PASS")
