"""Frozen chart-derived scoring measurements."""
import bisect, hashlib, json, math
from collections import Counter, defaultdict
from pathlib import Path
import numpy as np


def entropy(values):
    counts=Counter(values);n=len(values)
    return -sum((v/n)*math.log2(v/n) for v in counts.values()) if n else 0.

def calculate(notes):
    rows=defaultdict(list)
    for n in notes:
        if n['t']!=3:rows[n['s']].append(n)
    times=np.array(sorted(rows));groups=[rows[t] for t in times];beats=np.array([g[0]['b'] for g in groups]);n=len(times)
    gap=np.diff(times);bgap=np.diff(beats);units=np.round(bgap*48).astype(int);f={}
    incoming=np.r_[gap[0],gap];outgoing=np.r_[gap,gap[-1]]
    bincoming=np.r_[bgap[0],bgap];boutgoing=np.r_[bgap,bgap[-1]]
    # Sparse weak subdivisions demand a different timing context from streams.
    for grid in [1,2,4,8]:
        on_grid=np.abs(beats*grid-np.round(beats*grid))<.015
        weak=~on_grid
        for rest in [.25,.5,1.]:
            isolated=weak&(bincoming>=rest-.001)&(boutgoing>=rest-.001)
            entering=weak&(bincoming>=rest-.001)&(boutgoing<rest-.001)
            exiting=weak&(bincoming<rest-.001)&(boutgoing>=rest-.001)
            for label,event in [('isolated',isolated),('entry',entering),('exit',exiting)]:
                f[f'timing_weak_g{grid}_r{rest}_{label}']=float(np.mean(event))
    # Rhythm changes are weighted by how much real time there is to adjust.
    local_change=np.r_[0.,np.abs(np.log2(np.maximum(gap[1:],.001)/np.maximum(gap[:-1],.001))),0.]
    local_change=np.minimum(local_change,3.)
    imbalance=np.abs(np.log2(np.maximum(incoming,.001)/np.maximum(outgoing,.001)))
    surprise=[]
    for width in [8,32]:
        values=[];previous=Counter()
        for i,u in enumerate(units):
            if i>=width:previous[units[i-width]]-=1
            # Only previously seen intervals determine online novelty.
            size=min(width,i);value=-math.log2((previous[u]+.5)/(size+4.))
            values.append(value);previous[u]+=1
        surprise=np.r_[0.,values]
        f[f'timing_online_surprise_w{width}_mean']=float(np.mean(surprise))
        f[f'timing_online_surprise_w{width}_p90']=float(np.percentile(surprise,90))
        f[f'timing_online_surprise_w{width}_fast']=float(np.mean(surprise/np.maximum(incoming,.08)))
    for cutoff in [.15,.25,.4]:
        asym=imbalance*(np.minimum(incoming,outgoing)<cutoff)
        f[f'timing_gap_asym_{cutoff}_mean']=float(np.mean(asym))
        f[f'timing_gap_asym_{cutoff}_p90']=float(np.percentile(asym,90))
    # Concentrated hard passages should survive averaging over an easy chart.
    hazards={'change':local_change,'offbeat':(~(np.abs(beats*2-np.round(beats*2))<.015)).astype(float),'surprise':surprise,'asymmetry':imbalance}
    for label,values in hazards.items():
        cumulative=np.r_[0.,np.cumsum(values)]
        for window in [1.,4.,12.]:
            ends=np.searchsorted(times,times+window,side='left');counts=ends-np.arange(n)
            local=(cumulative[ends]-cumulative[np.arange(n)])/window
            f[f'timing_{label}_peak_{window}s']=float(np.max(local))
            f[f'timing_{label}_p90_{window}s']=float(np.percentile(local,90))
            per_row=(cumulative[ends]-cumulative[np.arange(n)])/np.maximum(1,counts)
            valid=counts>=4
            f[f'timing_{label}_row_p90_{window}s']=float(np.percentile(per_row[valid],90)) if np.any(valid) else 0.
    # Per-foot-independent rhythm vocabulary conditioned on surrounding panels.
    masks=np.array([sum(1<<x['c'] for x in g) for g in groups])
    same=(masks[:-1]&masks[1:])>0
    jumps=np.array([len(g)>1 for g in groups])
    for label,selection in [('same_panel',same),('changed_panel',~same),('jump_entry',jumps[1:]),('single_entry',~jumps[1:])]:
        u=units[selection];g=gap[selection]
        f[f'timing_{label}_entropy']=entropy(u.tolist())
        f[f'timing_{label}_fast_entropy']=entropy(u[g<.25].tolist())
    # Repeated notes with changing spacing are distinct from regular jacks.
    for col in range(4):
        lane=np.array([t for t,g in zip(times,groups) if any(x['c']==col for x in g)])
        lg=np.diff(lane);lc=np.minimum(3.,np.abs(np.log2(np.maximum(lg[1:],.001)/np.maximum(lg[:-1],.001))))
        f[f'timing_lane{col}_change_mean']=float(np.mean(lc)) if len(lc) else 0.
        f[f'timing_lane{col}_fast_change']=float(np.mean(lc*(np.minimum(lg[1:],lg[:-1])<.3))) if len(lc) else 0.
    assert all(math.isfinite(v) for v in f.values())
    return f
