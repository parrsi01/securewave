#!/usr/bin/python3
"""Exercise the installed SecureWave GUI; retain only nonsecret runtime evidence."""
import os
os.environ['GDK_BACKEND'] = 'x11'
import argparse
import ctypes as C
import ctypes.util
import datetime
import ipaddress
import json
from pathlib import Path
import re
import secrets
import socket
import subprocess
import sys
import time
import pyatspi
import gi
gi.require_version('Gdk', '3.0')
gi.require_version('GdkX11', '3.0')
from gi.repository import Gdk, GdkX11

OUT = None
CONFIG = Path.home() / '.config/securewave/sw-wg.conf'
EVENTS = None

def config_files():
    # Contract 15 uses a separate config for each durable usage session.
    # Include the legacy path so baseline/cleanup also detect stale old files.
    root = CONFIG.parent
    return ([CONFIG] if CONFIG.exists() or CONFIG.is_symlink() else []) + list(root.glob('usage-[0-9]*/sw-wg.conf'))

def record(event, **data):
    item = dict(time=datetime.datetime.now(datetime.timezone.utc).isoformat(), event=event, **data)
    with EVENTS.open('a') as f:
        f.write(json.dumps(item) + '\n')
    print(json.dumps(item), flush=True)

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def cmd(args, timeout=25):
    p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    require(p.returncode == 0, 'Command failed: ' + args[0] + ' ' + ' '.join(args[1:3]))
    return p.stdout.strip()

def runtime():
    with socket.socket(socket.AF_UNIX) as s:
        s.settimeout(5)
        s.connect('/run/securewave/helper.sock')
        s.sendall(b'version=1\nop=wireguard.runtime\n')
        s.shutdown(socket.SHUT_WR)
        data = b''
        while True:
            b = s.recv(4096)
            if not b:
                break
            data += b
            require(len(data) < 65536, 'Oversized runtime response')
    def unescape(v):
        return re.sub(r'\\(.)', lambda m: {'n': '\n', 'r': '\r'}.get(m[1], m[1]), v)
    d = {k: unescape(v) for line in data.decode().splitlines() if '=' in line for k, v in [line.split('=', 1)]}
    require(d.get('ok') == 'true', 'Helper runtime inspection failed')
    return d

def nodes():
    applications = [a for a in pyatspi.Registry.getDesktop(0) if 'securewave' in (a.name or '').lower()]
    require(len(applications) == 1, 'Expected one installed SecureWave GUI')
    result = []
    def visit(o, depth=0):
        if depth > 40:
            return
        result.append(o)
        for c in o:
            visit(c, depth+1)
    visit(applications[0])
    return result

def ui():
    result = []
    for o in nodes():
        role = o.getRoleName()
        name = '<field>' if role in ['text', 'password text', 'entry'] else o.name
        if name:
            result.append(dict(role=role, name=name))
    return result

def has(name, role=None):
    return any(o.name == name and (role is None or o.getRoleName() == role) for o in nodes())

def click(name):
    candidates = [o for o in nodes() if o.getRoleName() == 'push button' and o.name == name]
    require(len(candidates) == 1, 'Expected exactly one button: ' + name)
    o = candidates[0]
    require(o.getState().contains(pyatspi.STATE_ENABLED), 'Button is disabled: ' + name)
    q = o.queryAction()
    action = next((i for i in range(q.nActions) if q.getName(i).lower() in ['tap', 'click']), None)
    require(action is not None and q.doAction(action), 'GUI action failed: ' + name)
    record('gui_button', name=name)

def wait(check, message, seconds=100):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if check():
            return
        time.sleep(1)
    raise RuntimeError(message)

