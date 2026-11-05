"""Local rhythm, movement and timing measurements."""
import bisect, json, math, zlib
from collections import Counter, defaultdict
from pathlib import Path
import numpy as np
from learn import entropy
ROOT = Path('.')

def run_lengths(values):
    if not len(values):return [0]
    out=[];n=1
    for a,b in zip(values,values[1:]):
        if a==b:n+=1
        else:out.append(n);n=1
    out.append(n);return out

def extra_features(name,diff):
    song=json.loads((ROOT/'assets/songs'/(name+'.json')).read_text())
    notes=json.loads((ROOT/'assets/steps'/(name+'.json')).read_text())['charts']['sp'][diff]['notes']
    notes=[n for n in notes if n['t']!=3];rows=defaultdict(list)
    for n in notes:rows[n['s']].append(n)
    ts=np.array(sorted(rows));groups=[rows[t] for t in ts];beats=np.array([g[0]['b'] for g in groups])
    gaps=np.diff(ts);bgaps=np.diff(beats);n=len(ts);duration=ts[-1]-ts[0];f={}
    keys=['beginner','easy','medium','hard','challenge'];idx=0
    if song.get('per_chart'):
        first=next(i for i,k in enumerate(keys) if song.get('sp',{}).get(k) is not None or song.get('dp',{}).get(k) is not None)
        idx=min(len(song['charts'])-1,keys.index(diff)-first)
    timing=song['charts'][idx];bpms=sorted(timing['bpms'],key=lambda b:b['st']);starts=[b['st'] for b in bpms]
    def bpm(t):return max(1,bpms[max(0,bisect.bisect_right(starts,float(t))-1)]['val'])
    # Repetition in real-time note intervals; quantization tolerates stored ms.
    timed_units=np.round(gaps*np.array([bpm(t) for t in ts[:-1]])/60*48).astype(int)
    beat_units=np.round(bgaps*48).astype(int)
    for label,units in [('time',timed_units),('beat',beat_units)]:
        f[label+'_interval_entropy']=entropy(units)
        runs=run_lengths(units)
        f[label+'_regular_run_mean']=float(np.mean(runs));f[label+'_regular_run_max']=max(runs)
        f[label+'_regular_run_row_fraction']=sum(r for r in runs if r>=8)/len(units)
        for lag in [1,2,3,4,8,16]:
            f[f'{label}_recurrence_lag{lag}']=float(np.mean(units[lag:]==units[:-lag])) if len(units)>lag else 0
        text=','.join(str(x) for x in units).encode()
        f[label+'_compression_ratio']=len(zlib.compress(text))/max(1,len(text))
        for k in [2,4,8]:
            motifs=[tuple(units[i:i+k]) for i in range(len(units)-k+1)]
            f[f'{label}_motif_unique{k}']=len(set(motifs))/max(1,len(motifs))
    # Binary/ternary changes, distinguished from continuous repeating triplets.
    ternary=(np.abs(bgaps*3-np.round(bgaps*3))<.01)&(np.abs(bgaps*2-np.round(bgaps*2))>.01)
    f['ternary_gap_fraction']=float(np.mean(ternary))
    f['ternary_boundary_fraction']=float(np.mean(ternary[1:]!=ternary[:-1]))
    truns=run_lengths(ternary)
    f['ternary_singleton_fraction']=sum(x==1 for x in truns)/len(truns)
    ratios=gaps[1:]/np.maximum(gaps[:-1],.001)
    for ratio in [1.,2.,.5,1.5,2/3,3.,1/3]:
        f[f'gap_ratio_{ratio:.3f}']=float(np.mean(np.abs(np.log2(ratios/ratio))<.035))
    f['gap_ratio_rare']=float(np.mean(np.min(np.abs(np.log2(ratios[:,None]/np.array([1,2,.5,1.5,2/3,3,1/3])[None,:])),axis=1)>.1))
    # Actual four-beat rhythm motifs and transitions between neighbouring bars.
    bars=defaultdict(list)
    for beat in beats:
        bar=math.floor((beat+.0001)/4);bars[bar].append(round((beat-bar*4)*48))
    motifs=[tuple(sorted(set(v))) for k,v in sorted(bars.items())]
    f['bar_rhythm_unique_fraction']=len(set(motifs))/max(1,len(motifs))
    f['bar_rhythm_entropy']=entropy(motifs)
    similarities=[len(set(a)&set(b))/max(1,len(set(a)|set(b))) for a,b in zip(motifs,motifs[1:])]
    f['bar_rhythm_similarity']=float(np.mean(similarities)) if similarities else 1
    f['bar_rhythm_exact_repetition']=float(np.mean([a==b for a,b in zip(motifs,motifs[1:])])) if len(motifs)>1 else 1
    f['bar_rhythm_lag2_repetition']=float(np.mean([a==b for a,b in zip(motifs,motifs[2:])])) if len(motifs)>2 else 1
    # Fast fragments, their starts/ends, and concentration of errors.
    for cutoff in [.1,.125,.15,.2]:
        fast=gaps<cutoff;runs=[];length=0
        for v in fast:
            if v:length+=1
            elif length:runs.append(length);length=0
        if length:runs.append(length)
        f[f'fast{cutoff}_run_mean']=float(np.mean(runs)) if runs else 0
        f[f'fast{cutoff}_run_max']=max(runs,default=0)
        f[f'fast{cutoff}_isolated_fraction']=sum(x==1 for x in runs)/max(1,len(runs))
        f[f'fast{cutoff}_entry_per100']=100*sum(fast[1:]&~fast[:-1])/n
    # Separate pace on individual panels and footwork patterns.
    for col in range(4):
        lane=np.array([t for t in ts if any(x['c']==col for x in rows[t])]);lg=np.diff(lane)
        f[f'lane{col}_fast_fraction']=float(np.mean(lg<.2)) if len(lg) else 0
    masks=[sum(1<<n['c'] for n in g) for g in groups]
    jumps=np.array([len(g)>=2 for g in groups])
    f['jump_incoming_under_02']=float(np.sum(jumps[1:]&(gaps<.2))/n)
    f['jump_outgoing_under_02']=float(np.sum(jumps[:-1]&(gaps<.2))/n)
    f['jump_repeated_panel_under_03']=sum(bool(a&b) and (jumps[i] or jumps[i+1]) and gaps[i]<.3 for i,(a,b) in enumerate(zip(masks,masks[1:])))/n
    pattern=json.loads((ROOT/'assets/patterns'/(name+'.json')).read_text())['sp'][diff]
    sortedbeats=beats.tolist()
    for key in ['crossover','footswitch','sideswitch','jack','doublestep','candle','staircase']:
        event_gaps=[]
        for beat in pattern.get('at',{}).get(key,[]):
            i=bisect.bisect_left(sortedbeats,beat);i=min(n-1,max(1,i))
            if i>1 and abs(sortedbeats[i-1]-beat)<abs(sortedbeats[i]-beat):i-=1
            event_gaps.append(gaps[i-1])
        for cutoff in [.125,.2,.3]:f[f'{key}_under{cutoff}_per100']=100*sum(g<cutoff for g in event_gaps)/n
    # Stop novelty and how soon the next timing demand arrives.
    stops=[s for s in timing['stops'] if ts[0]<=s['st']<=ts[-1]]
    stop_beats=[s['dur']*bpm(s['st']-.001)/60 for s in stops]
    f['stop_beats_entropy']=entropy([round(x*8) for x in stop_beats])
    f['stop_fractional_beat_per100']=100*sum(abs(x-round(x))>.05 for x in stop_beats)/n
    f['stop_total_beats_per100']=100*sum(stop_beats)/n
    f['stop_duration_variation']=float(np.std([s['dur'] for s in stops])) if stops else 0
    restart_gaps=[]
    for s in stops:
        resume=s['st']+s['dur'];i=np.searchsorted(ts,resume-.002)
        if i<n-1:restart_gaps.append(float(ts[i+1]-ts[i]))
    f['restart_following_gap_mean']=float(np.mean(restart_gaps)) if restart_gaps else 0
    f['restart_fast_followups_per100']=100*sum(g<.2 for g in restart_gaps)/n
    # BPM segments: brief doubled pulses should differ from sustained changes.
    durations=[];values=[]
    for i,b in enumerate(bpms):
        start=max(ts[0],b['st']);end=min(ts[-1],b['ed'],bpms[i+1]['st'] if i+1<len(bpms) else ts[-1])
        if end>start:durations.append(end-start);values.append(max(1,b['val']))
    main=Counter()
    for d,v in zip(durations,values):main[v]+=d
    main_bpm=max(main,key=main.get)
    f['main_bpm_time_share']=main[main_bpm]/sum(durations)
    for minimum in [.25,1.,4.]:
        f[f'sustained_bpm_deviation_{minimum}']=sum(d*abs(math.log2(v/main_bpm)) for d,v in zip(durations,values) if d>=minimum)/duration
        f[f'brief_speed_segment_share_{minimum}']=sum(d for d,v in zip(durations,values) if d<minimum and abs(math.log2(v/main_bpm))>.1)/duration
    # Scoring opportunities: jumps and simultaneous hold releases count once.
    releases={(n['b'],n.get('e')) for n in notes if n['t'] in [1,2]}
    scoring_units=len(ts)+len(releases)
    f['great_point_penalty']=400000/scoring_units+10
    f['perfect_fraction_score_penalty']=10*len(ts)
    for k,v in list(f.items()):f[k]=float(v)
    assert all(math.isfinite(v) for v in f.values()),name
    return f
