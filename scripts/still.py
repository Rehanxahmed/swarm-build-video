#!/usr/bin/env python3
"""Freeze the build at a few moments and tile the screenshots into one image,
to check the script before recording.

    python3 still.py --app path/to/MyApp.app --at 1 2.5 4 6 8 99 [--out stills.png]

Each moment is a fresh launch with `-swarm -swarm-at <t>` on the "Swarm
Recorder" simulator; 99 (anything past the end) shows the finished screen.
Options: --args "..." extra launch arguments, --sim NAME, --dark, --keep.
"""
import argparse, os, plistlib, subprocess, sys, tempfile, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from record import find_or_create, prepare, sim, wait_until  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--app', required=True)
    ap.add_argument('--at', type=float, nargs='+', required=True)
    ap.add_argument('--out', default='swarm-stills.png')
    ap.add_argument('--args', default='')
    ap.add_argument('--sim', default='Swarm Recorder')
    ap.add_argument('--dark', action='store_true')
    ap.add_argument('--keep', action='store_true')
    o = ap.parse_args()

    app = os.path.abspath(o.app.rstrip('/'))
    bundle = plistlib.load(open(os.path.join(app, 'Info.plist'), 'rb'))['CFBundleIdentifier']
    udid = find_or_create(o.sim)
    prepare(udid, o.dark)
    sim('install', udid, app, check=True)

    tmp = tempfile.mkdtemp(prefix='swarm-stills-')
    shots = []
    for t in o.at:
        sim('terminate', udid, bundle)
        sim('launch', udid, bundle, '-swarm', '-swarm-at', str(t), *o.args.split(), check=True)
        wait_until(2.6)
        path = os.path.join(tmp, f'{len(shots):02d}.png')
        sim('io', udid, 'screenshot', path, check=True)
        shots.append(path)
    sim('terminate', udid, bundle)
    if not o.keep:
        sim('shutdown', udid)

    # label-free tile, in the order asked, 320 px wide each
    inputs = []
    for p in shots:
        inputs += ['-i', p]
    n = len(shots)
    chain = ''.join(f'[{i}:v]scale=320:-2[s{i}];' for i in range(n))
    chain += ''.join(f'[s{i}]' for i in range(n)) + f'hstack=inputs={n}' if n > 1 else '[s0]copy'
    out = os.path.abspath(o.out)
    r = subprocess.run(['ffmpeg', '-v', 'error', '-y', *inputs, '-filter_complex', chain, '-frames:v', '1', out],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(r.stderr)
    print(out)
    print('moments: ' + ', '.join(f'{t:g}s' for t in o.at))


if __name__ == '__main__':
    main()
