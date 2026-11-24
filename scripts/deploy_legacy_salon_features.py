#!/usr/bin/env python3
"""Apply the reviewed SalonFe bundle to four existing legacy HTTP functions.
Only buildConfig.source is patched; all runtime limits, secrets and IAM remain.
The Mumbai deployment must already have succeeded. Results are resumable.
"""
import io, json, pathlib, subprocess, time, urllib.request, urllib.parse, zipfile
PROJECT = 'trimtime-46539'
NAMES = ['completeReferralOnboarding', 'createBooking', 'rescheduleBookingAsAdmin', 'saveOwnerSalonProfile']
OUT = pathlib.Path('output/salon-discovery/legacy-deployment')
OUT.mkdir(parents=True, exist_ok=True)
def api(host, path, body=None, method=None):
    token = subprocess.check_output(['gcloud', 'auth', 'print-access-token'], text=True).strip()
    request = urllib.request.Request('https://' + host + '/' + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={'Authorization':'Bearer ' + token, 'Content-Type':'application/json'}, method=method)
    with urllib.request.urlopen(request, timeout=90) as response:
        return json.load(response)
def function_path(region, name):
    return f'projects/{PROJECT}/locations/{region}/functions/{name}'
def function(region, name):
    return api('cloudfunctions.googleapis.com', 'v2/' + function_path(region, name))
source_function = function('asia-south1', 'completeReferralOnboarding')
if source_function.get('state') != 'ACTIVE': raise RuntimeError('Mumbai source is not healthy')
source = source_function['buildConfig']['source']
# Inspect the immutable deployed archive before copying it to legacy handlers.
storage = source['storageSource']
media_path = 'storage/v1/b/' + storage['bucket'] + '/o/' + urllib.parse.quote(storage['object'], safe='') + '?alt=media&generation=' + str(storage['generation'])
token = subprocess.check_output(['gcloud','auth','print-access-token'],text=True).strip()
request = urllib.request.Request('https://storage.googleapis.com/' + media_path,headers={'Authorization':'Bearer ' + token})
with urllib.request.urlopen(request,timeout=90) as response: archive=response.read()
with zipfile.ZipFile(io.BytesIO(archive)) as bundle:
    code=bundle.read('index.js').decode()
    if 'closedDaysInput' not in code or 'exports.salonSharePage' not in code: raise RuntimeError('Unexpected source bundle')
progress_file=OUT/'progress.json'
progress=json.loads(progress_file.read_text()) if progress_file.exists() else {}
for name in NAMES:
    previous=function('us-central1',name)
    record=progress.get(name,{})
    if record.get('verified'): continue
    if not record.get('operation'):
        (OUT/(name+'-before.json')).write_text(json.dumps(previous,indent=2))
        operation=api('cloudfunctions.googleapis.com','v2/'+previous['name']+'?updateMask=buildConfig.source',
            {'name':previous['name'],'buildConfig':{'source':source}},'PATCH')
        record={'operation':operation['name'],'source':source}
        progress[name]=record;progress_file.write_text(json.dumps(progress,indent=2))
        print('Updating legacy source:',name,flush=True)
    deadline=time.monotonic()+1200
    while time.monotonic()<deadline:
        operation=api('cloudfunctions.googleapis.com','v2/'+record['operation'])
        if operation.get('done'): break
        time.sleep(10)
    else: raise RuntimeError('Timed out: '+name)
    if operation.get('error'): raise RuntimeError(json.dumps(operation['error']))
    current=function('us-central1',name)
    before=json.loads((OUT/(name+'-before.json')).read_text())
    keys=['availableCpu','availableMemory','maxInstanceCount','minInstanceCount','maxInstanceRequestConcurrency','secretEnvironmentVariables','environmentVariables','serviceAccountEmail','ingressSettings']
    for key in keys:
        if current['serviceConfig'].get(key) != before['serviceConfig'].get(key): raise RuntimeError('Runtime changed: '+key)
    if current.get('state')!='ACTIVE': raise RuntimeError('Function is not active: '+name)
    record['verified']=True
    (OUT/(name+'-after.json')).write_text(json.dumps(current,indent=2))
    progress_file.write_text(json.dumps(progress,indent=2))
    print('Verified legacy source and unchanged runtime:',name,flush=True)
