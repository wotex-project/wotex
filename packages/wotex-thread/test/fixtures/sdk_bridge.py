#!/usr/bin/env python3
"""Injected C07 peer for BEAM ownership tests; never SDK interoperability evidence."""
import json
import os
from pathlib import Path
import signal
import select
import sys
import time

root=Path(__file__).parent
mode=(root/'mode').read_text().strip()
(root/'pid').write_text(str(os.getpid()))
petition=None
state=dict(role='disabled',network_name=None,rloc16=None,ipv6_enabled=False,thread_enabled=False,generation=1)
def await_release():
    while not (root/'release').exists():
        readable,_,_=select.select([sys.stdin.fileno()],[],[],0.002)
        if readable and not os.read(sys.stdin.fileno(),4096):sys.exit(0)
def write(value):
    sys.stdout.write(json.dumps(value,separators=(',',':'))+'\n');sys.stdout.flush()
def reply(request,result):write(dict(version=1,id=request['id'],ok=True,result=result))
if mode=='startup_stall':time.sleep(60)
if mode=='startup_wait':
    await_release()
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
            await_release()
        if mode=='wrong_id':request['id']='unmatched'
        if mode=='duplicate':reply(request,state if operation=='inspect' else 'disabled')
        if mode=='bad_json':sys.stdout.write('{bad}\n');sys.stdout.flush();break
        if mode=='truncated':sys.stdout.write('{');sys.stdout.flush();break
        if mode=='large':sys.stdout.write('x'*131072+'\n');sys.stdout.flush();break
        if operation=='form_network':
            if mode=='error':write(dict(version=1,id=request['id'],ok=False,error=dict(code='creation_not_allowed',state=state)))
            elif mode=='form_bad':reply(request,state)
            else:
                state.update(ipv6_enabled=True,thread_enabled=True,role='leader')
                reply(request,state)
        elif operation in ['management_active_set','management_pending_set']:
            if mode=='error':write(dict(version=1,id=request['id'],ok=False,error=dict(code='remote_error',status=37)))
            elif mode=='management_bad':reply(request,dict(accepted=True,effective='verified'))
            else:reply(request,dict(accepted=True,effective='not_verified'))
        elif operation=='commissioner_start':
            if mode in ['petition_pending','petition_stop_wait']:petition=request
            elif mode=='commissioner_bad':reply(request,'petition')
            elif mode=='error':write(dict(version=1,id=request['id'],ok=False,error=dict(code='remote_error',status=13)))
            else:reply(request,dict(state='active'))
        elif operation=='commissioner_stop':
            if mode=='petition_stop_wait':continue
            if petition is not None:
                write(dict(version=1,id=petition['id'],ok=False,error=dict(code='cancelled')))
                petition=None
            reply(request,dict(state='disabled'))
        elif operation=='add_joiner':
            parameters=request['parameters']
            identity=dict(type='eui64',value='000000000000002B') if mode=='admission_wrong' else parameters['identity']
            lifetime=1 if mode=='admission_lifetime' else parameters['lifetime']
            reply(request,dict(identity=identity,lifetime_s=lifetime))
        elif operation=='remove_joiner':reply(request,None)
        elif operation=='set_enabled':
            if mode=='error':write(dict(version=1,id=request['id'],ok=False,error=dict(code='remote_error',status=253)))
            else:
                state['ipv6_enabled']=request['parameters']['ipv6']
                state['thread_enabled']=request['parameters']['thread']
                state['role']='detached' if state['thread_enabled'] else 'disabled'
                reply(request,state)
        elif operation=='validate_dataset':
            if mode=='dataset_invalid':write(dict(version=1,id=request['id'],ok=False,error=dict(code='invalid_dataset')))
            else:reply(request,None)
        elif operation=='get_dataset':
            if mode=='dataset_invalid':reply(request,dict(type='bytes',base64='AB=='))
            elif mode=='dataset_missing':write(dict(version=1,id=request['id'],ok=False,error=dict(code='dataset_not_found')))
            else:reply(request,dict(type='bytes',base64='+gEA'))
        elif mode=='error':
            write(dict(version=1,id=request['id'],ok=False,error=dict(code='remote_error',status=253)))
        else:reply(request,dict(inspect=state,state='disabled',version='fixture',network_name=None,rloc16=None)[operation])
(root/'exited').write_text('done')
