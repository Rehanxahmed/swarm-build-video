#!/usr/bin/env python3
"""Record a Demo film: a real flow of the app, driven by a UI test.

    python3 record_flow.py --app path/to/MyApp.app --flow path/to/flow-copy [options]

--flow is a copy of the skill's flow/ folder with Flow.swift written for this
app. The script builds it, then, on the dedicated "Swarm Recorder" simulator:

  1. installs the app, does one unrecorded warm-up launch, then launches it
     with -swarm-touches (so the app draws each finger as a dot);
  2. runs the flow, which brings the app up front and says it's ready;
  3. starts recording, waits --settle seconds, and cues the flow;
  4. stops recording --hold seconds after the flow ends.

No test runner, launch animation or app switch ends up in the take.

Writes <out>/<name>.mov and <out>/<name>.json, the captions timed against
the take ({"captions": [{"at": s, "text": "..."}], "start": s, "end": s}),
for render.py --mode demo --captions.

Options:
  --app PATH        the built .app (simulator build), required
  --flow DIR        the flow folder (holds SwarmFlow.xcodeproj), required
  --args "..."      extra launch arguments for the app (e.g. "-demo")
  --out DIR         where the take goes (default: ./swarm-takes)
  --name NAME       take file name without extension (default: flow)
  --sim NAME        simulator name (default: "Swarm Recorder")
  --time HH:MM      status bar clock (default: 9:41)
  --settle N        seconds recorded before the cue (default 1.0)
  --hold N          seconds recorded after the flow ends (default 1.5)
  --timeout N       give up on a flow that runs longer than this (default 240)
  --dark            record in dark appearance
  --keep            leave the simulator booted afterwards
"""
import argparse, glob, json, os, plistlib, signal, subprocess, sys, threading, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from record import find_or_create, prepare, sim, wait_until  # noqa: E402


