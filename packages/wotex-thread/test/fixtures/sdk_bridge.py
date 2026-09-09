#!/usr/bin/env python3
"""Injected C07 peer for BEAM ownership tests; never SDK interoperability evidence."""
import json
import os
from pathlib import Path
import signal
import sys
import time

root=Path(__file__).parent
mode=(root/'mode').read_text().strip()
(root/'pid').write_text(str(os.getpid()))
state=dict(role='disabled',network_name=None,rloc16=None,ipv6_enabled=False,thread_enabled=False,generation=1)
def write(value):
    sys.stdout.write(json.dumps(value,separators=(',',':'))+'\n');sys.stdout.flush()
def reply(request,result):write(dict(version=1,id=request['id'],ok=True,result=result))
if mode=='startup_stall':time.sleep(60)
if mode=='startup_wait':
    while not (root/'release').exists():time.sleep(0.002)
if mode=='bad_ready':write(dict(version=2,event='ready',backend='openthread',revision='bad'))
else:write(dict(version=1,event='ready',backend='openthread',revision='5c8c318627954c99cd1a957a290bbd4b1027d04b'))
for line in sys.stdin:
    request=json.loads(line)
    with (root/'requests').open('a') as log:log.write(json.dumps(request)+'\n')
    operation=request['operation']
    if operation=='open':
        if mode=='open_stall':time.sleep(60)
        if mode=='open_bad':reply(request,dict(role='invalid'))
        elif mode=='open_error':write(dict(version=1,id=request['id'],ok=False,error=dict(code='storage_unavailable')))
        else:reply(request,state)
    elif operation=='close':
        if mode=='close_stall':
            signal.signal(signal.SIGTERM,signal.SIG_IGN)
            time.sleep(60)
        elif mode=='slow_close':time.sleep(0.025)
        reply(request,'invalid' if mode=='close_bad' else None)
        break
    else:
        if mode=='wait':
            while not (root/'release').exists():time.sleep(0.002)
        if mode=='wrong_id':request['id']='unmatched'
        if mode=='duplicate':reply(request,state if operation=='inspect' else 'disabled')
        if mode=='bad_json':sys.stdout.write('{bad}\n');sys.stdout.flush();break
        if mode=='truncated':sys.stdout.write('{');sys.stdout.flush();break
        if mode=='large':sys.stdout.write('x'*131072+'\n');sys.stdout.flush();break
        if mode=='error':
            write(dict(version=1,id=request['id'],ok=False,error=dict(code='remote_error',status=253)))
        else:reply(request,dict(inspect=state,state='disabled',version='fixture',network_name=None,rloc16=None)[operation])
(root/'exited').write_text('done')
