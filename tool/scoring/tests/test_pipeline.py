"""Freshness, boundary and coverage regressions; no model dependencies needed."""
import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fingerprint import input_hash, tier_for
from validate_content import validate


class FingerprintTest(unittest.TestCase):
    def setUp(self):
        self.song = dict(name='A', sp=dict(hard=14), dp={}, per_chart=False,
                         charts=[dict(bpms=[dict(st=0, ed=10, val=120)], stops=[])])
        self.steps = dict(charts=dict(sp=dict(hard=dict(notes=[dict(s=0, b=0, c=0, t=0), dict(s=1, b=2, c=1, t=0)]))))

    def fingerprint(self, song=None, steps=None, model='scoring-v31', engine='engine'):
        return input_hash(song or self.song, steps or self.steps, 'hard', model, engine)

    def test_annotations_and_unrelated_charts_do_not_invalidate(self):
        changed = copy.deepcopy(self.song)
        changed.update(title='new', scoring_tiers={'sp': {'hard': 14.9}})
        changed['sp']['easy'] = 4
        self.assertEqual(self.fingerprint(), self.fingerprint(changed))
        steps = copy.deepcopy(self.steps)
        steps['charts']['sp']['easy'] = dict(notes=[])
        self.assertEqual(self.fingerprint(), self.fingerprint(steps=steps))

    def test_notes_timing_level_model_and_engine_invalidate(self):
        baseline = self.fingerprint()
        for field in ('s', 'b', 'c', 't', 'es', 'eb'):
            changed = copy.deepcopy(self.steps)
            changed['charts']['sp']['hard']['notes'][0][field] = 3
            self.assertNotEqual(baseline, self.fingerprint(steps=changed))
        for field, value in [('sp', dict(hard=15)), ('charts', [dict(bpms=[], stops=[])])]:
            changed = {**self.song, field: value}
            self.assertNotEqual(baseline, self.fingerprint(changed))
        self.assertNotEqual(baseline, self.fingerprint(model='scoring-v32'))
        self.assertNotEqual(baseline, self.fingerprint(engine='next'))

    def test_per_chart_timing_follows_available_difficulties(self):
        song = dict(self.song, per_chart=True, sp=dict(easy=4, hard=14),
                    charts=[dict(bpms=[1], stops=[]), dict(bpms=[2], stops=[]), dict(bpms=[3], stops=[])])
        changed = copy.deepcopy(song)
        changed['charts'][0]['bpms'] = [4]
        self.assertEqual(self.fingerprint(song), self.fingerprint(changed))
        changed['charts'][2]['bpms'] = [5]
        self.assertNotEqual(self.fingerprint(song), self.fingerprint(changed))

    def test_boundaries_floor_and_clamp(self):
        for position, expected in [(-.1, 14.), (0.049999, 14.), (.05, 14.05), (.9, 14.9), (1.1, 14.95)]:
            self.assertEqual(tier_for(14, position), expected)
        self.assertEqual(tier_for(19, .95), 19.9)
        with self.assertRaises(ValueError):
            tier_for(14, float('nan'))

    def test_validator_rejects_stale_and_lost_coverage(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for kind in ('songs', 'steps'):
                (root/kind).mkdir()
            self.song['scoring_tiers'] = dict(schema=1, model='scoring-v31', engine='engine',
                sp=dict(hard=dict(tier=14.9, position=.901, input_hash=self.fingerprint())))
            song_file = root/'songs/A.json'
            song_file.write_text(json.dumps(self.song))
            (root/'steps/A.json').write_text(json.dumps(self.steps))
            self.assertEqual(validate(root/'songs', root/'steps')['problems'], [])
            self.steps['charts']['sp']['hard']['notes'][0]['s'] = .1
            (root/'steps/A.json').write_text(json.dumps(self.steps))
            self.assertIn('Stale', validate(root/'songs', root/'steps')['problems'][0])
            previous = root/'previous.json'
            previous.write_text(json.dumps([self.song]))
            self.song.pop('scoring_tiers')
            song_file.write_text(json.dumps(self.song))
            self.assertIn('lost coverage', validate(root/'songs', root/'steps', previous)['problems'][0])

if __name__ == '__main__':
    unittest.main()
