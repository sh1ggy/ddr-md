"""Frozen chart-derived scoring measurements."""
import bisect, hashlib, json, math
from collections import Counter, defaultdict
from pathlib import Path
import numpy as np


def calculate(notes,base):
    steps=len({n['s'] for n in notes if n['t']!=3});freezes=len({(n['b'],n.get('e')) for n in notes if n['t'] in [1,2]});shocks=len({n['s'] for n in notes if n['t']==3});total=steps+freezes+shocks;great=400000/total+10
    f={'scoring_units':float(total),'scoring_tight_fraction':steps/total,'scoring_freeze_fraction':freezes/total,'scoring_shock_fraction':shocks/total,'scoring_great_penalty':great,'scoring_good_penalty':800000/total+10,'scoring_miss_penalty':1000000/total,'scoring_great_loss_per_error_rate':steps*great,'scoring_hold_loss_per_error_rate':freezes*1000000/total,'scoring_shock_loss_per_error_rate':shocks*1000000/total}
    # These coefficients convert an error probability per event to expected
    # money-score loss; no error probability or difficulty weight is assumed.
    rates=['pattern_crossover','pattern_footswitch','pattern_sideswitch','pattern_jack','pattern_doublestep','pattern_bracket','foot_moving_fast_per100','foot_same_panel_fast_per100','restarts_note_under_0.25_per100','restart_fast_followups_per100']
    for key in rates:
        value=base.get('cleaned_'+key,base.get(key,0.));f['scoring_exposure_'+key]=value*steps/100*great
    for key in ['ternary_boundary_fraction','gap_ratio_rare','jump_incoming_under_02','hold_overlap_fraction']:
        f['scoring_exposure_'+key]=base.get(key,0.)*steps*great
    return f
