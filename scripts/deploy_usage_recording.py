"""Prepare and activate an exact-SHA overlay while retaining the full live backend."""
import argparse
import base64
import json
from pathlib import Path
import re
import subprocess

CHANGED = (
    "models/vpn_connection.py", "models/vpn_usage_event.py", "models/wireguard_peer.py",
    "services/usage_metering_service.py", "services/subscription_access.py", "routes/vpn.py",
)
ADDED = ("routes/usage_recording.py", "scripts/migrate_usage_recording.py")
TESTS = ("tests/test_vpn_client_owned_config.py", "tests/test_wireguard_helper.py",
         "tests/test_usage_recording.py", "tests/test_usage_postgres.py")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--ssh-key", required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--base-sha", default="9e4f7587a37c9a97d2c9fcc393654b07dcbcf412")
    parser.add_argument("--activate", action="store_true")
    args = parser.parse_args()
    for sha in (args.source_sha, args.base_sha):
        if not re.fullmatch("[0-9a-f]{40}", sha):
            raise SystemExit("An exact source SHA is required")
    root = Path(__file__).resolve().parents[1]
    if subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip() != args.source_sha:
        raise SystemExit("Source SHA does not match checkout")
    if subprocess.check_output(["git", "status", "--porcelain"], cwd=root):
        raise SystemExit("Clean source checkout required")
    payload = {"source_sha": args.source_sha, "activate": args.activate, "files": {}}
    for path in CHANGED + ADDED + TESTS:
        previous = subprocess.check_output(["git", "show", args.base_sha + ":" + path], cwd=root) if path in CHANGED else b""
        payload["files"][path] = {"base": base64.b64encode(previous).decode(),
                                 "new": base64.b64encode((root / path).read_bytes()).decode()}
    remote = r'''
import base64,hashlib,json,os,pathlib,shutil,subprocess,tempfile,time
payload = json.loads(PAYLOAD)
deployment_stage='production-env-validation'
root=pathlib.Path('/opt/securewave-beta')
active=(root/'current').resolve()
assert active.parent == root/'releases'
pid=subprocess.check_output(['systemctl','show','securewave-api','-p','MainPID','--value'],text=True).strip()
runtime=dict(x.split('=',1) for x in pathlib.Path('/proc/'+pid+'/environ').read_bytes().decode().split('\0') if '=' in x)
assert runtime.get('ENVIRONMENT') == 'production'
assert runtime.get('DEMO_MODE') == 'false' and runtime.get('WG_MOCK_MODE') == 'false'
name=time.strftime('%Y%m%dT%H%M%SZ',time.gmtime())+'-usage-'+payload['source_sha'][:12]
candidate=root/'releases'/name
assert not candidate.exists()
deployment_stage='preserving-copy'
shutil.copytree(active,candidate,symlinks=True)
manifest={'source_sha':payload['source_sha'],'base_release':str(active),'files':{}}
with tempfile.TemporaryDirectory(prefix='usage-merge-') as temporary:
 for relative,contents in payload['files'].items():
  target=candidate/relative
  new=base64.b64decode(contents['new']);base=base64.b64decode(contents['base'])
  deployment_stage='overlay-merge:'+relative
  if base:
   before=pathlib.Path(temporary)/'base';after=pathlib.Path(temporary)/'new'
   before.write_bytes(base);after.write_bytes(new)
   result=subprocess.run(['git','merge-file','-p',str(target),str(before),str(after)],capture_output=True)
   if result.returncode:raise RuntimeError('Overlay merge requires review: '+relative)
   new=result.stdout
  target.parent.mkdir(parents=True,exist_ok=True)
  ownership=target.stat() if target.exists() else (active/'routes/vpn.py').stat()
  target.write_bytes(new);os.chmod(target,ownership.st_mode & 0o777);os.chown(target,ownership.st_uid,ownership.st_gid)
  manifest['files'][relative]=hashlib.sha256(new).hexdigest()
deployment_stage='compile-candidate'
python=str(candidate/'.venv/bin/python')
env=dict(os.environ,**runtime,PYTHONPATH=str(candidate))
subprocess.run([python,'-m','py_compile',*[str(candidate/p) for p in payload['files']]],check=True,env=env,cwd=candidate)
(candidate/'.usage-overlay.json').write_text(json.dumps(manifest,indent=2)+'\n')
os.chmod(candidate/'.usage-overlay.json',0o444)
if not payload['activate']:
 print('Prepared backend candidate: '+str(candidate));raise SystemExit(0)
deployment_stage='database-backup'
# Back up the database locally on the verified host without exposing its URL.
from sqlalchemy.engine import make_url
url=make_url(runtime['DATABASE_URL'])
assert url.host in ('localhost','127.0.0.1','::1')
backup=pathlib.Path('/var/backups')/('securewave-usage-'+name)
backup.mkdir(mode=0o700)
with (backup/'database.dump').open('wb') as output:
 result=subprocess.run(['runuser','-u','postgres','--','pg_dump','--format=custom','--dbname',url.database],stdout=output,stderr=subprocess.PIPE)
 if result.returncode:raise RuntimeError('Database backup failed')
os.chmod(backup/'database.dump',0o600)
deployment_stage='database-migration'
subprocess.run([python,'-m','scripts.migrate_usage_recording'],check=True,env=env,cwd=candidate)
before_hash={p:hashlib.sha256((active/p).read_bytes()).hexdigest() for p in ('routes/auth.py','services/jwt_service.py')}
deployment_stage='activate-candidate'
switched=False
try:
 for relative in ('models/vpn_connection.py','models/vpn_usage_event.py','models/wireguard_peer.py','services/usage_metering_service.py','services/subscription_access.py','routes/vpn.py','routes/usage_recording.py'):
  assert hashlib.sha256((candidate/relative).read_bytes()).hexdigest()==manifest['files'][relative]
 new_link=root/'current.usage-new';new_link.symlink_to(candidate);os.replace(new_link,root/'current');switched=True
 subprocess.run(['systemctl','restart','securewave-api'],check=True)
 import urllib.request
 for attempt in range(30):
  try:
   with urllib.request.urlopen('http://127.0.0.1:8080/api/ready',timeout=1) as response:ready=json.load(response)
   if ready.get('database')=='connected':break
  except Exception:pass
  time.sleep(1)
 else:raise RuntimeError('New API did not become database-ready')
 for relative,digest in before_hash.items():assert hashlib.sha256((candidate/relative).read_bytes()).hexdigest()==digest
 print('Activated backend candidate: '+str(candidate))
 print('Source overlay SHA: '+payload['source_sha'])
 print('Database backup saved; authentication source unchanged; readiness passed.')
except BaseException:
 if switched:
  link=root/'current.usage-rollback';link.symlink_to(active);os.replace(link,root/'current')
  subprocess.run(['systemctl','restart','securewave-api'],check=True)
 raise
'''
    remote = remote.replace("PAYLOAD", repr(json.dumps(payload)))
    remote = "try:\n exec(compile(" + repr(remote) + ", 'usage_deployment', 'exec'))\nexcept Exception as error:\n print('Failure stage: ' + globals().get('deployment_stage', 'startup'))\n print('Failure type: ' + type(error).__name__)\n raise SystemExit(1)\n"
    command = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-o", "StrictHostKeyChecking=yes",
               "-i", args.ssh_key, args.host, "/opt/securewave-beta/current/.venv/bin/python -"]
    result = subprocess.run(command, input=remote, text=True, capture_output=True)
    print(result.stdout, end="")
    if result.returncode:
        # Never dump production subprocess errors or environment values.
        print("Backend preparation/deployment failed; inspect the candidate and rollback state.")
        raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
