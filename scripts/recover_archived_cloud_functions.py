#!/usr/bin/env python3
"""Recover reviewed services from their exact archived source, not local code.

Requires an explicit original function inventory and reviewed capacity plan.
Verifies immutable source generations, rebuilds the same code, then disables
startup CPU boost using the newly built, existing image digest. No IAM or data
changes. Existing memory, scaling, secrets and environment are preserved.
"""
import argparse
import concurrent.futures
import datetime
import json
import pathlib
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", required=True)
    parser.add_argument("--plan", required=True)
    parser.add_argument("--source-verification", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    output = pathlib.Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    inventory = json.loads(pathlib.Path(args.inventory).read_text())
    plan = json.loads(pathlib.Path(args.plan).read_text())
    service_inventory = json.loads(pathlib.Path(args.inventory).with_name("services.json").read_text())
    original_image_references = {(item["metadata"]["labels"]["cloud.googleapis.com/location"], item["metadata"]["annotations"]["cloudfunctions.googleapis.com/function-id"]): item["spec"]["template"]["spec"]["containers"][0]["image"] for item in service_inventory}
    source_checks = json.loads(pathlib.Path(args.source_verification).read_text())
    checked = {(item["region"], item["function"]): item for item in source_checks}
    functions = {(item["name"].split("/")[3], item["name"].split("/")[-1]): item
                 for item in inventory}
    for item in plan:
        check = checked[(item["region"], item["function"])]
        assert check["verified"], item["function"]
        assert check["source"] == functions[(item["region"], item["function"])]["buildConfig"]["source"]["storageSource"]
    print(json.dumps({"reviewedServices": len(plan), "verifiedArchives": len(plan), "apply": args.apply}), flush=True)
    if not args.apply:
        return

    token = subprocess.run(["gcloud", "auth", "print-access-token"],
                           capture_output=True, text=True, check=True).stdout.strip()
    headers = {"Authorization": "Bearer " + token,
               "X-Goog-User-Project": "trimtime-46539", "Content-Type": "application/json"}

    def api(host, path, body=None, method=None):
        request = urllib.request.Request("https://" + host + "/" + path, headers=headers,
                                         method=method, data=None if body is None else json.dumps(body).encode())
        for attempt in range(18):
            try:
                with urllib.request.urlopen(request, timeout=90) as response:
                    return json.load(response)
            except urllib.error.HTTPError as error:
                detail = json.load(error).get("error", {})
                if error.code == 429 and attempt < 17:
                    time.sleep(10)
                    continue
                raise RuntimeError(json.dumps({"code": error.code, "message": detail.get("message")})) from None
            except (ConnectionError, TimeoutError, urllib.error.URLError):
                if body is None and attempt < 5:
                    time.sleep(2)
                    continue
                raise

    def functions_api(path, body=None, method=None):
        return api("cloudfunctions.googleapis.com", "v2/" + path, body, method)

    def run_api(path, body=None, method=None):
        return api("run.googleapis.com", "v2/" + path, body, method)

    def source_hash(source):
        path = ("storage/v1/b/" + source["bucket"] + "/o/" + urllib.parse.quote(source["object"], safe="") +
                "?" + urllib.parse.urlencode({"generation": source["generation"], "fields": "md5Hash,size"}))
        return api("storage.googleapis.com", path)

    priority = {name: index for index, name in enumerate([
        "getAdminPhaseOneData", "getDiscountAdministrationDataAsAdmin",
        "getProinPhaseOneDataAsAdmin", "signInAdminWithPassword",
        "reviewSalonOnboardingAsAdmin", "addAdminNote", "updateSalonControlAsAdmin",
    ])}
    queue = sorted(plan, key=lambda item: priority.get(item["function"], 100))
    progress_file = output / "progress.json"
    progress = json.loads(progress_file.read_text()) if progress_file.exists() else []
    intent_file = output / "start-intent.json"
    if intent_file.exists():
        intent = json.loads(intent_file.read_text())
        if intent["function"] not in {item["function"] for item in progress}:
            query = urllib.parse.urlencode({"filter": 'metadata.target="' + intent["functionName"] + '"', "pageSize": 100})
            operations = functions_api("projects/trimtime-46539/locations/" + intent["region"] + "/operations?" + query).get("operations", [])
            started = datetime.datetime.fromisoformat(intent["requestedAt"])
            candidates = [operation for operation in operations if datetime.datetime.fromisoformat(operation["metadata"]["createTime"].replace("Z", "+00:00")) >= started - datetime.timedelta(seconds=10)]
            if candidates:
                operation = max(candidates, key=lambda item: item["metadata"]["createTime"])
                progress.append({**intent, "buildOperation": operation["name"]})
                progress_file.write_text(json.dumps(progress, indent=2))
                print("Reused interrupted build request:", intent["function"], flush=True)
        intent_file.unlink()
    completed_names = {item["function"] for item in progress if item.get("verified")}
    active = [item for item in progress if not item.get("verified") and not item.get("error")]
    submitted_names = {item["function"] for item in progress}
    queue = [item for item in queue if item["function"] not in submitted_names]

    def save():
        progress_file.write_text(json.dumps(progress, indent=2))

    def start(item):
        original = functions[(item["region"], item["function"])]
        current = functions_api(original["name"])
        expected_source = original["buildConfig"]["source"]["storageSource"]
        current_source = current["buildConfig"]["source"]["storageSource"]
        if current_source != expected_source and source_hash(current_source) != source_hash(expected_source):
            raise RuntimeError("Archived source changed externally: " + item["function"])
        config = {"availableCpu": item["cpu"], "maxInstanceRequestConcurrency": 1 if float(item["cpu"]) < 1 else original["serviceConfig"].get("maxInstanceRequestConcurrency", 80)}
        body = {"name": original["name"], "serviceConfig": config,
                "buildConfig": {"source": original["buildConfig"]["source"]}}
        mask = "serviceConfig.availableCpu,serviceConfig.maxInstanceRequestConcurrency,buildConfig.source"
        intent = {**item, "functionName": original["name"], "source": expected_source,
                  "service": original["serviceConfig"]["service"], "requestedAt": datetime.datetime.now(datetime.timezone.utc).isoformat()}
        intent_file.write_text(json.dumps(intent, indent=2))
        operation = functions_api(original["name"] + "?updateMask=" + mask, body, "PATCH")
        record = {**item, "functionName": original["name"], "source": expected_source,
                  "service": original["serviceConfig"]["service"], "buildOperation": operation["name"]}
        progress.append(record)
        active.append(record)
        save()
        intent_file.unlink(missing_ok=True)
        print("Rebuilding exact archived source:", item["function"], flush=True)

    def finish(record, operation):
        # A build may succeed even if its boosted startup subsequently failed.
        stages = operation.get("metadata", {}).get("stages", [])
        build = next((stage for stage in stages if stage["name"] == "BUILD"), None)
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as reads:
            current_future = reads.submit(functions_api, record["functionName"])
            service_future = reads.submit(run_api, record["service"])
            original_hash_future = reads.submit(source_hash, record["source"])
            current = current_future.result()
            rebuilt_hash_future = reads.submit(source_hash, current["buildConfig"]["source"]["storageSource"])
            build_name = build.get("resource") if build else current["buildConfig"].get("build")
            built_future = reads.submit(api, "cloudbuild.googleapis.com", "v1/" + build_name + "?fields=status")
            original_hash = original_hash_future.result()
            rebuilt_hash = rebuilt_hash_future.result()
            built = built_future.result()
            service = service_future.result()
        if original_hash != rebuilt_hash:
            raise RuntimeError("Archived source content changed: " + record["function"])
        record["sourceMd5"] = original_hash["md5Hash"]
        record["rebuiltSourceMd5"] = rebuilt_hash["md5Hash"]
        if built.get("status") != "SUCCESS":
            raise RuntimeError("Archived build failed: " + record["function"])
        image_reference = original_image_references[(record["region"], record["function"])]
        registry, project, repository, package_tag = image_reference.split("/", 3)
        package, tag = package_tag.rsplit(":", 1)
        tag_path = ("v1/projects/" + project + "/locations/" + record["region"] + "/repositories/" + repository +
                    "/packages/" + urllib.parse.quote(package, safe="") + "/tags/" + urllib.parse.quote(tag, safe=""))
        registry_tag = api("artifactregistry.googleapis.com", tag_path)
        digest = registry_tag["version"].rsplit("/", 1)[-1]
        pinned_image = "/".join([registry, project, repository, package]) + "@" + digest
        if "@sha256:" not in pinned_image:
            raise RuntimeError("Missing rebuilt registry digest: " + record["function"])
        containers = service["template"]["containers"]
        existing_resources = containers[0]["resources"]
        if (service.get("terminalCondition", {}).get("state") == "CONDITION_SUCCEEDED" and
                containers[0]["image"] == pinned_image and
                existing_resources["limits"]["cpu"] == record["cpu"] and
                not existing_resources.get("startupCpuBoost", False)):
            record.update({"verified": True, "image": pinned_image, "archivedBuildSucceeded": True,
                           "build": build_name, "condition": service["terminalCondition"]})
            save()
            print("Already healthy with archived source preserved:", record["function"], flush=True)
            return
        containers[0]["image"] = pinned_image
        containers[0]["resources"]["startupCpuBoost"] = False
        containers[0]["resources"]["limits"]["cpu"] = record["cpu"]
        template = {"containers": containers, "revision": ""}
        mask = ["template.containers", "template.revision"]
        if float(record["cpu"]) < 1:
            template.update({"executionEnvironment": "EXECUTION_ENVIRONMENT_GEN1", "maxInstanceRequestConcurrency": 1})
            mask.extend(["template.executionEnvironment", "template.maxInstanceRequestConcurrency"])
        rollout = run_api(record["service"] + "?updateMask=" + ",".join(mask),
                          {"name": record["service"], "etag": service["etag"], "template": template}, "PATCH")
        record.update({"rolloutOperation": rollout["name"], "image": pinned_image,
                       "build": build_name, "archivedBuildSucceeded": True})
        save()
        print("Deploying rebuilt image without CPU boost:", record["function"], flush=True)

    deadline = time.monotonic() + 3600
    while (queue or active) and time.monotonic() < deadline:
        while queue and len(active) < 10:
            start(queue.pop(0))
            time.sleep(3.5)
        for record in active[:]:
            if not record.get("rolloutOperation"):
                operation = functions_api(record["buildOperation"])
                if not operation.get("done"):
                    continue
                finish(record, operation)
                if record.get("verified"):
                    active.remove(record)
                time.sleep(3.5)
            else:
                operation = run_api(record["rolloutOperation"])
                if not operation.get("done"):
                    continue
                if operation.get("error"):
                    record["error"] = operation["error"]
                    save()
                    raise RuntimeError("Rollout failed: " + record["function"] + " " + str(record["error"]))
                service = run_api(record["service"])
                record["verified"] = service.get("terminalCondition", {}).get("state") == "CONDITION_SUCCEEDED" and service["template"]["containers"][0]["image"] == record["image"]
                if not record["verified"]:
                    raise RuntimeError("Health or image verification failed: " + record["function"])
                record["condition"] = service["terminalCondition"]
                active.remove(record)
                save()
                print("Healthy with archived source preserved:", record["function"], flush=True)
        if active:
            time.sleep(5)
    summary = {"requested": len(plan), "verified": sum(bool(item.get("verified")) for item in progress),
               "remaining": len(queue) + len(active)}
    (output / "summary.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary), flush=True)
    if summary["remaining"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
