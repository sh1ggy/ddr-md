"""Frozen chart-derived scoring measurements."""
import bisect, hashlib, json, math
from collections import Counter, defaultdict
from pathlib import Path
import numpy as np


def calculate(song,notes,diff,return_intervals=False):
    times=np.array(sorted({n['s'] for n in notes if n['t']!=3}));first,last=times[0],times[-1];keys=['beginner','easy','medium','hard','challenge'];index=0
    if song.get('per_chart'):
        start=next(i for i,k in enumerate(keys) if song.get('sp',{}).get(k) is not None or song.get('dp',{}).get(k) is not None);index=min(len(song['charts'])-1,keys.index(diff)-start)
    timing=song['charts'][index];bpms=sorted(timing['bpms'],key=lambda b:b['st']);starts=[b['st'] for b in bpms];stops=[s for s in timing['stops'] if s['dur']>0 and s['st']<last and s['st']+s['dur']>first]
    boundaries={first,last}
    for b in bpms:
        if first<b['st']<last:boundaries.add(b['st'])
    for s in stops:boundaries.update([max(first,s['st']),min(last,s['st']+s['dur'])])
    edges=np.array(sorted(boundaries));durations=np.diff(edges);values=[]
    for a,b in zip(edges,edges[1:]):
        mid=(a+b)/2;bpm=max(0.,bpms[max(0,bisect.bisect_right(starts,mid)-1)]['val']);frozen=any(s['st']<=mid<s['st']+s['dur'] for s in stops);values.append(0. if frozen else bpm)
    values=np.array(values);positive=values>0;totals=Counter()
    for d,v in zip(durations,values):
        if v>0:totals[v]+=d
    headline=max(totals,key=totals.get);rate=headline/60.;cum=np.r_[0.,np.cumsum(durations*values/60.)];abs_cum=np.r_[0.,np.cumsum(durations*np.abs(values-headline)/60.)]
    def integrate(t,absolute=False):
        t=np.clip(t,first,last);indices=np.clip(np.searchsorted(edges,t,side='right')-1,0,len(values)-1);c=abs_cum if absolute else cum;v=np.abs(values-headline) if absolute else values;return c[indices]+(t-edges[indices])*v[indices]/60.
    f={'visibility_headline_bpm':float(headline),'visibility_effective_min_bpm':float(min(values[positive])),'visibility_effective_max_bpm':float(max(values)),'visibility_frozen_share':float(sum(durations[~positive])/(last-first))}
    beat_by_time={n['s']:n['b'] for n in notes if n['t']!=3};expected=np.diff([beat_by_time[t] for t in times]);measured=integrate(times[1:])-integrate(times[:-1]);fit_error=np.abs(expected-measured)
    f['visibility_timing_fit_error_mean']=float(np.mean(fit_error));f['visibility_timing_fit_error_p95']=float(np.percentile(fit_error,95));f['visibility_timing_fit_error_max']=float(max(fit_error))
    sample=np.unique(np.r_[times,np.arange(first,last,.1)])
    for window in [.125,.25,.5,1.,2.]:
        s=sample[sample+window<=last];travel=(integrate(s+window)-integrate(s))/(rate*window) if len(s) else np.array([1.]);absolute=(integrate(s+window,True)-integrate(s,True))/(rate*window) if len(s) else np.array([0.]);deviation=np.abs(travel-1.);cancel=np.maximum(0,absolute-deviation)
        for label,x in [('travel',travel),('deviation',deviation),('cancel',cancel)]:
            f[f'visibility_{label}_{window}_mean']=float(np.mean(x));f[f'visibility_{label}_{window}_p95']=float(np.percentile(x,95));f[f'visibility_{label}_{window}_max']=float(max(x))
        f[f'visibility_travel_{window}_p05']=float(np.percentile(travel,5));f[f'visibility_deviation_{window}_over10pct']=float(np.mean(deviation>.1))
        # Note-weighted exposure: timing outside note contexts has less weight.
        s=times[(times>=first+window)&(times<=last-window)];before=(integrate(s)-integrate(s-window))/(rate*window);after=(integrate(s+window)-integrate(s))/(rate*window)
        f[f'visibility_note_{window}_change_mean']=float(np.mean(abs(after-before))) if len(s) else 0.
        f[f'visibility_note_{window}_deviation_mean']=float(np.mean(abs(after-1))) if len(s) else 0.
    # Group contiguous departures from headline pace, including a freeze followed
    # immediately by a fast pulse. Measure both excursion and final displacement.
    events=[];i=0
    while i<len(values):
        if abs(values[i]-headline)<.01:i+=1;continue
        j=i+1
        while j<len(values) and abs(values[j]-headline)>=.01:j+=1
        a,b=edges[i],edges[j];increments=durations[i:j]*(values[i:j]-headline)/60.;path=np.r_[0.,np.cumsum(increments)];net=abs(path[-1]);excursion=max(path)-min(path);interior=int(np.sum((times>a+.002)&(times<b-.002)));events.append((b-a,net,excursion,interior,a,b));i=j
    f['visibility_events_per100']=len(events)*100/len(times);f['visibility_event_net_per_row']=sum(e[1] for e in events)/len(times);f['visibility_event_excursion_per_row']=sum(e[2] for e in events)/len(times)
    f['visibility_compensated_events_per100']=sum(e[1]<.05 and e[2]>.05 for e in events)*100/len(times)
    f['visibility_compensated_no_inner_note_per100']=sum(e[1]<.05 and e[2]>.05 and e[3]==0 for e in events)*100/len(times)
    for duration in [.25,.5,1.,2.]:
        subset=[e for e in events if e[0]>=duration];f[f'visibility_event_over{duration}_per100']=len(subset)*100/len(times);f[f'visibility_event_over{duration}_time_share']=sum(e[0] for e in subset)/(last-first)
    for excursion in [.125,.25,.5,1.,2.]:f[f'visibility_event_excursion_over{excursion}_per100']=sum(e[2]>=excursion for e in events)*100/len(times)
    assert all(math.isfinite(v) for v in f.values())
    if return_intervals:
        intervals=[(e[4],e[5],headline) for e in events if e[0]<=.5 and e[1]<.02 and .05<e[2]<=.5 and e[3]==0]
        return f,intervals
    return f
