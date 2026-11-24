#!/usr/bin/env python3
"""Audit Firebase callable invocation policies without invoking business handlers.

Read-only by default. --repair-public-callables restores the public transport
policy only for Firebase-labelled callables explicitly declared public in source.
Application authentication/App Check are unchanged. Scheduled/event services are
never made public. Requires an authorized gcloud session and Python's stdlib.
"""

import argparse
import concurrent.futures
import json
import pathlib
import re
import subprocess
import urllib.error
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--repair-public-callables", action="store_true")
    parser.add_argument("--probe", action="store_true", help="Also run sequential, non-mutating HTTP checks (warms services)")
    args = parser.parse_args()
    output = pathlib.Path(args.output)
    output.mkdir(parents=True, exist_ok=True)

    def gcloud(*arguments):
        result = subprocess.run(
            ["gcloud", *arguments], capture_output=True, text=True, check=True)
        return result.stdout.strip()

    token = gcloud("auth", "print-access-token")
    headers = {"Authorization": "Bearer " + token,
               "X-Goog-User-Project": args.project}
    functions = json.loads(gcloud(
        "functions", "list", "--project", args.project, "--format=json"))
    source = (pathlib.Path(__file__).resolve().parents[1] /
              "functions/index.js").read_text()

    def api(url, payload=None):
        request = urllib.request.Request(
            url, headers={**headers, "Content-Type": "application/json"},
            data=None if payload is None else json.dumps(payload).encode())
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.load(response)

    def public(policy):
        return any(binding["role"] == "roles/run.invoker" and
                   "allUsers" in binding.get("members", [])
                   for binding in policy.get("bindings", []))

    def inventory(function):
        service = function["serviceConfig"]["service"]
        return {"function": function["name"].split("/")[-1],
                "region": function["name"].split("/")[3],
                "service": service, "state": function.get("state"),
                "callable": function.get("labels", {}).get(
                    "deployment-callable") == "true",
                "url": function["url"],
                "policy": api("https://run.googleapis.com/v2/" +
                              service + ":getIamPolicy")}

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        inventory_before = list(pool.map(inventory, functions))
    (output / "iam-before.json").write_text(
        json.dumps(inventory_before, indent=2))
    missing = [entry for entry in inventory_before
               if entry["callable"] and not public(entry["policy"])]

    def probe(entry):
        origin = "https://pritze-control-center.greentradexporter.chatgpt.site"
        results = {"function": entry["function"], "region": entry["region"]}
        # An invalid callable envelope is rejected by Firebase before the
        # application's business handler, avoiding production data changes.
        for method in ("OPTIONS", "POST"):
            request = urllib.request.Request(
                entry["url"], method=method,
                headers={"Origin": origin, "Content-Type": "application/json",
                         "Access-Control-Request-Method": "POST",
                         "Access-Control-Request-Headers": "authorization,content-type"},
                data=b"{}" if method == "POST" else None)
            try:
                response = urllib.request.urlopen(request, timeout=90)
            except urllib.error.HTTPError as error:
                response = error
            with response:
                body = response.read().decode()
                try:
                    error_status = json.loads(body).get("error", {}).get("status")
                except (ValueError, AttributeError):
                    error_status = None
                results[method] = {
                    "status": response.status,
                    "allowOrigin": response.headers.get("Access-Control-Allow-Origin"),
                    "error": error_status}
        return results

    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
        before_probes = list(pool.map(probe, missing)) if args.probe else []
    (output / "blocked-before.json").write_text(json.dumps(before_probes, indent=2))
    repaired = []
    if args.repair_public_callables:
        for entry in missing:
            declaration = re.search(
                r"exports\." + re.escape(entry["function"]) +
                r"\s*=\s*on(?:Mobile)?Call\s*\(\s*\{([^}]+)\}", source)
            if not declaration or not re.search(
                    r'invoker:\s*"public"', declaration.group(1)):
                raise RuntimeError("No explicit public source declaration: " +
                                   entry["function"])
            # Re-read immediately before writing; preserve etag and all bindings.
            url = "https://run.googleapis.com/v2/" + entry["service"]
            policy = api(url + ":getIamPolicy")
            if not public(policy):
                bindings = policy.setdefault("bindings", [])
                binding = next((item for item in bindings
                                if item["role"] == "roles/run.invoker" and
                                not item.get("condition")), None)
                if binding is None:
                    binding = {"role": "roles/run.invoker", "members": []}
                    bindings.append(binding)
                binding["members"].append("allUsers")
                updated = api(url + ":setIamPolicy", {"policy": policy})
                if not public(updated):
                    raise RuntimeError("Repair not verified: " + entry["function"])
                repaired.append({"function": entry["function"],
                                 "region": entry["region"]})
                (output / "repairs.json").write_text(json.dumps(repaired, indent=2))
                print("Restored callable transport:", entry["region"],
                      entry["function"], flush=True)

    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
        probes = list(pool.map(probe, [entry for entry in inventory_before
                                       if entry["callable"]])) if args.probe else []
    (output / "endpoint-verification.json").write_text(json.dumps(probes, indent=2))
    failures = [entry for entry in probes
                if entry["OPTIONS"]["status"] != 204 or
                entry["POST"]["status"] != 400 or
                entry["POST"]["error"] != "INVALID_ARGUMENT"]
    summary = {"servicesAudited": len(inventory_before),
               "callablesAudited": sum(entry["callable"] for entry in inventory_before),
               "callablesProbed": len(probes), "missingBefore": len(missing),
               "repaired": len(repaired), "probeFailures": failures}
    (output / "summary.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps({**summary, "probeFailures": len(failures)}, indent=2))
    if failures or (missing and not args.repair_public_callables):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
