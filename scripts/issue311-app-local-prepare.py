#!/usr/bin/env python3
"""R06-06 independent App-bot PREPARE-only original ZIP admission (no publisher)."""
from __future__ import annotations
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

REPO = "pgextwin/pg_repack"
BOT = "pgextwin-issue311-prepare-coord[bot]"
BOT_ID = 350058024
REQUEST_ID = "r-20261030-r06coordlocalpgrepack01"
LEGACY_CENTRAL_REQUEST_ID = "r-20261030-r06preparecoord001"
WORKFLOW = "Issue 311 App-bot original local PREPARE (NO RELEASE)"
OUTPUT = "issue311-app-local-prepare-receipt.json"
SOURCE = Path(".pgextwin-build/scripts/issue311-r06-fleet-local-prepare.py")
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA64 = re.compile(r"^[0-9a-f]{64}$")
CENTRAL_ID = re.compile(r"^r-20[0-9]{6}-r06prepare[a-z0-9-]{4,40}$")
FIELDS = {"request_id", "source_run_id", "source_head_sha",
          "source_artifact_id", "source_zip_sha256", "central_request_id",
          "local_main_sha"}
DERIVED = re.compile(r"r-20[0-9]{6}-r06coordlocal[a-f0-9]{24}\Z")
SOURCE_DATE = re.compile(r"r-(20[0-9]{6})-r06prepare[a-z0-9-]{4,40}\Z")

def derive_local_id(inputs):
    """R10 v1 immutable six-field local ID. Never itself grants App source trust."""
    need(type(inputs) is dict and set(inputs) == FIELDS
         and all(type(v) is str for v in inputs.values()), "noncanonical App inputs")
    central, run = inputs["central_request_id"], inputs["source_run_id"]
    match = SOURCE_DATE.fullmatch(central)
    need(match is not None and run.isdecimal() and run == str(int(run))
         and int(run) > 0 and SHA40.fullmatch(inputs["source_head_sha"])
         and SHA64.fullmatch(inputs["source_zip_sha256"])
         and SHA40.fullmatch(inputs["local_main_sha"]), "invalid original source for ID")
    # Identical to protected build/scripts/issue311-r10-replay-safe-id.py:
    fields = (central, run, inputs["source_head_sha"], inputs["source_zip_sha256"],
              REPO, inputs["local_main_sha"])
    raw = b"pgextwin-r10-local-request-v1\0" + b"\0".join(
        field.encode("ascii") for field in fields)
    result = "r-" + match.group(1) + "-r06coordlocal" + hashlib.sha256(raw).hexdigest()[:24]
    need(DERIVED.fullmatch(result) is not None, "invalid derived request ID")
    return result

class Denied(ValueError):
    pass

def need(ok, message):
    if not ok:
        raise Denied("ISSUE311_APP_LOCAL_DENY " + message)

def unique(pairs):
    obj = {}
    for k, v in pairs:
        need(k not in obj, "duplicate event field")
        obj[k] = v
    return obj

def authenticate_event(event, env):
    need(env.get("GITHUB_REPOSITORY") == REPO
         and env.get("GITHUB_WORKFLOW") == WORKFLOW
         and env.get("GITHUB_EVENT_NAME") == "workflow_dispatch"
         and env.get("GITHUB_REF") == "refs/heads/main"
         and env.get("GITHUB_ACTOR") == BOT
         and env.get("GITHUB_RUN_ATTEMPT") == "1",
         "wrong GitHub workflow origin")
    need(event.get("repository", {}).get("full_name") == REPO
         and event.get("ref") == "refs/heads/main",
         "wrong original event repository/ref")
    sender = event.get("sender", {})
    need(sender.get("id") == BOT_ID and sender.get("login") == BOT
         and sender.get("type") == "Bot", "actual sender App identity changed")
    inputs = event.get("inputs", {})
    need(type(inputs) is dict and set(inputs) == FIELDS,
         "unapproved one-shot source-kind or inputs")
    if inputs.get("request_id") == REQUEST_ID:
        # Historical pilot only; never reinterpret the fixed ID as a fresh source.
        need(inputs.get("central_request_id") == LEGACY_CENTRAL_REQUEST_ID,
             "fixed legacy request may not target a new central source")
    else:
        need(inputs.get("central_request_id") != LEGACY_CENTRAL_REQUEST_ID
             and inputs.get("request_id") == derive_local_id(inputs),
             "new original requires exact replay-safe source-bound local ID")
    need(SHA40.fullmatch(env.get("GITHUB_SHA", "")) is not None
         and inputs.get("local_main_sha") == env["GITHUB_SHA"],
         "local source ref is not pinned to original App event HEAD")
    for key in ("source_run_id", "source_artifact_id"):
        value = inputs.get(key, "")
        need(type(value) is str and value.isdecimal() and int(value) > 0,
             "invalid original source identifier")
    need(SHA40.fullmatch(inputs.get("source_head_sha", "")) is not None
         and SHA64.fullmatch(inputs.get("source_zip_sha256", "")) is not None
         and CENTRAL_ID.fullmatch(inputs.get("central_request_id", "")) is not None,
         "invalid original source digest/central request")
    need(str(env.get("GITHUB_RUN_ID", "")).isdecimal()
         and int(env["GITHUB_RUN_ID"]) > 0, "missing original local Run ID")
    return inputs

