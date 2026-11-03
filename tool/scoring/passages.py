"""Frozen chart-derived scoring measurements."""
import bisect, hashlib, json, math
from collections import Counter, defaultdict
from pathlib import Path
import numpy as np
PARAMS = None
CHANNELS=['log_gap_seconds','log_gap_beats','beat_sin','beat_cos','halfbeat_sin','halfbeat_cos','quarterbeat_sin','quarterbeat_cos','fourbeat_sin','fourbeat_cos','left_panel','down_panel','up_panel','right_panel','left_foot','right_foot','both_feet','repeat_foot','left_cadence','right_cadence','hold_start','active_holds','hold_release','shock','jump','bpm_ratio','net_bpm_ratio','stop_overlap']


def event_sequence(song,notes,diff,foot_rows):
    bytime=defaultdict(list)
    for n in notes:bytime[n['s']].append(n)
    times=np.array(sorted(bytime));rows=[bytime[t] for t in times];beats=np.array([g[0]['b'] for g in rows]);gap=np.r_[np.median(np.diff(times)),np.diff(times)];bgap=np.r_[np.median(np.diff(beats)),np.diff(beats)];x=np.zeros((len(times),len(CHANNELS)));x[:,0]=np.clip(np.log2(np.maximum(gap,.03)),-5,2)/3;x[:,1]=np.clip(np.log2(np.maximum(bgap,1/48)),-5,3)/3
    phase=beats%1
    for k,mult in enumerate([1,2,4]):x[:,2+2*k]=np.sin(2*np.pi*mult*phase);x[:,3+2*k]=np.cos(2*np.pi*mult*phase)
    x[:,8]=np.sin(2*np.pi*(beats%4)/4);x[:,9]=np.cos(2*np.pi*(beats%4)/4)
    assigned={round(t,3):int(mask) for t,mask in foot_rows};last={1:None,8:None};previous=0
    holds=[n for n in notes if n['t'] in [1,2] and 'es' in n];keys=['beginner','easy','medium','hard','challenge'];index=0
    if song.get('per_chart'):
        first=next(i for i,k in enumerate(keys) if song.get('sp',{}).get(k) is not None or song.get('dp',{}).get(k) is not None);index=min(len(song['charts'])-1,keys.index(diff)-first)
    timing=song['charts'][index];bpms=sorted(timing['bpms'],key=lambda b:b['st']);starts=[b['st'] for b in bpms];row_bpms=np.array([max(1,bpms[max(0,bisect.bisect_right(starts,float(t))-1)]['val']) for t in times]);headline=max(1,float(np.median(row_bpms)));x[:,25]=np.clip(np.log2(row_bpms/headline),-2,2)/2;x[:,26]=np.clip(np.log2(np.maximum(1,60*bgap/np.maximum(gap,.03))/headline),-2,2)/2
    for i,(t,row) in enumerate(zip(times,rows)):
        mask=assigned.get(round(float(t),3),0);heads=[n for n in row if n['t']!=3]
        for n in heads:x[i,10+n['c']]=1
        x[i,14]=bool(mask&1);x[i,15]=bool(mask&8);x[i,16]=mask==9;x[i,17]=bool(mask&previous) and mask!=9 and previous!=9
        for foot,column in [(1,18),(8,19)]:
            if mask&foot:
                dt=2. if last[foot] is None else max(.03,t-last[foot]);x[i,column]=np.clip(np.log2(dt),-5,2)/3;last[foot]=t
        x[i,20]=sum(n['t'] in [1,2] for n in row)/2;x[i,21]=min(2,sum(n['s']<t<n['es'] for n in holds))/2;pt=times[i-1] if i else t-gap[i];x[i,22]=min(2,sum(pt<h['es']<=t for h in holds))/2;x[i,23]=any(n['t']==3 for n in row);x[i,24]=max(0,len(heads)-1);overlap=sum(max(0,min(t,s['st']+s['dur'])-max(pt,s['st'])) for s in timing['stops']);x[i,27]=min(1,overlap/max(.03,gap[i]));previous=mask
    return x

def mirror(x):
    z=x.copy();z[:,[10,13]]=z[:,[13,10]];z[:,[14,15]]=z[:,[15,14]];z[:,[18,19]]=z[:,[19,18]];return z

def encode(x,params):
    output=[]
    for g in range(len(params['lengths'])):
        projection=params['A'][g];projected=np.zeros((len(x),projection.shape[1]))
        # Fixed accumulation order makes cached and live features independent
        # of BLAS thread scheduling.
        for channel in range(x.shape[1]):projected+=x[:,channel,None]*projection[channel][None,:]
        length=int(params['lengths'][g]);dilation=int(params['dilations'][g]);count=len(x)-(length-1)*dilation
        if count<=0:output.extend(np.zeros(48));continue
        response=np.zeros((count,projection.shape[1]))
        for k in range(length):response+=projected[k*dilation:k*dilation+count]*params['W'][g,k][None,:]
        output.extend(np.max(response,axis=0));output.extend(np.mean(response>params['B'][g][None,:],axis=0))
    return np.asarray(output)

def calculate(song,notes,diff,foot_rows,params_path=PARAMS):
    with np.load(params_path) as source:params={k:source[k] for k in source.files}
    x=event_sequence(song,notes,diff,foot_rows);v=(encode(x,params)+encode(mirror(x),params))/2
    return {f'passage_{i:04d}':float(value) for i,value in enumerate(v)}
