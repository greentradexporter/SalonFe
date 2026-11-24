#!/usr/bin/env python3
"""Repair failed Firebase Cloud Run revisions without rebuilding application code.

Read-only unless --apply is provided. Only quota-failed revisions are selected.
Disable startup CPU boosting and restore fractional CPU where existing source
explicitly requests gcf_gen1 at 256 MiB. Keep full CPU otherwise. IAM, images,
environment, secrets, memory, min/max instances and request billing are preserved.
"""
import argparse
import json
import pathlib
import re
import subprocess
import time
import urllib.request
import urllib.error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--plan", help="Resume an already reviewed plan")
    parser.add_argument("--baseline-inventory", help="Original Cloud Run inventory for exact image preservation")
    args = parser.parse_args()
    output = pathlib.Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    source = (pathlib.Path(__file__).resolve().parents[1] / "functions/index.js").read_text()

    def command(*parts):
        return subprocess.run(parts, capture_output=True, text=True, check=True).stdout.strip()

    token = command("gcloud", "auth", "print-access-token")
    headers = {"Authorization": "Bearer " + token,
               "X-Goog-User-Project": args.project, "Content-Type": "application/json"}

    def api(path, body=None, method=None):
        request = urllib.request.Request(
            "https://run.googleapis.com/v2/" + path, headers=headers, method=method,
            data=None if body is None else json.dumps(body).encode())
        for attempt in range(12):
            try:
                with urllib.request.urlopen(request, timeout=90) as response:
                    return json.load(response)
            except urllib.error.HTTPError as error:
                detail = json.load(error).get("error", {})
                if error.code == 429 and attempt < 11:
                    time.sleep(10)
                    continue
                raise RuntimeError(json.dumps({"status": error.code, "message": detail.get("message")})) from None

    services = json.loads(command("gcloud", "run", "services", "list",
                                  "--project", args.project, "--format=json"))
    plan = []
    for service in services:
        conditions = service.get("status", {}).get("conditions", [])
        ready = next((item for item in conditions if item["type"] == "Ready"), {})
        if ready.get("status") == "True" or "Quota exceeded" not in ready.get("message", ""):
            continue
        metadata = service["metadata"]
        function = metadata.get("annotations", {}).get("cloudfunctions.googleapis.com/function-id")
        if not function:
            continue
        declaration = re.search(r"exports\." + re.escape(function) + r"\s*=", source)
        if not declaration:
            continue
        next_export = source.find("\nexports.", declaration.start() + 1)
        end = min(declaration.start() + 800, next_export if next_export > 0 else len(source))
        header = source[declaration.start():end]
        resources = service["spec"]["template"]["spec"]["containers"][0]["resources"]["limits"]
        fractional = 'cpu: "gcf_gen1"' in header and resources.get("memory") == "256Mi"
        plan.append({"name": metadata["name"], "function": function,
                     "region": metadata["labels"]["cloud.googleapis.com/location"],
                     "beforeCpu": resources["cpu"],
                     "cpu": "0.1666" if fractional else resources["cpu"]})
    if args.plan:
        plan = json.loads(pathlib.Path(args.plan).read_text())
    baseline = json.loads(pathlib.Path(args.baseline_inventory).read_text()) if args.baseline_inventory else services
    baselines = {(item["metadata"]["labels"]["cloud.googleapis.com/location"], item["metadata"]["name"]): item for item in baseline}
    if not (output / "services-before.json").exists():
        (output / "services-before.json").write_text(json.dumps(baseline, indent=2))
    (output / "plan.json").write_text(json.dumps(plan, indent=2))
    print(json.dumps({"quotaFailedServices": len(plan),
                      "fractionalCpuRepairs": sum(item["cpu"] != item["beforeCpu"] for item in plan),
                      "apply": args.apply}), flush=True)
    if not args.apply:
        return

    operations = []
    skipped = []
    for item in plan:
        path = f"projects/{args.project}/locations/{item['region']}/services/{item['name']}"
        service = api(path)
        template = service["template"]
        containers = template["containers"]
        baseline_service = baselines[(item["region"], item["name"])]
        configured_revision = baseline_service["status"]["latestCreatedRevisionName"]
        revision_name = path + "/revisions/" + configured_revision
        revision = api(revision_name)
        original_image = revision["containers"][0]["image"]
        if "@sha256:" not in original_image:
            # The v1 revision status exposes the resolved immutable image digest.
            revision_id = revision_name.rsplit("/", 1)[-1]
            original_image = command("gcloud", "run", "revisions", "describe", revision_id,
                                     "--project", args.project, "--region", item["region"],
                                     "--format=value(status.imageDigest)")
        if "@sha256:" not in original_image:
            raise RuntimeError("Cannot pin the existing image for " + item["name"])
        resources = containers[0]["resources"]
        if (service.get("terminalCondition", {}).get("state") == "CONDITION_SUCCEEDED" and
                containers[0]["image"] == original_image and
                resources["limits"]["cpu"] == item["cpu"] and
                not resources.get("startupCpuBoost", False)):
            skipped.append(item["name"])
            continue
        # Refuse to change a live template unless this immutable registry image exists.
        registry_path = original_image.split("/gcf-artifacts/", 1)[1]
        import urllib.parse
        image_resource = ("https://artifactregistry.googleapis.com/v1/projects/" + args.project +
                          "/locations/" + item["region"] + "/repositories/gcf-artifacts/dockerImages/" +
                          urllib.parse.quote(registry_path, safe=""))
        with urllib.request.urlopen(urllib.request.Request(image_resource, headers=headers), timeout=30) as image_response:
            json.load(image_response)
        containers[0]["image"] = original_image
        containers[0]["resources"]["limits"]["cpu"] = item["cpu"]
        containers[0]["resources"]["startupCpuBoost"] = False
        patch = {"name": path, "etag": service["etag"],
                 "template": {"containers": containers, "revision": ""}}
        mask = ["template.containers", "template.revision"]
        if float(item["cpu"]) < 1:
            patch["template"].update({"maxInstanceRequestConcurrency": 1,
                                      "executionEnvironment": "EXECUTION_ENVIRONMENT_GEN1"})
            mask.extend(["template.maxInstanceRequestConcurrency", "template.executionEnvironment"])
        operation = api(path + "?updateMask=" + ",".join(mask), patch, "PATCH")
        operations.append({**item, "service": path, "operation": operation["name"],
                           "image": original_image})
        (output / "operations.json").write_text(json.dumps(operations, indent=2))
        print("Repairing quota-failed service:", item["name"], "CPU", item["cpu"], flush=True)
        # Stay below the regional Cloud Run write-rate quota.
        time.sleep(3.5)

    pending = operations[:]
    completed = []
    deadline = time.monotonic() + 900
    while pending and time.monotonic() < deadline:
        for item in pending[:]:
            operation = api(item["operation"])
            if not operation.get("done"):
                continue
            result = {**item, "error": operation.get("error")}
            if not result["error"]:
                service = api(item["service"])
                result["condition"] = service.get("terminalCondition")
                result["sameImage"] = service["template"]["containers"][0]["image"] == item["image"]
                result["resources"] = service["template"]["containers"][0]["resources"]
            completed.append(result)
            pending.remove(item)
            (output / "results.json").write_text(json.dumps(completed, indent=2))
            print("Verified rollout:", item["name"], "error" if result["error"] else "complete", flush=True)
        if pending:
            time.sleep(5)
    (output / "pending.json").write_text(json.dumps(pending, indent=2))
    failures = [item for item in completed if item["error"] or not item.get("sameImage") or
                item.get("condition", {}).get("state") != "CONDITION_SUCCEEDED"]
    summary = {"completed": len(completed), "alreadyHealthy": len(skipped), "pending": len(pending), "failures": len(failures)}
    (output / "summary.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary), flush=True)
    if failures or pending:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
