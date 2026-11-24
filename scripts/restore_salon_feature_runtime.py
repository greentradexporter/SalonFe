#!/usr/bin/env python3
"""Restore recorded pre-update Mumbai scaling/boost settings; never change CPU."""
import copy,json,pathlib,subprocess,time,urllib.request
OUT=pathlib.Path('output/salon-discovery')
rows=json.loads((OUT/'runtime-baselines.json').read_text())
rows.append({'name':'salonsharepage','scaling':{'maxInstanceCount':3},'resources':{'limits':{'cpu':'0.1666','memory':'256Mi'}}})
def api(path,body=None):
 token=subprocess.check_output(['gcloud','auth','print-access-token'],text=True).strip()
 request=urllib.request.Request('https://run.googleapis.com/v2/'+path,data=json.dumps(body).encode() if body else None,headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'},method='PATCH' if body else 'GET')
 with urllib.request.urlopen(request,timeout=90) as r:return json.load(r)
records=[]
for row in rows:
 path='projects/trimtime-46539/locations/asia-south1/services/'+row['name']
 service=api(path);template=service['template'];containers=copy.deepcopy(template['containers'])
 if containers[0]['resources']['limits']!=row['resources']['limits']:raise RuntimeError('CPU/memory changed; review required: '+row['name'])
 boost=row['resources'].get('startupCpuBoost',False)
 desired_scaling=row.get('scaling',{})
 if template.get('scaling',{})!=desired_scaling or containers[0]['resources'].get('startupCpuBoost',False)!=boost:
  containers[0]['resources']['startupCpuBoost']=boost
  (OUT/(row['name']+'-runtime-before.json')).write_text(json.dumps(service,indent=2))
  operation=api(path+'?updateMask=template.containers,template.scaling,template.revision',{'name':path,'etag':service['etag'],'template':{'containers':containers,'scaling':desired_scaling,'revision':''}})
  print('Restoring existing runtime safeguards:',row['name'],flush=True)
  for _ in range(90):
   result=api(operation['name'])
   if result.get('done'):break
   time.sleep(5)
  if not result.get('done') or result.get('error'):raise RuntimeError(str(result))
 current=api(path);t=current['template'];c=t['containers'][0]['resources']
 if t.get('scaling',{})!=desired_scaling or c.get('startupCpuBoost',False)!=boost or current['terminalCondition']['state']!='CONDITION_SUCCEEDED':raise RuntimeError('Verification failed: '+row['name'])
 records.append({'name':row['name'],'cpu':c['limits']['cpu'],'scaling':t.get('scaling',{}),'startupCpuBoost':c.get('startupCpuBoost',False),'healthy':True})
 (OUT/'runtime-final.json').write_text(json.dumps(records,indent=2))
 print('Verified unchanged CPU and prior scaling:',row['name'],flush=True)