def run():
    receipt = {
        "schemaVersion": 1, "requestId": None, "result": "FAILED",
        "sourceKind": "APP_BOT_AUTHENTICATED_ORIGINAL_PREPARE_LOCAL_READONLY_V1",
        "candidateAdmissionAuthorized": False,
        "publisherSourceKindAuthorized": False,
        "publicationAuthorized": False,
        "publicReleaseAuthorized": False, "genuineSchedule": False,
        "runtimeEnabled": False
    }
    try:
        event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_bytes(),
                           object_pairs_hook=unique)
        inputs = authenticate_event(event, os.environ)
        receipt["requestId"] = inputs["request_id"]
        receipt["requestIdBinding"] = ("LEGACY_EXACT_SOURCE" if
            inputs["request_id"] == REQUEST_ID else "R10_SOURCE_BOUND_SHA256_V1")
        head = subprocess.check_output(["git", "rev-parse", "HEAD"],
                                       text=True).strip()
        need(head == os.environ["GITHUB_SHA"], "local checkout/event SHA mismatch")
        need(SOURCE.is_file(), "missing immutable central verifier")
        spec = importlib.util.spec_from_file_location("r06_app_original", SOURCE)
        need(spec is not None and spec.loader is not None, "invalid central verifier")
        gate = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(gate)
        need(gate.REPO == REPO, "central verifier repository mismatch")
        live = gate.remote_branch(REPO)
        need(live.get("name") == "main" and live.get("protected") is True
             and live.get("commit", {}).get("sha") == head,
             "not current exact protected local main")
        source = {
            "sourceRunId": int(inputs["source_run_id"]),
            "sourceHeadSha": inputs["source_head_sha"],
            "sourceArtifactId": int(inputs["source_artifact_id"]),
            "sourceZipSha256": inputs["source_zip_sha256"],
            "centralRequestId": inputs["central_request_id"]
        }
        status, raw_sha, outer_sha = gate.authenticate_original(source, head)
        need(status in ("up-to-date", "update-available")
             and outer_sha == inputs["source_zip_sha256"], "original PREPARE denied")
        receipt.update({
            "result": "NO_UPDATE" if status == "up-to-date" else "UPDATE_PRESENT_NOT_AUTHORIZED",
            "actualBotLogin": BOT, "actualBotUserId": BOT_ID,
            "localOriginalEvent": "workflow_dispatch",
            "localRunId": int(os.environ["GITHUB_RUN_ID"]), "localRunAttempt": 1,
            "localProtectedMainSha": head,
            "centralSourceRunId": source["sourceRunId"],
            "centralSourceHeadSha": source["sourceHeadSha"],
            "centralSourceArtifactId": source["sourceArtifactId"],
            "centralSourceRequestId": source["centralRequestId"],
            "centralSourceRawRequestSha256": raw_sha,
            "centralOriginalOuterZipSha256Verified": outer_sha,
            "originalScanReexecuted": False, "candidateCreated": False
        })
    except Exception as exc:
        receipt["reason"] = str(exc)[:400]
    Path(OUTPUT).write_text(json.dumps(receipt, sort_keys=True, indent=2) + "\n",
                            encoding="utf-8")
    print("ISSUE311_APP_LOCAL_PREPARE_ORIGINAL", json.dumps(receipt, sort_keys=True))
    return 0 if receipt["result"] in ("NO_UPDATE", "UPDATE_PRESENT_NOT_AUTHORIZED") else 1

if __name__ == "__main__":
    raise SystemExit(run())
