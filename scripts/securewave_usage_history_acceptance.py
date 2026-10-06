#!/usr/bin/env python3
"""Owner-scoped history checks using the installed app session in memory only."""
import argparse
import gi,json,sys,time,urllib.request,urllib.error
from pathlib import Path

gi.require_version('Secret','1')
from gi.repository import Secret
OUT = None
FIELDS=('session_id','device_id','server_id','protocol','connected_at','disconnected_at','bytes_sent','bytes_received','last_sequence','final_sequence','recording_quality','finalization_reason','metering_version','client_verified_at')
class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*args,**kwargs):raise RuntimeError('History redirects refused')

def history():
 schema=Secret.Schema.new('com.example.securewave_app/FlutterSecureStorage',Secret.SchemaFlags.NONE,{'account':Secret.SchemaAttributeType.STRING})
 blob=Secret.password_lookup_sync(schema,{'account':'com.example.securewave_app.secureStorage'},None)
 if not blob:raise RuntimeError('Installed app session is unavailable')
 token=json.loads(blob).get('access_token');del blob
 if not isinstance(token,str) or not token:raise RuntimeError('Installed app is not signed in')
 req=urllib.request.Request('https://api.securewaveapp.com/api/vpn/usage/sessions?limit=100',headers={'Authorization':'Bearer '+token})
 try:
  with urllib.request.build_opener(NoRedirect()).open(req,timeout=20) as response:
   data=json.loads(response.read(262144))
 finally:del token,req
 return [{k:r.get(k) for k in FIELDS} for r in data['sessions']]

def main():
 global OUT
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('operation', choices=['before','after'])
 parser.add_argument('--evidence-dir', type=Path, required=True)
 args=parser.parse_args()
 OUT=args.evidence_dir.expanduser().resolve()
 if not OUT.is_dir() or OUT.stat().st_mode & 0o077:
  raise RuntimeError('Evidence directory must exist and be private (mode 0700)')
 import os
 os.umask(0o077)
 mode=args.operation
 if mode=='before':
  rows=history();(OUT/'ledger-before.json').write_text(json.dumps(rows,indent=2));print('Authenticated owner-scoped history baseline saved; credentials remain in memory only.');return
 if mode!='after':raise RuntimeError('Invalid ledger operation')
 old={r['session_id'] for r in json.loads((OUT/'ledger-before.json').read_text())}
 traffic=[json.loads((OUT/(label+'-connected.json')).read_text()) for label in ('05-first','07-reconnect')]
 minimum_rx=sum(r['delta_rx'] for r in traffic);minimum_tx=sum(r['delta_tx'] for r in traffic)
 deadline=time.monotonic()+45
 while True:
  rows=[r for r in history() if r['session_id'] not in old]
  complete=len(rows)==2 and all(r['metering_version']==2 and r['disconnected_at'] and r['final_sequence']==r['last_sequence'] and r['last_sequence']>0 and r['client_verified_at'] and r['recording_quality']=='complete' and r['finalization_reason']=='client_disconnect' for r in rows)
  if complete:
   if sum(r['bytes_received'] for r in rows)<minimum_rx or sum(r['bytes_sent'] for r in rows)<minimum_tx:raise RuntimeError('Persisted totals do not cover independently observed traffic')
   (OUT/'ledger-after.json').write_text(json.dumps(rows,indent=2))
   print('Final ledger verified: two finalized v2 sessions, complete quality, verified timestamps and cumulative totals covering observed traffic.');return
  if time.monotonic()>=deadline:
   (OUT/'ledger-after-unverified.json').write_text(json.dumps(rows,indent=2));raise RuntimeError('Final ledger did not satisfy the acceptance conditions within 45 seconds')
  time.sleep(2)

if __name__=='__main__':
 try:main()
 except urllib.error.HTTPError as e:print('History HTTP status:',e.code);sys.exit(1)
 except RuntimeError as e:print('Ledger verification blocked:',str(e));sys.exit(1)
 except Exception:print('Ledger verification failed; sensitive exception details were suppressed.');sys.exit(1)