def build_flow(flow):
    proj = os.path.join(flow, 'SwarmFlow.xcodeproj')
    if not os.path.isdir(proj):
        sys.exit(f'{flow} has no SwarmFlow.xcodeproj. Copy the skill\'s flow/ folder and write Flow.swift in it.')
    derived = os.path.join(flow, 'build')
    r = subprocess.run(['xcodebuild', 'build-for-testing', '-project', proj, '-scheme', 'SwarmFlow',
                        '-destination', 'generic/platform=iOS Simulator', '-derivedDataPath', derived,
                        'CODE_SIGNING_ALLOWED=NO'], capture_output=True, text=True)
    if r.returncode != 0:
        errors = [l for l in r.stdout.splitlines() if 'error:' in l]
        sys.exit('The flow does not build:\n' + '\n'.join(errors[:20] or r.stdout.splitlines()[-30:]))
    runs = sorted(glob.glob(os.path.join(derived, 'Build', 'Products', '*.xctestrun')), key=os.path.getmtime)
    if not runs:
        sys.exit('Built the flow but found no .xctestrun file.')
    return runs[-1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--app', required=True)
    ap.add_argument('--flow', required=True)
    ap.add_argument('--args', default='')
    ap.add_argument('--out', default='swarm-takes')
    ap.add_argument('--name', default='flow')
    ap.add_argument('--sim', default='Swarm Recorder')
    ap.add_argument('--time', default='9:41')
    ap.add_argument('--settle', type=float, default=1.0)
    ap.add_argument('--hold', type=float, default=1.5)
    ap.add_argument('--timeout', type=float, default=240)
    ap.add_argument('--dark', action='store_true')
    ap.add_argument('--keep', action='store_true')
    o = ap.parse_args()

    app = os.path.abspath(o.app.rstrip('/'))
    info = os.path.join(app, 'Info.plist')
    if not os.path.exists(info):
        sys.exit(f'{app} is not an .app bundle (no Info.plist). Build for the simulator first.')
    bundle = plistlib.load(open(info, 'rb'))['CFBundleIdentifier']
    extra = o.args.split()
    flow = os.path.abspath(o.flow)
    os.makedirs(o.out, exist_ok=True)
    out = os.path.abspath(os.path.join(o.out, o.name + '.mov'))
    flow_log = os.path.abspath(os.path.join(o.out, o.name + '-flow.json'))
    test_log = os.path.abspath(os.path.join(o.out, o.name + '-xcodebuild.log'))
    for f in (out, flow_log):
        if os.path.exists(f):
            os.remove(f)

    print('building the flow…', file=sys.stderr)
    xctestrun = build_flow(flow)

    udid = find_or_create(o.sim)
    prepare(udid, o.dark, o.time)
    sim('install', udid, app, check=True)
    sim('launch', udid, bundle, *extra, check=True)       # warm-up, not recorded
    wait_until(5)
    sim('terminate', udid, bundle)
    wait_until(1)
    sim('launch', udid, bundle, '-swarm-touches', *extra, check=True)
    wait_until(3)

    # listen for "ready" before the flow can send it
    ready = subprocess.Popen(['xcrun', 'simctl', 'spawn', udid, 'notifyutil', '-1', 'swarm.ready'],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    env = dict(os.environ, TEST_RUNNER_SWARM_APP=bundle, TEST_RUNNER_SWARM_LOG=flow_log)
    log = open(test_log, 'w')
    test = subprocess.Popen(['xcodebuild', 'test-without-building', '-xctestrun', xctestrun,
                             '-destination', f'id={udid}'], stdout=log, stderr=subprocess.STDOUT, env=env)

    def stop(proc):
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()

    deadline = time.monotonic() + 180
    while ready.poll() is None:
        if test.poll() is not None or time.monotonic() > deadline:
            stop(ready)
            stop(test)
            tail = open(test_log).read().splitlines()[-25:]
            sys.exit('The flow never said it was ready (SwarmDemo.start()).\n' + '\n'.join(tail))
        time.sleep(0.05)
    wait_until(0.8)                                       # the switch back to the app settles

    rec = subprocess.Popen(['xcrun', 'simctl', 'io', udid, 'recordVideo', '--codec', 'h264', '--force', out],
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    started = threading.Event()
    rec_at = [0.0]

    def watch():
        for line in rec.stderr:
            if 'Recording started' in line and not started.is_set():
                rec_at[0] = time.monotonic()
                started.set()
    threading.Thread(target=watch, daemon=True).start()
    if not started.wait(15):
        stop(rec)
        stop(test)
        sys.exit('recordVideo never started.')
    wait_until(o.settle)
    sim('spawn', udid, 'notifyutil', '-p', 'swarm.go')
    go = time.monotonic() - rec_at[0]

    try:
        test.wait(timeout=o.timeout)
    except subprocess.TimeoutExpired:
        stop(test)
        print(f'warning: the flow ran past {o.timeout:g} s and was stopped', file=sys.stderr)
    wait_until(o.hold)
    rec.send_signal(signal.SIGINT)
    try:
        rec.wait(timeout=30)
    except subprocess.TimeoutExpired:
        rec.kill()
    log.close()
    sim('terminate', udid, bundle)
    if not o.keep:
        sim('shutdown', udid)

    text = open(test_log).read()
    if test.returncode != 0 or 'TEST EXECUTE FAILED' in text or 'TEST FAILED' in text:
        fails = [l for l in text.splitlines() if 'error:' in l or 'failed' in l.lower()][:15]
        print('warning: the flow failed part way, so the take may stop early:\n  ' + '\n  '.join(fails)
              + f'\n  (full log: {test_log})', file=sys.stderr)
    if not os.path.exists(out) or os.path.getsize(out) < 10_000:
        sys.exit('The take is missing or empty. Run with --keep and check the simulator.')

    flow_data = json.load(open(flow_log)) if os.path.exists(flow_log) else {'captions': []}
    timed = {'captions': [{'at': round(go + c['at'], 3), 'text': c['text']} for c in flow_data.get('captions', [])],
             'start': round(go, 3)}
    if flow_data.get('end') is not None:
        timed['end'] = round(go + flow_data['end'], 3)
    json.dump(timed, open(os.path.join(o.out, o.name + '.json'), 'w'), indent=2)
    print(out)
    print(os.path.abspath(os.path.join(o.out, o.name + '.json')))


if __name__ == '__main__':
    main()
