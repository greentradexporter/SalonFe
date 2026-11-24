#!/usr/bin/env python3
"""Add the consent-based location projection to the existing admin read endpoint.

Dry run by default. --apply rebuilds the endpoint's exact archived source with
only the customer serializer addition and its new helper. Runtime capacity,
identity, secret references and IAM are verified against the original settings.
"""
import argparse
import copy
import io
import json
import pathlib
import subprocess
import time
import urllib.parse
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/admin-customer-location'
PATH = 'projects/trimtime-46539/locations/asia-south1/functions/getAdminPhaseOneData'


def api(host, path, body=None, method=None, data=None):
    token = subprocess.check_output(['gcloud', 'auth', 'print-access-token'], text=True).strip()
    payload = data if data is not None else json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request('https://' + host + '/' + path, data=payload,
        headers={'Authorization': 'Bearer ' + token,
                 'Content-Type': 'application/zip' if data is not None else 'application/json'}, method=method)
    with urllib.request.urlopen(request, timeout=120) as response:
        return json.load(response)


def wait(host, path):
    for _ in range(150):
        result = api(host, path)
        if result.get('done'):
            if result.get('error'):
                raise RuntimeError(str(result['error']))
            return
        time.sleep(8)
    raise RuntimeError('Timed out: ' + path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    progress_file = OUT / 'deployment.json'
    progress = json.loads(progress_file.read_text()) if progress_file.exists() else {}
    if progress.get('verified'):
        print('Existing deployment already verified; no changes made.')
        return
    if not progress.get('operation'):
        before = api('cloudfunctions.googleapis.com', 'v2/' + PATH)
        service = api('run.googleapis.com', 'v2/' + before['serviceConfig']['service'])
        iam = api('run.googleapis.com', 'v2/' + service['name'] + ':getIamPolicy')
        print('Plan: source-only update to getAdminPhaseOneData in asia-south1; preserve runtime and IAM.', flush=True)
        if not args.apply:
            return
        for name, value in [('function-before', before), ('run-before', service), ('iam-before', iam)]:
            (OUT / (name + '.json')).write_text(json.dumps(value, indent=2))
        source = before['buildConfig']['source']['storageSource']
        route = 'storage/v1/b/' + source['bucket'] + '/o/' + urllib.parse.quote(source['object'], safe='') + '?alt=media&generation=' + str(source['generation'])
        token = subprocess.check_output(['gcloud', 'auth', 'print-access-token'], text=True).strip()
        request = urllib.request.Request('https://storage.googleapis.com/' + route, headers={'Authorization': 'Bearer ' + token})
        with urllib.request.urlopen(request, timeout=120) as response:
            archive = response.read()
        output = io.BytesIO()
        with zipfile.ZipFile(io.BytesIO(archive)) as old, zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as new:
            code = old.read('index.js').decode()
            if 'customerLocation: adminCustomerLocation(' in code:
                raise RuntimeError('Location projection already exists; inspect instead of redeploying.')
            anchor = 'const {setGlobalOptions} = require("firebase-functions/v2");'
            if code.count(anchor) != 1:
                raise RuntimeError('Unexpected archived imports')
            code = code.replace(anchor, anchor + '\nconst {adminCustomerLocation} = require("./admin_customer_location");')
            start = code.index('function adminCustomerRecord(document) {')
            end = code.index('\nfunction adminReviewRecord', start)
            section = code[start:end]
            anchor = '    ...adminCustomerProfileView(document.id, data),'
            if section.count(anchor) != 1:
                raise RuntimeError('Unexpected archived customer serializer')
            section = section.replace(anchor, anchor + '\n    customerLocation: adminCustomerLocation(\n      data.customerLocation,\n      adminMillis(data.customerLocation?.capturedAt),\n    ),')
            code = code[:start] + section + code[end:]
            for entry in old.infolist():
                new.writestr(entry, code.encode() if entry.filename == 'index.js' else old.read(entry.filename))
            new.writestr('admin_customer_location.js', (ROOT / 'functions/admin_customer_location.js').read_bytes())
        # Check the exact patched deployment source before uploading it.
        subprocess.run(['node', '--check'], input=code, text=True, check=True)
        blob = output.getvalue()
        (OUT / 'function-source.zip').write_bytes(blob)
        obj = 'admin-customer-location-' + str(int(time.time())) + '/function-source.zip'
        uploaded = api('storage.googleapis.com', 'upload/storage/v1/b/' + source['bucket'] + '/o?uploadType=media&name=' + urllib.parse.quote(obj, safe=''), method='POST', data=blob)
        patched_source = {'storageSource': {'bucket': uploaded['bucket'], 'object': uploaded['name'], 'generation': uploaded['generation']}}
        operation = api('cloudfunctions.googleapis.com', 'v2/' + PATH + '?updateMask=buildConfig.source',
            {'name': PATH, 'buildConfig': {'source': patched_source}}, 'PATCH')
        progress = {'operation': operation['name']}
        progress_file.write_text(json.dumps(progress, indent=2))
        print('Building the existing admin read endpoint with the location projection.', flush=True)
    wait('cloudfunctions.googleapis.com', 'v2/' + progress['operation'])
    before = json.loads((OUT / 'function-before.json').read_text())
    baseline = json.loads((OUT / 'run-before.json').read_text())
    current = api('cloudfunctions.googleapis.com', 'v2/' + PATH)
    for field in ['availableCpu', 'availableMemory', 'minInstanceCount', 'maxInstanceCount', 'maxInstanceRequestConcurrency', 'serviceAccountEmail', 'secretEnvironmentVariables', 'environmentVariables', 'ingressSettings', 'timeoutSeconds']:
        if current['serviceConfig'].get(field) != before['serviceConfig'].get(field):
            raise RuntimeError('Runtime changed: ' + field)
    service = api('run.googleapis.com', 'v2/' + current['serviceConfig']['service'])
    template = service['template']
    original = baseline['template']
    containers = copy.deepcopy(template['containers'])
    if containers[0]['resources']['limits'] != original['containers'][0]['resources']['limits']:
        raise RuntimeError('CPU or memory changed')
    boost = original['containers'][0]['resources'].get('startupCpuBoost', False)
    if template.get('scaling', {}) != original.get('scaling', {}) or containers[0]['resources'].get('startupCpuBoost', False) != boost:
        containers[0]['resources']['startupCpuBoost'] = boost
        op = api('run.googleapis.com', 'v2/' + service['name'] + '?updateMask=template.containers,template.scaling,template.revision',
            {'name': service['name'], 'etag': service['etag'], 'template': {'containers': containers, 'scaling': original.get('scaling', {}), 'revision': ''}}, 'PATCH')
        wait('run.googleapis.com', 'v2/' + op['name'])
    final = api('run.googleapis.com', 'v2/' + service['name'])
    iam = api('run.googleapis.com', 'v2/' + service['name'] + ':getIamPolicy')
    prior_iam = json.loads((OUT / 'iam-before.json').read_text())
    if iam.get('bindings', []) != prior_iam.get('bindings', []):
        raise RuntimeError('IAM changed')
    if current.get('state') != 'ACTIVE' or final.get('terminalCondition', {}).get('state') != 'CONDITION_SUCCEEDED':
        raise RuntimeError('Endpoint not healthy')
    for name, value in [('function-after', current), ('run-after', final), ('iam-after', iam)]:
        (OUT / (name + '.json')).write_text(json.dumps(value, indent=2))
    progress['verified'] = True
    progress_file.write_text(json.dumps(progress, indent=2))
    print('Verified healthy endpoint, unchanged capacity, identity, secret references and IAM.', flush=True)


if __name__ == '__main__':
    main()
