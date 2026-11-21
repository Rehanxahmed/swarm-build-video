#!/usr/bin/env python3
"""Turn a take into the finished videos.

    python3 render.py <take.mov> --out ~/Movies/Swarm/MyApp-Home [--duration 12]

Finds where the build starts and stops on its own (the first and last frames
where anything moves). Then it cuts from just before the first cursor to a
held finished screen, and writes:

  <out>.mp4          the phone mockup on a pale plate, 1440x1800 (4:5), 60 fps
  <out>-screen.mp4   the bare screen recording, same cut, 60 fps
  <out>-sheet.png    a contact sheet (2 frames a second) to check the motion

--duration  total length in seconds (default 12). A build that runs longer
            than this keeps its natural length plus a one-second hold.
--start/--end  override the detected cut (seconds into the take).
"""
import argparse, json, os, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, '..', 'assets')
LEAD = 0.45      # empty page shown before the first cursor arrives
HOLD = 1.0       # finished screen held after the last thing moves


def run(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, **kw)
    if r.returncode != 0:
        sys.exit(f"{cmd[0]} failed:\n{r.stderr.decode(errors='replace')[-2000:]}")
    return r


def probe(path):
    out = run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries',
               'stream=width,height:format=duration', '-of', 'json', path]).stdout
    j = json.loads(out)
    s = j['streams'][0]
    return s['width'], s['height'], float(j['format']['duration'])


def activity(path, w, h):
    """Times (s) of the first and last frame that differs from the one before it."""
    fps, sw = 30, 144
    sh = int(round(sw * h / w / 2)) * 2
    raw = run(['ffmpeg', '-v', 'error', '-i', path, '-vf', f'fps={fps},scale={sw}:{sh}:flags=area,format=gray',
               '-f', 'rawvideo', '-']).stdout
    n = len(raw) // (sw * sh)
    size = sw * sh
    changed = []
    try:
        import numpy as np
        frames = np.frombuffer(raw[:n * size], dtype=np.uint8).reshape(n, size).astype(np.int16)
        d = np.abs(np.diff(frames, axis=0)) > 22
        changed = [i + 1 for i, c in enumerate(d.sum(axis=1)) if c >= 3]
    except ImportError:
        prev = raw[0:size]
        for i in range(1, n):
            cur = raw[i * size:(i + 1) * size]
            if cur != prev:
                c = 0
                for a, b in zip(prev, cur):
                    if a - b > 22 or b - a > 22:
                        c += 1
                        if c >= 3:
                            break
                if c >= 3:
                    changed.append(i)
            prev = cur
    # ignore anything in the first quarter second (the recorder settling)
    changed = [i for i in changed if i / fps > 0.25]
    if not changed:
        return None, None
    return changed[0] / fps, changed[-1] / fps


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('take')
    ap.add_argument('--out', required=True)
    ap.add_argument('--duration', type=float, default=12)
    ap.add_argument('--start', type=float)
    ap.add_argument('--end', type=float)
    o = ap.parse_args()
    if not shutil.which('ffmpeg'):
        sys.exit('ffmpeg is not installed (brew install ffmpeg).')

    take = os.path.abspath(o.take)
    out = os.path.abspath(os.path.expanduser(o.out))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    w, h, length = probe(take)

    first, last = activity(take, w, h)
    if first is None and o.start is None:
        sys.exit('Nothing moves in this take. The build never started: check that the screen has '
                 '.swarmStage(build), that the app opens on it with -swarm, and that -swarm-cue works.')
    start = o.start if o.start is not None else max(0.0, first - LEAD)
    end = o.end if o.end is not None else last + HOLD
    natural = end - start
    dur = max(natural, o.duration) if o.end is None else natural
    pad = max(0.0, start + dur - length) + 0.1
    moves = f'{first:.2f}–{last:.2f} s' if first is not None else 'not detected'
    print(f'build moves {moves}; cut {start:.2f} s for {dur:.2f} s'
          + (f' (longer than {o.duration:g} s)' if natural > o.duration else ''), file=sys.stderr)

    g = json.load(open(os.path.join(ASSETS, 'geom.json')))
    color = ['-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709']
    enc = ['-c:v', 'libx264', '-preset', 'medium', '-crf', '16', '-r', '60', '-pix_fmt', 'yuv420p', *color,
           '-movflags', '+faststart', '-an']
    clip = f'setpts=PTS-STARTPTS,fps=60,tpad=stop_mode=clone:stop_duration={pad:.2f}'

    # the phone mockup
    still = ['-loop', '1', '-framerate', '60', '-t', f'{dur + 0.5:.2f}']
    run(['ffmpeg', '-v', 'error', '-y', '-ss', f'{start:.3f}', '-i', take,
         *still, '-i', os.path.join(ASSETS, 'screen_mask.png'),
         *still, '-i', os.path.join(ASSETS, 'base.png'),
         *still, '-i', os.path.join(ASSETS, 'screen_over.png'),
         '-filter_complex',
         f"[0:v]{clip},scale={g['sw']}:{g['sh']}:flags=lanczos,format=rgba[v];"
         f"[1:v]format=gray[m];[v][m]alphamerge[vm];"
         f"[vm][3:v]overlay=0:0:format=rgb:shortest=1[vs];"
         f"[2:v][vs]overlay={g['sx']}:{g['sy']}:format=rgb:shortest=1,"
         f"scale=out_color_matrix=bt709:out_range=tv,format=yuv420p[out]",
         '-map', '[out]', '-t', f'{dur:.3f}', *enc, out + '.mp4'])

    # the bare screen
    run(['ffmpeg', '-v', 'error', '-y', '-ss', f'{start:.3f}', '-i', take,
         '-vf', f'{clip},scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p',
         '-t', f'{dur:.3f}', *enc, out + '-screen.mp4'])

    # a contact sheet to look at
    cols = 8
    rows = max(1, int((dur * 2 + cols - 1) // cols))
    run(['ffmpeg', '-v', 'error', '-y', '-i', out + '.mp4', '-vf',
         f'fps=2,scale=240:-1,tile={cols}x{rows}:padding=4:color=gray', '-frames:v', '1', out + '-sheet.png'])

    for f in (out + '.mp4', out + '-screen.mp4', out + '-sheet.png'):
        print(f)


if __name__ == '__main__':
    main()
