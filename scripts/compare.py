#!/usr/bin/env python3
"""Check that a Before → After film shows the real screens.

    python3 compare.py <film-still.png> <real-screen.png> [--out diff.png]

Compare the film's first frame (still.py --at 0.3) with a screenshot of the
real old screen, and its last frame (still.py --at 99) with the real new one.
Both should be screenshots from the same simulator ("Swarm Recorder"), so the
status bar and size match.

Prints the SSIM (1.0 = identical) and a verdict, and writes a strip:
film | real | difference (changed pixels lit up in red).
"""
import argparse, os, re, subprocess, sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('film')
    ap.add_argument('real')
    ap.add_argument('--out')
    o = ap.parse_args()
    out = os.path.abspath(o.out or os.path.splitext(o.film)[0] + '-vs-real.png')

    # same size, then SSIM
    r = subprocess.run(['ffmpeg', '-v', 'info', '-i', o.film, '-i', o.real, '-lavfi',
                        '[1:v][0:v]scale2ref=flags=bicubic[b][a];[a][b]ssim', '-f', 'null', '-'],
                       capture_output=True, text=True)
    m = re.search(r'All:([0-9.]+)', r.stderr)
    if not m:
        sys.exit('Could not compare the two images:\n' + r.stderr[-1500:])
    score = float(m.group(1))

    # film | real | difference
    r = subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', o.film, '-i', o.real, '-filter_complex',
                        '[1:v][0:v]scale2ref=flags=bicubic[b][a];'
                        '[a]format=rgb24,split[a1][a2];[b]format=rgb24,split[b1][b2];'
                        '[a2][b2]blend=all_mode=difference,format=gray,'
                        "geq=lum='if(gt(lum(X,Y),12),255,0)',format=rgb24,"
                        "colorchannelmixer=rr=1:gg=0:bb=0[d];"
                        '[a1][b1][d]hstack=inputs=3,scale=960:-2',
                        '-frames:v', '1', out], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(r.stderr)

    if score >= 0.985:
        verdict = 'match'
    elif score >= 0.95:
        verdict = 'close: look at the red in the strip (often just a clock, a cursor or a keyboard)'
    else:
        verdict = 'DIFFERENT: the film does not show this screen as it really is'
    print(f'SSIM {score:.4f}  {verdict}')
    print(out)


if __name__ == '__main__':
    main()
