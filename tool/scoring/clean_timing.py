"""Frozen chart-derived scoring measurements."""
import bisect, hashlib, json, math
from collections import Counter, defaultdict
from pathlib import Path
import numpy as np
import visibility_features, rate, learn, features_v2
from unittest.mock import patch
ROOT = Path('.')


def calculate(name,diff,baseline,root=ROOT):
    rate.ROOT=root;learn.ROOT=root;features_v2.ROOT=root;song_path=root/'assets/songs'/(name+'.json');song=json.loads(song_path.read_text());notes=json.loads((root/'assets/steps'/(name+'.json')).read_text())['charts']['sp'][diff]['notes'];_,intervals=visibility_features.calculate(song,notes,diff,True);timing_keys=[k for k in baseline if any(s in k for s in ['bpm','stop','restart','reading']) and not k.startswith(('visibility_','cleaned_'))]
    if not intervals:return {'cleaned_'+k:float(baseline[k]) for k in timing_keys}
    clean=json.loads(json.dumps(song));keys=['beginner','easy','medium','hard','challenge'];index=0
    if song.get('per_chart'):
        first=next(i for i,k in enumerate(keys) if song.get('sp',{}).get(k) is not None or song.get('dp',{}).get(k) is not None);index=min(len(song['charts'])-1,keys.index(diff)-first)
    timing=clean['charts'][index]
    for a,b,headline in intervals:
        for bpm in timing['bpms']:
            if a-.00001<=bpm['st']<b-.00001:bpm['val']=float(headline)
        timing['stops']=[s for s in timing['stops'] if not (s['st']>=a-.00001 and s['st']+s['dur']<=b+.00001)]
    encoded=json.dumps(clean);read=Path.read_text
    def override(path,*a,**kw):return encoded if path==song_path else read(path,*a,**kw)
    # This changes a private feature-extraction view only. Notes, wall times,
    # beat positions and app content are never edited. Pulse descriptors remain.
    with patch.object(Path,'read_text',override):
        features={**learn.extract(rate.features(name,diff)),**features_v2.extra_features(name,diff)}
    return {'cleaned_'+k:float(features[k]) for k in timing_keys}