def screenshot(name):
    x = C.CDLL(ctypes.util.find_library('X11'))
    x.XOpenDisplay.argtypes = [C.c_char_p]; x.XOpenDisplay.restype = C.c_void_p
    x.XDefaultRootWindow.argtypes = [C.c_void_p]; x.XDefaultRootWindow.restype = C.c_ulong
    x.XQueryTree.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong), C.POINTER(C.c_ulong), C.POINTER(C.POINTER(C.c_ulong)), C.POINTER(C.c_uint)]
    x.XFetchName.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(C.c_char_p)]
    x.XFree.argtypes = [C.c_void_p]; x.XCloseDisplay.argtypes = [C.c_void_p]
    d = x.XOpenDisplay(None)
    require(bool(d), 'X11 display unavailable')
    found = []
    def visit(w, depth=0):
        r=C.c_ulong(); p=C.c_ulong(); children=C.POINTER(C.c_ulong)(); n=C.c_uint()
        x.XQueryTree(d,w,C.byref(r),C.byref(p),C.byref(children),C.byref(n))
        for i in range(n.value):
            wid=children[i]; nm=C.c_char_p(); x.XFetchName(d,wid,C.byref(nm))
            if nm.value and nm.value.decode(errors='replace') == 'SecureWave VPN':
                found.append(wid)
            if nm.value:
                x.XFree(nm)
            if depth < 2:
                visit(wid,depth+1)
        if children:
            x.XFree(children)
    visit(x.XDefaultRootWindow(d))
    require(len(found) == 1, 'Visible SecureWave window not found')
    window=GdkX11.X11Window.foreign_new_for_display(Gdk.Display.get_default(),found[0])
    geom=window.get_geometry()
    pix=Gdk.pixbuf_get_from_window(window,0,0,geom.width,geom.height)
    require(pix is not None, 'Window capture failed')
    pix.savev(str(OUT/(name+'.png')),'png',[],[])
    x.XCloseDisplay(d)
    (OUT/(name+'-ui.json')).write_text(json.dumps(ui(),indent=2))

def network():
    return dict(routes4=json.loads(cmd(['ip','-j','route','show','table','all'])),
                routes6=json.loads(cmd(['ip','-j','-6','route','show','table','all'])),
                rules=json.loads(cmd(['ip','-j','rule','show'])),
                dns=cmd(['resolvectl','dns']), domains=cmd(['resolvectl','domain']),
                public_ip=cmd(['curl','-4fsS','--max-time','20','https://api.ipify.org']))

def initialize():
    require(runtime()['status']=='disconnected','Baseline tunnel was active')
    require(not Path('/sys/class/net/sw-wg').exists(),'Stale tunnel interface')
    require(not config_files(),'Stale temporary VPN config')
    baseline=network()
    (OUT/'network-baseline.json').write_text(json.dumps(baseline,indent=2))
    record('network_baseline', public_ip=baseline['public_ip'], helper=runtime())
    screenshot('03-before-connect')

def register():
    # This operation is used only following explicit authorization. Secrets live
    # in this process and the GUI; they are never logged or saved by the harness.
    email='securewave-qa-'+secrets.token_hex(8)+'@example.com'
    password=secrets.token_urlsafe(28)+'aA1!'
    click('New to SecureWave? Create an account')
    wait(lambda:has('Create account','push button'),'Registration screen did not open',10)
    fields=[o for o in nodes() if o.getRoleName() in ['text','password text']]
    require(len(fields)==3,'Unexpected registration fields')
    for o,v in zip(fields,[email,password,password]):
        require(o.queryEditableText().setTextContents(v),'Could not enter generated registration field')
    click('Create account')
    wait(lambda:has('Account created. Sign in to continue.'),'GUI registration did not succeed',35)
    record('registration',result='passed',credential_storage='process memory only')
    fields=[o for o in nodes() if o.getRoleName() in ['text','password text']]
    require(len(fields)==2,'Unexpected sign-in fields')
    for o,v in zip(fields,[email,password]):
        require(o.queryEditableText().setTextContents(v),'Could not enter generated sign-in field')
    click('Sign in')
    wait(lambda:has('Connect','push button'),'GUI sign-in did not reach Home',35)
    del password,email
    record('login',result='passed')
    screenshot('04-authenticated')

