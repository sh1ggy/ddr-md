"""Chart density, rhythm and canonical pattern measurements."""
import bisect, json, math
from pathlib import Path
ROOT = Path('.')
PATTERN_WEIGHTS = dict(crossover=1, footswitch=1, sideswitch=1, jack=1, doublestep=1.5, bracket=1.5)

def read(kind, name):
    return json.loads((ROOT / 'assets' / kind / (name + '.json')).read_text())

def peak(times, seconds):
    # Maximum row count in a half-open rolling window / full window duration.
    j = 0
    best = 0
    for i, t in enumerate(times):
        while j < len(times) and times[j] < t + seconds - 1e-9:
            j += 1
        best = max(best, j-i)
    return best / seconds

def features(name, diff):
    song = read('songs', name)
    notes = [n for n in read('steps', name)['charts']['sp'][diff]['notes']
             if n['t'] != 3]
    pattern = read('patterns', name)['sp'][diff]
    grouped = {}
    for n in notes:
        grouped.setdefault(n['s'], []).append(n)
    times = sorted(grouped)
    count = len(times)
    assert count == pattern['steps'], (name, diff, count, pattern['steps'])
    duration = times[-1] - times[0]
    gaps = [b-a for a,b in zip(times,times[1:])]
    assert all(x > 0 for x in gaps)
    # Technique counts from the app's existing default parity, weighted by speed.
    # A 250 ms incoming gap is weight 1; weights are bounded to [0.25, 3].
    beat_index = {n['b']: i for i,t in enumerate(times) for n in grouped[t]}
    beats = sorted(beat_index)
    def row_index(b):
        j=bisect.bisect_left(beats,b)
        near=min(beats[max(0,j-1):min(len(beats),j+1)],key=lambda x:abs(x-b))
        assert abs(near-b)<.0011,(name,diff,b,near)
        return beat_index[near]
    def speed(i):
        gap = gaps[max(i-1,0)]
        return min(3, max(.25, (.25 / max(gap,.05)) ** 2))
    tech = sum(w * speed(row_index(b)) for key,w in PATTERN_WEIGHTS.items()
               for b in pattern.get('at',{}).get(key,[]))
    tech += sum(speed(i) for i,t in enumerate(times) if len(grouped[t]) >= 2)
    tech = 100 * tech / count
    # Rhythm: changes between adjacent real-time gaps; rests over .75s excluded.
    changes = [min(2, abs(math.log2(b/a))) for a,b in zip(gaps,gaps[1:])
               if a <= .75 and b <= .75]
    rhythm = sum(changes) / len(changes) if changes else 0
    chart_index = 0
    if song.get('per_chart'):
        keys = ['beginner','easy','medium','hard','challenge']
        first = next(i for i,k in enumerate(keys)
                     if song.get('sp',{}).get(k) is not None or song.get('dp',{}).get(k) is not None)
        chart_index = min(len(song['charts'])-1, keys.index(diff)-first)
    timing = song['charts'][chart_index]
    bpms = sorted(timing['bpms'], key=lambda x:x['st'])
    # Clip timing spans to the played section, resolving overlaps by latest start.
    spans = []
    for i,b in enumerate(bpms):
        start = max(times[0], b['st'])
        end = min(times[-1], b['ed'], bpms[i+1]['st'] if i+1<len(bpms) else times[-1])
        if end > start and b['val'] > 0:
            spans.append((end-start,b['val']))
    total = sum(d for d,b in spans)
    acc = 0
    base = 0
    for d,b in sorted(spans,key=lambda p:p[1]):
        acc += d
        if acc >= total/2:
            base=b
            break
    spread = math.sqrt(sum(d*math.log2(b/base)**2 for d,b in spans)/total)
    stops = [s for s in timing['stops'] if times[0] <= s['st'] <= times[-1]]
    stop_burden = 100 * sum(min(2,s['dur']/.5) for s in stops) / count
    return dict(name=name,difficulty=diff,rows=count,arrows=len(notes),
                duration=duration,jumps=sum(len(grouped[t])>=2 for t in times),
                holds=sum(n['t'] in (1,2) for n in notes),
                stop_count=len(stops),stop_seconds=sum(s['dur'] for s in stops),
                bpm_min=min(b['val'] for b in bpms),bpm_max=max(b['val'] for b in bpms),
                burst=peak(times,2),average=count/duration,sustained=peak(times,8),
                technique=tech,rhythm=rhythm,reading=stop_burden+2*spread,
                stop_burden=stop_burden,bpm_spread=spread,counts=pattern['counts'])
