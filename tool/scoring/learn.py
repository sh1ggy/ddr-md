"""Frozen numerical feature definitions for scoring-v31."""
import bisect, json, math
from collections import Counter
from pathlib import Path
import numpy as np
ROOT = Path('.')

def entropy(xs):
    if not len(xs):return 0.
    counts=Counter(xs);n=len(xs)
    return -sum((c/n)*math.log2(c/n) for c in counts.values())

def extract(c):
    # Explicit allowlist: no title, artist, version, tier, rank or score input.
    keep=['rows','duration','jumps','holds','burst','average','sustained',
          'technique','rhythm','reading','stop_burden','bpm_spread',
          'stop_count','stop_seconds','bpm_min','bpm_max']
    f={k:float(c[k]) for k in keep}
    for k,v in c['counts'].items():f['pattern_'+k]=100*v/c['rows']
    f['jump_fraction']=c['jumps']/c['rows']
    f['hold_fraction']=c['holds']/c['rows']
    f['seconds_per_stop']=c['stop_seconds']/max(1,c['stop_count'])
    name,diff=c['name'],c['difficulty']
    song=json.loads((ROOT/'assets/songs'/(name+'.json')).read_text())
    notes=json.loads((ROOT/'assets/steps'/(name+'.json')).read_text())['charts']['sp'][diff]['notes']
    notes=[n for n in notes if n['t']!=3]
    rows={}
    for n in notes:rows.setdefault(n['s'],[]).append(n)
    ts=np.array(sorted(rows));groups=[rows[t] for t in ts]
    beats=np.array([g[0]['b'] for g in groups])
    gaps=np.diff(ts);bgaps=np.diff(beats)
    for q in [5,25,50,75,95]:f[f'gap_q{q}']=float(np.percentile(gaps,q))
    f['gap_cv']=float(np.std(gaps)/np.mean(gaps))
    for threshold in [.1,.15,.2,.3,.5,1.]:
        f[f'gap_under_{threshold}']=float(np.mean(gaps<threshold))
    # Discrete rhythmic vocabulary and its sequence predictability.
    units=[round(float(x)*48) for x in bgaps]
    f['beat_gap_entropy']=entropy(units)
    for k in [2,3,4]:
        f[f'beat_gap_cond_entropy_{k}']=entropy([tuple(units[i:i+k]) for i in range(len(units)-k+1)])-entropy([tuple(units[i:i+k-1]) for i in range(len(units)-k+1)])
    for grid in [1,2,3,4,6,8,12]:
        f[f'gap_grid_{grid}']=float(np.mean(np.abs(bgaps*grid-np.round(bgaps*grid))<.01))
        f[f'note_grid_{grid}']=float(np.mean(np.abs(beats*grid-np.round(beats*grid))<.01))
    # Recurring foot/panel sequences and holds constrain accurate movements.
    masks=[sum(1<<n['c'] for n in g) for g in groups]
    f['row_mask_entropy']=entropy(masks)
    for k in [2,4,8]:
        seq=[tuple(masks[i:i+k]) for i in range(len(masks)-k+1)]
        f[f'panel_ngram_unique_{k}']=len(set(seq))/max(1,len(seq))
    f['same_panel_fraction']=float(np.mean([bool(a&b) for a,b in zip(masks,masks[1:])]))
    holds=[n for n in notes if n['t'] in [1,2] and 'es' in n]
    f['held_seconds_per_row']=sum(n['es']-n['s'] for n in holds)/len(ts)
    f['hold_overlap_fraction']=sum(any(n['s']<t<n['es'] for n in holds) for t in ts)/len(ts)
    # Density profile, including rest/recovery and concentration of workload.
    for window in [1,4,16]:
        counts=np.array([np.searchsorted(ts,t+window,side='left')-i for i,t in enumerate(ts)])
        f[f'peak_{window}s']=float(np.max(counts)/window)
        f[f'median_{window}s']=float(np.median(counts)/window)
    f['early_late_density_ratio']=(np.sum(ts>ts[0]+.75*(ts[-1]-ts[0]))+1)/(np.sum(ts<ts[0]+.25*(ts[-1]-ts[0]))+1)
    # Chart-specific timing, respecting the app's per-chart timing indexing.
    idx=0
    if song.get('per_chart'):
        keys=['beginner','easy','medium','hard','challenge']
        first=next(i for i,k in enumerate(keys) if song.get('sp',{}).get(k) is not None or song.get('dp',{}).get(k) is not None)
        idx=min(len(song['charts'])-1,keys.index(diff)-first)
    timing=song['charts'][idx]
    stops=[s for s in timing['stops'] if ts[0]<=s['st']<=ts[-1]]
    f['stop_max_duration']=max([s['dur'] for s in stops],default=0)
    for threshold in [.1,.25,.5,1.]:
        f[f'stops_over_{threshold}_per100']=100*sum(s['dur']>=threshold for s in stops)/len(ts)
        next_gaps=[]
        for s in stops:
            resume=s['st']+s['dur'];j=np.searchsorted(ts,resume-.002)
            if j<len(ts):next_gaps.append(max(0,ts[j]-resume))
        f[f'restarts_note_under_{threshold}_per100']=100*sum(g<threshold for g in next_gaps)/len(ts)
    f['restart_weighted_burden']=100*sum(min(s['dur'],2)*math.exp(-max(0,ts[j]-(s['st']+s['dur']))/.25)
        for s in stops if (j:=np.searchsorted(ts,s['st']+s['dur']-.002))<len(ts))/len(ts)
    bpms=sorted(timing['bpms'],key=lambda b:b['st'])
    starts=[b['st'] for b in bpms]
    row_bpms=np.array([max(1,bpms[max(0,bisect.bisect_right(starts,float(t))-1)]['val']) for t in ts])
    f['bpm_median']=float(np.median(row_bpms))
    f['bpm_log_sd']=float(np.std(np.log2(row_bpms)))
    f['low_bpm_row_fraction']=float(np.mean(row_bpms<.75*np.median(row_bpms)))
    changes=[abs(math.log2(b['val']/a['val'])) for a,b in zip(bpms,bpms[1:]) if a['val']>0 and b['val']>0 and ts[0]<=b['st']<=ts[-1]]
    f['bpm_changes_over5pct_per100']=100*sum(x>math.log2(1.05) for x in changes)/len(ts)
    f['bpm_log_travel_per100']=100*sum(changes)/len(ts)
    assert all(math.isfinite(v) for v in f.values())
    return f
