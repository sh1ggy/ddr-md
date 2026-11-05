"""One chart per subprocess; fixed pad/feet and precision-goal call order."""
import ctypes
import json
import math
import subprocess
import sys

FIELDS = ('overall', 'stream', 'jumpstream', 'handstream', 'stamina', 'jackspeed', 'chordjack', 'technical')

class NoteInfo(ctypes.Structure):
    _fields_ = [('notes', ctypes.c_uint), ('rowTime', ctypes.c_float)]

class SSR(ctypes.Structure):
    _fields_ = [(name, ctypes.c_float) for name in FIELDS]


def evaluate(notes, feet, library):
    rows = {}
    for n in notes:
        if n['t'] != 3:
            rows[n['s']] = rows.get(n['s'], 0) | (1 << n['c'])
    result = subprocess.run([sys.executable, __file__, str(library)],
                            input=json.dumps(dict(pad=sorted(rows.items()), feet=feet)),
                            capture_output=True, text=True, check=True)
    return json.loads(result.stdout)


def worker(request, library):
    lib = ctypes.CDLL(library)
    lib.create_calc.restype = ctypes.c_void_p
    args = [ctypes.c_void_p, ctypes.POINTER(NoteInfo), ctypes.c_size_t, ctypes.c_float, ctypes.c_float]
    for name in ('calc_ssr', 'calc_ssr_research'):
        fn = getattr(lib, name)
        fn.argtypes = args
        fn.restype = SSR
    lib.destroy_calc.argtypes = [ctypes.c_void_p]
    handle = lib.create_calc()
    def calculate(input_rows):
        rows = {float(t): int(mask) for t, mask in input_rows}
        times = sorted(rows)
        if len(times) < 2:
            return {f'mina_wife_{goal}_{name}': 0. for goal in (930, 990, 999) for name in FIELDS}
        array = (NoteInfo * len(times))(*[NoteInfo(rows[t], t-times[0]+.1) for t in times])
        out, valid = {}, True
        for goal in (930, 990, 999):
            fn = lib.calc_ssr_research if goal > 965 else lib.calc_ssr
            value = fn(handle, array, len(times), 1., goal/1000)
            for name in FIELDS:
                v = float(getattr(value, name))
                valid &= math.isfinite(v)
                out[f'mina_wife_{goal}_{name}'] = v if math.isfinite(v) else 0.
        for name in FIELDS:
            out['mina_precision_delta_'+name] = out[f'mina_wife_999_{name}']-out[f'mina_wife_930_{name}']
            out['mina_precision_ratio_'+name] = out[f'mina_wife_999_{name}']/max(.1, out[f'mina_wife_930_{name}'])
        out['mina_valid'] = float(valid)
        return out
    try:
        out = {'pad_'+k: v for k, v in calculate(request['pad']).items()}
        out.update({'feet_'+k: v for k, v in calculate(request['feet']).items()})
        return out
    finally:
        lib.destroy_calc(handle)

if __name__ == '__main__':
    print(json.dumps(worker(json.load(sys.stdin), sys.argv[1]), allow_nan=False))
