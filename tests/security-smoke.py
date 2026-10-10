"""Non-destructive live authorization probes. Uses only the public application key."""
import concurrent.futures,json,re,urllib.request,urllib.error
from pathlib import Path
shared=(Path(__file__).resolve().parents[1]/'public/shared.js').read_text()
base=re.search(r"SUPABASE='([^']+)'",shared)[1]
key=re.search(r"PUBLIC_KEY='([^']+)'",shared)[1]
api=base+'/functions/v1/drvn-api'
actions=['workspace','dashboard','admin_list','save_event','cancel_event','entry_action','review','receipt','photo','settings','email_retry','send_emails','export']
cases=[(a,api,{'action':a},{},[401]) for a in actions]
cases += [('forged JWT',api,{'action':'workspace'},{'Authorization':'Bearer invalid-test-token'},[401]),('invalid private status',api,{'action':'status','token':'invalid'},{},[400]),('foreign origin',api,{'action':'events'},{'Origin':'https://unauthorized.example'},[400]),('direct registration read',base+'/rest/v1/drvn_registrations?select=id',None,{},[401,403]),('direct admin RPC',base+'/rest/v1/rpc/drvn_admin_summary',{'p_actor':'ee6e2514-a985-4fa6-b790-2ca3c11ed163'},{},[401,403]),('private receipt listing',base+'/storage/v1/object/list/drvn-receipts',{'prefix':'','limit':1},{},[200,400,401,403]),('public calendar',api,{'action':'events'},{},[200])]
def probe(case):
 name,url,body,extra,expected=case
 request=urllib.request.Request(url,data=json.dumps(body).encode() if body is not None else None,headers={'apikey':key,'Content-Type':'application/json',**extra})
 try:
  with urllib.request.urlopen(request,timeout=25) as r: status=r.status;payload=r.read()
 except urllib.error.HTTPError as ex:status=ex.code;payload=ex.read()
 except Exception as ex:return {'test':name,'pass':False,'error':type(ex).__name__}
 passed=status in expected
 if name=='private receipt listing' and status==200:passed=json.loads(payload)==[]
 if name=='public calendar' and status==200:
  passed=all(not any(k in t for k in ['email','token_hash','idempotency_key']) for t in json.loads(payload))
 return {'test':name,'status':status,'pass':passed}
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:results=list(pool.map(probe,cases))
print(json.dumps(results,indent=2),flush=True)
assert all(r['pass'] for r in results),'Security smoke test failed'
