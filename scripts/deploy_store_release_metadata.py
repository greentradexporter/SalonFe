#!/usr/bin/env python3
"""Deploy current release metadata to the four existing update-check functions.
Reuses the already deployed app-feature archive, replacing only index and the
release JSON files. Source-only updates retain function limits and IAM. Restore
external Run scaling/boost safeguards if Google resets them during the build.
"""
import concurrent.futures,copy,io,json,pathlib,subprocess,time,urllib.parse,urllib.request,zipfile
PROJECT='trimtime-46539'
android_release=json.loads(pathlib.Path('functions/android_release.json').read_text())
ios_release=json.loads(pathlib.Path('functions/ios_release.json').read_text())
build=android_release['candidateVersionCode']
if build != ios_release['candidateBuildNumber'] or android_release['versionName'] != ios_release['versionName']:
 raise RuntimeError('Android and iOS release metadata must agree')
OUT=pathlib.Path(f'output/salonfe-release-{build}/backend');OUT.mkdir(parents=True,exist_ok=True)
def token():return subprocess.check_output(['gcloud','auth','print-access-token'],text=True).strip()
def api(host,path,body=None,method=None,data=None):
 payload=data if data is not None else json.dumps(body).encode() if body is not None else None
 request=urllib.request.Request('https://'+host+'/'+path,data=payload,headers={'Authorization':'Bearer '+token(),'Content-Type':'application/zip' if data is not None else 'application/json'},method=method)
 with urllib.request.urlopen(request,timeout=120) as r:return json.load(r)
def fn(region,name):return api('cloudfunctions.googleapis.com',f'v2/projects/{PROJECT}/locations/{region}/functions/{name}')
def run(path,body=None):return api('run.googleapis.com','v2/'+path,body,'PATCH' if body else None)
def wait_operation(host,path):
 for _ in range(150):
  result=api(host,path)
  if result.get('done'):
   if result.get('error'):raise RuntimeError(str(result['error']))
   return result
  time.sleep(8)
 raise RuntimeError('Timed out: '+path)
source_file=OUT/'uploaded-source.json'
if source_file.exists():source=json.loads(source_file.read_text())
else:
 original=fn('asia-south1','completeReferralOnboarding')['buildConfig']['source']['storageSource']
 path='storage/v1/b/'+original['bucket']+'/o/'+urllib.parse.quote(original['object'],safe='')+'?alt=media&generation='+str(original['generation'])
 request=urllib.request.Request('https://storage.googleapis.com/'+path,headers={'Authorization':'Bearer '+token()})
 with urllib.request.urlopen(request,timeout=120) as r:blob=r.read()
 output=io.BytesIO()
 replacements={name:pathlib.Path('functions',name).read_bytes() for name in ['index.js','android_release.json','ios_release.json']}
 with zipfile.ZipFile(io.BytesIO(blob)) as old,zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as new:
  for item in old.infolist():new.writestr(item,replacements.pop(item.filename,old.read(item.filename)))
  for name,content in replacements.items():new.writestr(name,content)
 archive=output.getvalue();(OUT/'release-functions-source.zip').write_bytes(archive)
 obj=f'salonfe-release-{build}-'+str(int(time.time()))+'/function-source.zip'
 uploaded=api('storage.googleapis.com','upload/storage/v1/b/'+original['bucket']+'/o?uploadType=media&name='+urllib.parse.quote(obj,safe=''),method='POST',data=archive)
 source={'storageSource':{'bucket':uploaded['bucket'],'object':uploaded['name'],'generation':uploaded['generation']}}
 source_file.write_text(json.dumps(source,indent=2))
progress_file=OUT/'progress.json';progress=json.loads(progress_file.read_text()) if progress_file.exists() else {}
for region in ['asia-south1','us-central1']:
 for name in ['getAndroidAppUpdate','getIosAppUpdate']:
  key=region+'-'+name;record=progress.get(key,{})
  if record.get('verified'):continue
  if not record.get('operation'):
   before=fn(region,name);service=run(before['serviceConfig']['service'])
   (OUT/(key+'-function-before.json')).write_text(json.dumps(before,indent=2));(OUT/(key+'-run-before.json')).write_text(json.dumps(service,indent=2))
   operation=api('cloudfunctions.googleapis.com','v2/'+before['name']+'?updateMask=buildConfig.source',{'name':before['name'],'buildConfig':{'source':source}},'PATCH')
   record={'operation':operation['name']};progress[key]=record;progress_file.write_text(json.dumps(progress,indent=2));print('Updating store-gated release metadata:',key,flush=True)
  wait_operation('cloudfunctions.googleapis.com','v2/'+record['operation'])
  before=json.loads((OUT/(key+'-function-before.json')).read_text());run_before=json.loads((OUT/(key+'-run-before.json')).read_text());current=fn(region,name)
  for field in ['availableCpu','availableMemory','minInstanceCount','maxInstanceCount','maxInstanceRequestConcurrency','serviceAccountEmail','secretEnvironmentVariables','environmentVariables','ingressSettings']:
   if current['serviceConfig'].get(field)!=before['serviceConfig'].get(field):raise RuntimeError('Runtime changed: '+key+' '+field)
  service=run(current['serviceConfig']['service']);t=service['template'];baseline=run_before['template'];containers=copy.deepcopy(t['containers'])
  if containers[0]['resources']['limits']!=baseline['containers'][0]['resources']['limits']:raise RuntimeError('CPU/memory changed')
  boost=baseline['containers'][0]['resources'].get('startupCpuBoost',False)
  if t.get('scaling',{})!=baseline.get('scaling',{}) or containers[0]['resources'].get('startupCpuBoost',False)!=boost:
   containers[0]['resources']['startupCpuBoost']=boost
   op=run(service['name']+'?updateMask=template.containers,template.scaling,template.revision',{'name':service['name'],'etag':service['etag'],'template':{'containers':containers,'scaling':baseline.get('scaling',{}),'revision':''}})
   wait_operation('run.googleapis.com','v2/'+op['name'])
  final=run(service['name'])
  if current.get('state')!='ACTIVE' or final.get('terminalCondition',{}).get('state')!='CONDITION_SUCCEEDED':raise RuntimeError('Endpoint not healthy')
  record['verified']=True;progress_file.write_text(json.dumps(progress,indent=2))
  print('Verified release metadata and unchanged capacity:',key,flush=True)