def connected(label, baseline):
    click('Connect')
    wait(lambda:(has('Connected') or has('VPN connected.')) and has('Disconnect','push button'),'GUI did not reach Connected')
    r=runtime()
    require(r['status']=='connected' and r['counters_available']=='true','Connected runtime invalid')
    require(Path('/sys/class/net/sw-wg').is_dir(),'WireGuard interface missing')
    configs = config_files()
    require(len(configs) == 1,'Expected exactly one session tunnel config')
    config = configs[0]
    require(not config.is_symlink() and config.is_file() and config.stat().st_uid == os.getuid() and config.stat().st_mode & 0o777 == 0o600,'Temporary config missing or unsafe mode')
    # Retain only the public server parameters from the installed app's config.
    public={}
    for line in config.read_text().splitlines():
        if '=' not in line:
            continue
        k,v=map(str.strip,line.split('=',1))
        if k in ['PublicKey','Endpoint','AllowedIPs','DNS','Address']:
            public[k]=v
    peers={k:int(v) for line in r['peer_handshakes'].splitlines() if line for k,v in [line.split()]}
    require(public.get('PublicKey') in peers,'Configured production peer missing from runtime')
    age=int(time.time())-peers[public['PublicKey']]
    require(-30<=age<=180,'Peer handshake is not recent')
    route=cmd(['ip','-4','route','get','1.1.1.1'])
    require('dev sw-wg' in route,'Internet route does not use WireGuard')
    dns=cmd(['resolvectl','query','api.securewaveapp.com'])
    net=network()
    ipaddress.ip_address(net['public_ip'])
    require(net['public_ip']!=baseline['public_ip'],'VPN egress did not change')
    require(int(r['rx_bytes'])>0 and int(r['tx_bytes'])>0,'WireGuard counters are empty')
    screenshot(label+'-connected')
    before=runtime()
    download=json.loads(cmd(['curl','-4fsS','--max-time','40','--output','/dev/null','--write-out','%{json}',
                             'https://speed.cloudflare.com/__down?bytes=3145728'],45))
    require(int(download['http_code'])==200 and int(download['size_download'])==3145728,'Real download was incomplete')
    wait(lambda:int(runtime()['rx_bytes'])-int(before['rx_bytes'])>=3145728,'Downloaded bytes missing from tunnel counters',10)
    after=runtime()
    delta_rx=int(after['rx_bytes'])-int(before['rx_bytes']);delta_tx=int(after['tx_bytes'])-int(before['tx_bytes'])
    require(delta_tx>0,'Real download did not increase upload counters')
    time.sleep(4)
    screenshot(label+'-traffic')
    data=dict(helper=r,public_server=public,handshake_age_seconds=age,route=route,dns_resolution=dns,
              network=net,download_bytes=int(download['size_download']),runtime_after=after,delta_rx=delta_rx,delta_tx=delta_tx,ui=ui())
    (OUT/(label+'-connected.json')).write_text(json.dumps(data,indent=2))
    record('connected_verified',cycle=label,public_ip=net['public_ip'],handshake_age_seconds=age,download_bytes=3145728,delta_rx=delta_rx,delta_tx=delta_tx)

def disconnect(label, baseline):
    click('Disconnect')
    wait(lambda:(has('Disconnected') or has('VPN disconnected.')) and has('Connect','push button'),'GUI did not reach Disconnected',45)
    require(runtime()['status']=='disconnected','Helper still reports connected')
    require(not Path('/sys/class/net/sw-wg').exists(),'WireGuard interface remains')
    require(not config_files(),'Temporary VPN config remains')
    net=network()
    require(net['public_ip']==baseline['public_ip'],'Baseline egress was not restored')
    for k in ['routes4','routes6','rules','dns','domains']:
        require(net[k]==baseline[k],'Baseline '+k+' was not restored exactly')
    cmd(['resolvectl','query','api.securewaveapp.com'])
    screenshot(label+'-disconnected')
    (OUT/(label+'-disconnected.json')).write_text(json.dumps(dict(helper=runtime(),network=net,ui=ui()),indent=2))
    record('disconnect_verified',cycle=label,public_ip=net['public_ip'],routes_restored=True,dns_restored=True,temporary_config_removed=True)

def lifecycle():
    wait(lambda:has('Connect','push button'),'Sign-in is required',10)
    baseline=json.loads((OUT/'network-baseline.json').read_text())
    try:
        connected('05-first',baseline)
        disconnect('06-first',baseline)
        connected('07-reconnect',baseline)
        disconnect('08-final',baseline)
        record('lifecycle',result='passed',final_state='disconnected')
    except Exception:
        # Prefer the installed app's cleanup. Never replace a failed app test
        # with a direct helper connection or a mock tunnel.
        try:
            if has('Disconnect','push button'):
                disconnect('failure-cleanup',baseline)
        except Exception as cleanup:
            record('cleanup_failure',reason=str(cleanup))
        raise

if __name__=='__main__':
    os.umask(0o077)
    p=argparse.ArgumentParser()
    p.add_argument('operation',choices=['initialize','register','lifecycle','ui'])
    p.add_argument('--evidence-dir', type=Path, required=True, help='Private evidence directory shared by all operations')
    args=p.parse_args()
    OUT = args.evidence_dir.expanduser().resolve()
    OUT.mkdir(parents=True, exist_ok=True, mode=0o700)
    require(OUT.stat().st_mode & 0o077 == 0, 'Evidence directory must be private (mode 0700)')
    EVENTS = OUT / 'events.jsonl'
    try:
        if args.operation=='ui':print(json.dumps(ui(),indent=2))
        else:globals()[args.operation]()
    except Exception as e:
        record('failure',operation=args.operation,reason=str(e))
        sys.exit(1)
