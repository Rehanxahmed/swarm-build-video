#!/usr/bin/env python3
"""Turn a take into the finished videos.

    python3 render.py <take.mov> --out ~/Movies/Swarm/MyApp-Home [--duration 12]
    python3 render.py <take.mov> --out ~/Movies/Swarm/MyApp-Home-decisions --mode decisions \
        --decisions decisions.json [--vertical]
    python3 render.py <flow.mov> --out ~/Movies/Swarm/MyApp-Demo --mode demo --captions flow.json

Finds where the build starts and stops on its own (the first and last frames
where anything moves). Then it cuts from just before the first cursor to a
held finished screen, and writes:

  <out>.mp4          the phone mockup on a pale plate, 1440x1800 (4:5), 60 fps
  <out>-screen.mp4   the bare screen recording, same cut, 60 fps
  <out>-sheet.png    a contact sheet (2 frames a second) to check the motion

--mode build      (default) the 12 s swarm build film
--mode decisions  a Before → After film: it holds on the old screen first
                  (--before-hold, default 1.8 s) with a "Before" label under
                  the phone, swaps to "After" once the decisions are made,
                  holds (--after-hold, default 1.6 s), then crossfades to an
                  end card (--card, default 3.2 s): the two screens side by
                  side with the decisions listed under them. Also writes
                  <out>-compare.png, that end card as a still.
--mode demo       a Demo film: a real flow of the app (record_flow.py, or any
                  screen recording), with each caption in a pill under the
                  phone while its part of the flow plays, then an end card
                  (--card, default 4 s): a frame from each caption's part
                  side by side, numbered. Also writes <out>-strip.png, that
                  end card as a still. --card 0 leaves it off.
--captions FILE   JSON with the captions, timed in seconds into the take:
                  {"captions": [{"at": 2.1, "text": "..."}], "end": 14.7,
                   "title": "What it does"}
                  record_flow.py writes it. "end" (optional) is when the flow
                  finished; the film holds the last screen after it.
--decisions FILE  JSON with the end card's text:
                  {"title": "What changed", "decisions": [{"title": "...", "why": "..."}]}
--vertical        also write <out>-9x16.mp4 (1080x1920) for stories and reels.
--duration  total length in seconds before any end card (default 12 for a
            build, natural length for decisions). A build that runs longer
            than this keeps its natural length plus a hold.
--start/--end  override the detected cut (seconds into the take).
"""
import argparse, json, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, '..', 'assets')
LEAD = 0.45      # empty page shown before the first cursor arrives
HOLD = 1.0       # finished screen held after the last thing moves
PLATE = '0xF5F5F7'   # the plate colour, for the end card


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
    activity.changes = [i / fps for i in changed]    # for picking still frames
    if not changed:
        return None, None
    return changed[0] / fps, changed[-1] / fps


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('take')
    ap.add_argument('--out', required=True)
    ap.add_argument('--mode', choices=['build', 'decisions', 'demo'], default='build')
    ap.add_argument('--duration', type=float)
    ap.add_argument('--start', type=float)
    ap.add_argument('--end', type=float)
    ap.add_argument('--before-hold', type=float)
    ap.add_argument('--after-hold', type=float)
    ap.add_argument('--card', type=float)
    ap.add_argument('--decisions')
    ap.add_argument('--captions')
    ap.add_argument('--vertical', action='store_true')
    o = ap.parse_args()
    if not shutil.which('ffmpeg'):
        sys.exit('ffmpeg is not installed (brew install ffmpeg).')
    decisions = o.mode == 'decisions'
    demo = o.mode == 'demo'
    lead = o.before_hold if o.before_hold is not None else (1.8 if decisions else 0.6 if demo else LEAD)
    hold = o.after_hold if o.after_hold is not None else (1.6 if decisions else 1.2 if demo else HOLD)
    want = o.duration if o.duration is not None else (0.0 if decisions or demo else 12.0)
    card = (o.card if o.card is not None else 3.2) if decisions else \
           (o.card if o.card is not None else 4.0) if demo else 0.0
    captions, flow_end, title = [], None, None
    if demo and o.captions:
        cj = json.load(open(os.path.expanduser(o.captions)))
        captions = sorted(cj.get('captions', []), key=lambda c: c['at'])
        flow_end, title = cj.get('end'), cj.get('title')
    if demo and not captions:
        card = 0.0   # nothing to put on an end card

    take = os.path.abspath(o.take)
    out = os.path.abspath(os.path.expanduser(o.out))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    w, h, length = probe(take)

    first, last = activity(take, w, h)
    if demo and first is None and o.start is None:
        sys.exit('Nothing moves in this take: the flow never ran. Check record_flow.py\'s xcodebuild log.')
    if first is None and o.start is None:
        sys.exit('Nothing moves in this take. The build never started: check that the screen has '
                 '.swarmStage(build), that the app opens on it with -swarm, and that -swarm-cue works.')
    start = o.start if o.start is not None else max(0.0, first - lead)
    end = o.end if o.end is not None else last + hold
    if demo and o.end is None and flow_end is not None:
        # the flow's own end (its last pause is meant to be seen), or the last
        # movement plus the hold, whichever is later
        end = max(last + hold, flow_end + 0.3)
    natural = end - start
    dur = max(natural, want) if o.end is None else natural
    pad = max(0.0, start + dur - length) + 0.1
    moves = f'{first:.2f}–{last:.2f} s' if first is not None else 'not detected'
    if decisions and first is not None and first - lead < 0:
        print(f'warning: only {first:.2f} s of the Before screen in the take; record with a longer '
              f'--settle to get the full {lead:g} s hold', file=sys.stderr)
    print(f'build moves {moves}; cut {start:.2f} s for {dur:.2f} s'
          + (f' (longer than {want:g} s)' if want and natural > want else '')
          + (f' + {card:g} s end card' if card else ''), file=sys.stderr)

    g = json.load(open(os.path.join(ASSETS, 'geom.json')))
    color = ['-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709']
    enc = ['-c:v', 'libx264', '-preset', 'medium', '-crf', '16', '-r', '60', '-pix_fmt', 'yuv420p', *color,
           '-movflags', '+faststart', '-an']
    # The simulator only writes a frame when the screen changes, so a still
    # stretch has no frames at all. Make it 60 fps first, then trim: seeking
    # into a gap would start the cut at the next change instead.
    clip = f'fps=60,trim=start={start:.3f},setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration={pad:.2f}'
    tmp = tempfile.mkdtemp(prefix='swarm-render-')
    main_mp4 = os.path.join(tmp, 'main.mp4') if decisions or (demo and card) else out + '.mp4'

    # the phone mockup (for decisions: with the Before / After label under it)
    still = ['-loop', '1', '-framerate', '60', '-t', f'{dur + 0.5:.2f}']
    labels, label_inputs = '', []
    if demo and captions:
        n = min(4, len(captions))
        layers = text_layers(tmp, g, None, {'captions': [c['text'] for c in captions],
                                            'strip': [list(b) for b in strip_boxes(g, n)[1]],
                                            **({'title': title} if title else {})})
        chain, src = [], 'ph'
        for i, c in enumerate(captions):
            label_inputs += [*still, '-i', os.path.join(tmp, f'caption-{i + 1}.png')]
            a = max(0.0, c['at'] - start)
            b = (captions[i + 1]['at'] - start - 0.15) if i + 1 < len(captions) else dur - 0.45
            if b - a < 0.6:
                b = a + 0.6
            chain.append(f"[{4 + i}:v]format=rgba,fade=t=in:st={a:.2f}:d=0.25:alpha=1,"
                         f"fade=t=out:st={max(a + 0.25, b - 0.25):.2f}:d=0.25:alpha=1[c{i}];"
                         f"[{src}][c{i}]overlay=0:0:format=rgb:shortest=1[q{i}];")
            src = f'q{i}'
        labels = ''.join(chain) + f'[{src}]'
    if decisions:
        layers = text_layers(tmp, g, o.decisions)
        before_ends = (first - start) if first is not None else min(lead, dur)
        after_from = (last - start + 0.15) if last is not None else max(0, dur - hold)
        label_inputs = [*still, '-i', layers['chip-before'], *still, '-i', layers['chip-after']]
        labels = (f"[4:v]format=rgba,fade=t=out:st={max(0, before_ends - 0.3):.2f}:d=0.3:alpha=1[cb];"
                  f"[5:v]format=rgba,fade=t=in:st={after_from:.2f}:d=0.35:alpha=1[ca];"
                  f"[ph][cb]overlay=0:0:format=rgb:shortest=1[p1];[p1][ca]overlay=0:0:format=rgb:shortest=1,")
    fit = (f"scale={g['sw']}:{g['sh']}:force_original_aspect_ratio=increase:flags=lanczos,"
           f"crop={g['sw']}:{g['sh']}" if demo else f"scale={g['sw']}:{g['sh']}:flags=lanczos")
    phone = (f"[0:v]{clip},{fit},format=rgba[v];"
             f"[1:v]format=gray[m];[v][m]alphamerge[vm];"
             f"[vm][3:v]overlay=0:0:format=rgb:shortest=1[vs];"
             f"[2:v][vs]overlay={g['sx']}:{g['sy']}:format=rgb:shortest=1")
    # labels ends ready for the next filter: "…overlay," or "[q3]"
    phone += (',format=rgba[ph];' + labels) if labels else ','
    run(['ffmpeg', '-v', 'error', '-y', '-i', take,
         *still, '-i', os.path.join(ASSETS, 'screen_mask.png'),
         *still, '-i', os.path.join(ASSETS, 'base.png'),
         *still, '-i', os.path.join(ASSETS, 'screen_over.png'),
         *label_inputs,
         '-filter_complex',
         phone + "scale=out_color_matrix=bt709:out_range=tv,format=yuv420p[out]",
         '-map', '[out]', '-t', f'{dur:.3f}', *enc, main_mp4])

    # the bare screen
    run(['ffmpeg', '-v', 'error', '-y', '-i', take,
         '-vf', f'{clip},scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p',
         '-t', f'{dur:.3f}', *enc, out + '-screen.mp4'])

    written = [out + '.mp4', out + '-screen.mp4']
    if decisions or (demo and card):
        if decisions:
            compare = out + '-compare.png'
            end_card(main_mp4, dur, layers, g, compare, tmp)
        else:
            compare = out + '-strip.png'
            n = min(4, len(captions))
            times = []
            for i in range(n):
                # two thirds of the way through the caption's part: past its
                # first tap, before the next caption's
                nxt = captions[i + 1]['at'] if i + 1 < len(captions) else start + dur
                a, b = captions[i]['at'], nxt
                t = still_near(a + 0.65 * (b - a), a + 0.3, b - 0.1, getattr(activity, 'changes', []))
                times.append(min(dur - 0.1, max(0.05, t - start)))
            strip_card(main_mp4, times, os.path.join(tmp, 'strip-text.png'), g, compare, tmp)
        # the film, crossfading into the end card
        fade = 0.6
        run(['ffmpeg', '-v', 'error', '-y', '-i', main_mp4,
             '-loop', '1', '-framerate', '60', '-t', f'{card + fade:.2f}', '-i', compare,
             '-filter_complex',
             f"[1:v]fps=60,format=yuv420p,setsar=1,settb=1/60[c];[0:v]fps=60,setsar=1,settb=1/60[f];"
             f"[f][c]xfade=transition=fade:duration={fade}:offset={dur - fade:.3f},format=yuv420p[out]",
             '-map', '[out]', *enc, out + '.mp4'])
        written.append(compare)

    if o.vertical:
        # 4:5 into 9:16, the plate smeared up and down so there's no seam
        run(['ffmpeg', '-v', 'error', '-y', '-i', out + '.mp4', '-filter_complex',
             '[0:v]scale=1080:1350:flags=lanczos,split=3[m][t][b];'
             '[t]crop=1080:2:0:0,scale=1080:285[top];[b]crop=1080:2:0:1348,scale=1080:285[bot];'
             '[top][m][bot]vstack=inputs=3,format=yuv420p', *enc, out + '-9x16.mp4'])
        written.append(out + '-9x16.mp4')

    # a contact sheet to look at
    total = dur + card
    cols = 8
    rows = max(1, int((total * 2 + cols - 1) // cols))
    run(['ffmpeg', '-v', 'error', '-y', '-i', out + '.mp4', '-vf',
         f'fps=2,scale=240:-1,tile={cols}x{rows}:padding=4:color=gray', '-frames:v', '1', out + '-sheet.png'])
    written.append(out + '-sheet.png')
    shutil.rmtree(tmp, ignore_errors=True)

    for f in written:
        print(f)


def still_near(target, lo, hi, changes, gap=0.2):
    """The moment closest to target (within lo..hi) with nothing moving for
    `gap` seconds either side, so an end-card frame isn't caught mid-animation."""
    best = None
    for k in range(0, 200):
        for t in (target + k * 0.05, target - k * 0.05):
            if lo <= t <= hi and not any(abs(c - t) < gap for c in changes):
                return t
        if target + k * 0.05 > hi and target - k * 0.05 < lo:
            break
    return target if best is None else best


def phone_boxes(g):
    """Where the end card's two phones go: the crop around one phone (with its
    shadow) and its two scaled-down places."""
    # the phone and a little of its shadow, stopping above the label under it;
    # even sizes, like the video
    crop = (g['sx'] - 50, g['sy'] - 45, (g['sw'] + 100) // 2 * 2, (g['sh'] + 88) // 2 * 2)
    k = 0.56
    pw, ph = int(crop[2] * k) // 2 * 2, int(crop[3] * k) // 2 * 2
    gap, top = 140, 200
    left = (g['W'] // 2 - gap // 2 - pw, top, pw, ph)
    right = (g['W'] // 2 + gap // 2, top, pw, ph)
    return crop, left, right


def strip_boxes(g, n):
    """A Demo end card: n phones in a row, centred on the plate with their
    captions under them. Returns the crop around one phone and the n places."""
    crop = (g['sx'] - 50, g['sy'] - 45, (g['sw'] + 100) // 2 * 2, (g['sh'] + 88) // 2 * 2)
    gap, margin, text_h, head = 56, 70, 150, 90
    k = min((g['W'] - 2 * margin - gap * (n - 1)) / n / crop[2], 0.66)
    pw, ph = int(crop[2] * k) // 2 * 2, int(crop[3] * k) // 2 * 2
    top = int((g['H'] - (head + ph + text_h)) / 2 + head)
    x0 = (g['W'] - (n * pw + (n - 1) * gap)) // 2
    return crop, [(x0 + i * (pw + gap), top, pw, ph) for i in range(n)]


def strip_card(film, times, text_png, g, out, tmp):
    """The Demo end card: a frame from each caption's part of the flow."""
    crop, boxes = strip_boxes(g, len(times))
    cx, cy, cw, ch = crop
    shots = []
    for i, t in enumerate(times):
        path = os.path.join(tmp, f'strip-{i}.png')
        run(['ffmpeg', '-v', 'error', '-y', '-ss', f'{t:.3f}', '-i', film, '-frames:v', '1',
             '-vf', f'crop={cw}:{ch}:{cx}:{cy}', path])
        shots.append(path)
    feather = 50
    soft = f"geq=lum='255*clip(min(min(X,W-1-X),min(Y,H-1-Y))/{feather},0,1)'"
    n = len(shots)
    inputs = ['-f', 'lavfi', '-i', f"color=c={PLATE}:s={g['W']}x{g['H']}"]
    for p in shots:
        inputs += ['-i', p]
    inputs += ['-i', text_png, '-f', 'lavfi', '-i', f'color=c=white:s={cw}x{ch},format=gray,{soft}']
    mask = n + 2
    graph = f"[{mask}:v]split={n}" + ''.join(f'[m{i}]' for i in range(n)) + ';' if n > 1 else f"[{mask}:v]null[m0];"
    src = '0:v'
    for i, (x, y, w, h) in enumerate(boxes):
        graph += (f"[{i + 1}:v]format=rgba[s{i}];[s{i}][m{i}]alphamerge,scale={w}:{h}:flags=lanczos[p{i}];"
                  f"[{src}][p{i}]overlay={x}:{y}[o{i}];")
        src = f'o{i}'
    graph += f"[{src}][{n + 1}:v]overlay=0:0,format=rgb24"
    run(['ffmpeg', '-v', 'error', '-y', *inputs, '-filter_complex', graph, '-frames:v', '1', out])


def text_layers(tmp, g, decisions_path, extra=None):
    """The labels and the end card's words, drawn by card.swift."""
    if not shutil.which('swift'):
        sys.exit('This film needs Swift (it comes with Xcode) to draw its labels.')
    crop, left, right = phone_boxes(g)
    spec = {'W': g['W'], 'H': g['H'], 'chipY': (g['sy'] + g['sh'] + g['H']) // 2 + 8,
            'phones': [list(left), list(right)]}
    if extra:
        spec.update(extra)
    if decisions_path:
        spec.update(json.load(open(os.path.expanduser(decisions_path))))
    path = os.path.join(tmp, 'spec.json')
    json.dump(spec, open(path, 'w'))
    run(['swift', os.path.join(HERE, 'card.swift'), path, tmp])
    return {k: os.path.join(tmp, k + '.png') for k in ('chip-before', 'chip-after', 'card-text')}


def end_card(film, dur, layers, g, out, tmp):
    """The two screens side by side: the first and last frames of the film."""
    crop, left, right = phone_boxes(g)
    cx, cy, cw, ch = crop
    shots = []
    for name, t in (('before', 0.05), ('after', dur - 0.05)):
        path = os.path.join(tmp, name + '.png')
        run(['ffmpeg', '-v', 'error', '-y', '-ss', f'{max(0, t):.3f}', '-i', film, '-frames:v', '1',
             '-vf', f'crop={cw}:{ch}:{cx}:{cy}', path])
        shots.append(path)
    feather = 50
    soft = (f"geq=lum='255*clip(min(min(X,W-1-X),min(Y,H-1-Y))/{feather},0,1)'")
    run(['ffmpeg', '-v', 'error', '-y',
         '-f', 'lavfi', '-i', f"color=c={PLATE}:s={g['W']}x{g['H']}",
         '-i', shots[0], '-i', shots[1], '-i', layers['card-text'],
         '-f', 'lavfi', '-i', f'color=c=white:s={cw}x{ch},format=gray,{soft}',
         '-filter_complex',
         f"[4:v]split[m1][m2];"
         f"[1:v]format=rgba[b0];[b0][m1]alphamerge,scale={left[2]}:{left[3]}:flags=lanczos[b];"
         f"[2:v]format=rgba[a0];[a0][m2]alphamerge,scale={right[2]}:{right[3]}:flags=lanczos[a];"
         f"[0:v][b]overlay={left[0]}:{left[1]}[p1];[p1][a]overlay={right[0]}:{right[1]}[p2];"
         f"[p2][3:v]overlay=0:0,format=rgb24",
         '-frames:v', '1', out])


if __name__ == '__main__':
    main()
