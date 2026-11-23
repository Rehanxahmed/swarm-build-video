#!/usr/bin/env python3
"""Record a swarm build on its own simulator.

    python3 record.py --app path/to/MyApp.app --seconds 13 [options]

Uses a dedicated simulator ("Swarm Recorder", created on first use) so the
person's everyday simulator is never touched. Pins the status bar to 9:41,
installs the app, does one unrecorded warm-up launch, then launches with
`-swarm -swarm-cue`. That shows the screen as an empty page waiting for its
cue. Recording starts, the cue goes in (Darwin notification "swarm.start"),
and the build plays. There's no launch animation in the take.

Options:
  --app PATH        the built .app (simulator build), required
  --seconds N       how long to record after the cue (build length + ~2.5 s)
  --args "..."      extra launch arguments for both launches (e.g. "-demo")
  --out DIR         where the take goes (default: ./swarm-takes)
  --name NAME       take file name without extension (default: take)
  --sim NAME        simulator name (default: "Swarm Recorder")
  --time HH:MM      status bar clock (default: 9:41)
  --settle N        seconds recorded before the cue (default 1.5; use 3 for a
                    Before → After film so the old screen gets its hold)
  --dark            record in dark appearance
  --keep            leave the simulator booted afterwards

Prints the path of the .mov when done.
"""
import argparse, json, os, plistlib, signal, subprocess, sys, time

PREFERRED = ['iPhone 17 Pro', 'iPhone 16 Pro', 'iPhone 15 Pro', 'iPhone 17', 'iPhone 16', 'iPhone 15']


def sim(*args, check=False):
    r = subprocess.run(['xcrun', 'simctl', *args], capture_output=True, text=True)
    if check and r.returncode != 0:
        sys.exit(f"simctl {' '.join(args)} failed:\n{r.stderr.strip()}")
    return r


def wait_until(seconds):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        time.sleep(min(0.05, max(0, end - time.monotonic())))


def find_or_create(name):
    devices = json.loads(sim('list', 'devices', '-j', check=True).stdout)['devices']
    for runtime, items in devices.items():
        if 'iOS' not in runtime:
            continue
        for d in items:
            if d['name'] == name and d.get('isAvailable', True):
                return d['udid']
    runtimes = [r for r in json.loads(sim('list', 'runtimes', '-j', check=True).stdout)['runtimes']
                if r.get('platform', 'iOS') == 'iOS' and r.get('isAvailable', True) and 'iOS' in r['name']]
    if not runtimes:
        sys.exit('No iOS simulator runtime installed. Install one in Xcode > Settings > Components.')
    runtime = sorted(runtimes, key=lambda r: [int(x) for x in r['version'].split('.')])[-1]
    supported = {t['name']: t['identifier'] for t in runtime.get('supportedDeviceTypes', [])}
    if not supported:
        supported = {t['name']: t['identifier'] for t in json.loads(sim('list', 'devicetypes', '-j').stdout)['devicetypes']}
    kind = next((supported[n] for n in PREFERRED if n in supported), None)
    if not kind:
        kind = next((v for k, v in supported.items() if k.startswith('iPhone')), None)
    if not kind:
        sys.exit('No iPhone simulator type available.')
    udid = sim('create', name, kind, runtime['identifier'], check=True).stdout.strip()
    print(f'created simulator "{name}" ({udid}); first boot takes about a minute', file=sys.stderr)
    # A brand-new simulator shows setup banners (Apple Intelligence, Tips…)
    # for a while after its first boot. Let them come and go now, off camera.
    sim('boot', udid)
    sim('bootstatus', udid, '-b', check=True)
    wait_until(45)
    return udid


def prepare(udid, dark=False, clock='9:41'):
    """Boot, set the appearance and pin a clean status bar."""
    sim('boot', udid)
    sim('bootstatus', udid, '-b', check=True)
    sim('ui', udid, 'appearance', 'dark' if dark else 'light')
    sim('status_bar', udid, 'override', '--time', clock, '--dataNetwork', 'wifi', '--wifiMode', 'active',
        '--wifiBars', '3', '--cellularMode', 'active', '--cellularBars', '4', '--batteryState', 'discharging',
        '--batteryLevel', '100', '--operatorName', '')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--app', required=True)
    ap.add_argument('--seconds', type=float, default=13)
    ap.add_argument('--args', default='')
    ap.add_argument('--out', default='swarm-takes')
    ap.add_argument('--name', default='take')
    ap.add_argument('--sim', default='Swarm Recorder')
    ap.add_argument('--time', default='9:41')
    ap.add_argument('--settle', type=float, default=1.5)
    ap.add_argument('--dark', action='store_true')
    ap.add_argument('--keep', action='store_true')
    o = ap.parse_args()

    app = os.path.abspath(o.app.rstrip('/'))
    info = os.path.join(app, 'Info.plist')
    if not os.path.exists(info):
        sys.exit(f'{app} is not an .app bundle (no Info.plist). Build for the simulator first.')
    bundle = plistlib.load(open(info, 'rb'))['CFBundleIdentifier']
    extra = o.args.split()

    udid = find_or_create(o.sim)
    prepare(udid, o.dark, o.time)
    sim('install', udid, app, check=True)

    # one unrecorded launch, so the take isn't a cold start
    sim('launch', udid, bundle, *extra, check=True)
    wait_until(6)
    sim('terminate', udid, bundle)
    wait_until(1)

    # the screen comes up as an empty page, waiting for its cue
    sim('launch', udid, bundle, '-swarm', '-swarm-cue', *extra, check=True)
    wait_until(3.5)

    os.makedirs(o.out, exist_ok=True)
    out = os.path.abspath(os.path.join(o.out, o.name + '.mov'))
    if os.path.exists(out):
        os.remove(out)
    rec = subprocess.Popen(['xcrun', 'simctl', 'io', udid, 'recordVideo', '--codec', 'h264', '--force', out],
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    wait_until(max(1.5, o.settle))
    if rec.poll() is not None:
        sys.exit('recordVideo stopped straight away:\n' + rec.stderr.read())
    cue = sim('spawn', udid, 'notifyutil', '-p', 'swarm.start')
    if cue.returncode != 0:
        print('warning: could not post the cue; the build will start by itself after 30 s', file=sys.stderr)
    wait_until(o.seconds)
    rec.send_signal(signal.SIGINT)
    try:
        rec.wait(timeout=30)
    except subprocess.TimeoutExpired:
        rec.kill()
    sim('terminate', udid, bundle)
    if not o.keep:
        sim('shutdown', udid)
    if not os.path.exists(out) or os.path.getsize(out) < 10_000:
        sys.exit('The take is missing or empty. Try again; if it keeps failing, run with --keep and check the simulator.')
    print(out)


if __name__ == '__main__':
    main()
