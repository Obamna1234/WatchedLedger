#!/usr/bin/env python3
"""Turns the raw emulator recording into a captioned 40-second demo video.

Usage: make_video.py <demo-out dir> <output.mp4> [music.wav]

The demo-out folder (artifact of the "Demo video" workflow) holds raw.mp4,
rec_t0.txt (device clock when recording started) and marks.log (logcat lines
"MARK|<caption>" written by integration_test/demo_test.dart).
"""
import math
import os
import re
import subprocess
import sys
import tempfile
import textwrap

W, H, FPS = 720, 1600, 30
TOTAL = 40.0
TITLE = 2.2
END_MIN = 2.3
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
FONT_REG = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
ENC = ['-c:v', 'libx264', '-crf', '20', '-preset', 'veryfast',
       '-pix_fmt', 'yuv420p', '-r', str(FPS), '-an']
BG = '0x0E1F1B'  # deep ledger green
MARK_LAG = 0.5  # seconds between an action and its log line reaching logcat


def run(args):
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', *args],
                   check=True)


def encode(args, out):
    tmp = out[:-4] + '.part.mp4'
    run([*args, *ENC, tmp])
    os.replace(tmp, out)


def text_file(folder, name, text):
    path = os.path.join(folder, name)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)
    return path


def read_marks(folder):
    t0 = float(open(os.path.join(folder, 'rec_t0.txt')).read().strip())
    marks = []
    for line in open(os.path.join(folder, 'marks.log'), encoding='utf-8',
                     errors='replace'):
        m = re.match(r'\s*(\d+\.\d+).*?MARK\|(.*)$', line)
        if m:
            marks.append((float(m.group(1)) - t0 - MARK_LAG, m.group(2).strip()))
    return marks


def draw_lines(folder, prefix, lines, font, size, color, gap, top, box=''):
    """One drawtext per line, centred. Newer ffmpeg builds draw a box glyph
    for line breaks inside a single drawtext, so lines are never joined."""
    step = size + gap
    out = []
    for k, line in enumerate(lines):
        tf = text_file(folder, f'{prefix}.{k}.txt', line)
        out.append(f"drawtext=fontfile={font}:textfile={tf}:fontcolor={color}:"
                   f"fontsize={size}:x=(w-text_w)/2:y={top}+{k * step}{box}")
    return ','.join(out)


def card(folder, out, duration, title, subtitle, title_size=64):
    name = os.path.basename(out)
    t_lines = title.split('\n')
    t_top = f"h/2-60-{len(t_lines) * (title_size + 12)}"
    vf = (draw_lines(folder, name + '.t', t_lines, FONT, title_size, 'white', 12,
                     t_top) + ',' +
          draw_lines(folder, name + '.s', subtitle.split('\n'), FONT_REG, 34,
                     '0xBFE3D8', 14, 'h/2+20') + ',' +
          f"fade=t=in:st=0:d=0.35,fade=t=out:st={duration - 0.35:.2f}:d=0.35")
    encode(['-f', 'lavfi', '-i', f'color=c={BG}:s={W}x{H}:r={FPS}:d={duration:.3f}',
            '-vf', vf], out)


WAIT_SHOW = 0.45  # seconds each network wait is squeezed into


def plan_scenes(marks):
    """Groups marks into captioned scenes, each split into normal pieces and
    network-wait pieces ("~wait" ... "~go")."""
    start = next(t for t, c in marks if c == 'start')
    end = next(t for t, c in marks if c == 'end') + 1.0
    events = [(t, c) for t, c in marks if start < t <= end and c != 'end']
    scenes = []
    for t, c in events:
        if c == '~wait' and scenes:
            scenes[-1]['waits'].append([t, None])
        elif c == '~go' and scenes and scenes[-1]['waits']:
            scenes[-1]['waits'][-1][1] = t
        elif not c.startswith('~'):
            scenes.append({'caption': c, 'a': max(t, start + 0.3), 'waits': []})
    for i, sc in enumerate(scenes):
        sc['b'] = scenes[i + 1]['a'] if i + 1 < len(scenes) else end
        pieces, pos = [], sc['a']
        for wa, wb in sc['waits']:
            wb = wb if wb is not None else sc['b']
            if wa > pos:
                pieces.append((pos, wa, False))
            pieces.append((wa, wb, True))
            pos = wb
        if sc['b'] > pos:
            pieces.append((pos, sc['b'], False))
        sc['pieces'] = [p for p in pieces if p[1] - p[0] > 0.05]
        sc['active'] = sum(p[1] - p[0] for p in sc['pieces'] if not p[2])
        sc['wait_show'] = sum(min(WAIT_SHOW, p[1] - p[0])
                              for p in sc['pieces'] if p[2])
    return scenes


def main():
    folder, output = sys.argv[1], sys.argv[2]
    raw = os.path.join(folder, 'raw.mp4')
    scenes = plan_scenes(read_marks(folder))

    budget = TOTAL - TITLE - END_MIN - sum(sc['wait_show'] for sc in scenes)
    weights = [math.sqrt(max(sc['active'], 0.5)) for sc in scenes]
    for sc, w in zip(scenes, weights):
        target = budget * w / sum(weights)
        sc['speed'] = max(1.0, sc['active'] / target)

    work = tempfile.mkdtemp(prefix='demo-')
    parts = [os.path.join(work, '000_title.mp4')]
    card(work, parts[0], TITLE, 'WatchedLedger',
         'Movies, series, books,\naudiobooks, podcasts,\ngames and videos.\n\nNew in 1.1')

    used = TITLE
    for i, sc in enumerate(scenes, 1):
        cap_lines = textwrap.wrap(sc['caption'], 26)
        caption = draw_lines(
            work, f'cap{i}', cap_lines, FONT, 38, 'white', 14,
            f"h-110-{len(cap_lines) * 52}",
            box=':box=1:boxcolor=black@0.72:boxborderw=14')
        scene_len = 0.0
        for j, (a, b, waiting) in enumerate(sc['pieces']):
            length = b - a
            speed = max(1.0, length / WAIT_SHOW) if waiting else sc['speed']
            dur = length / speed
            vf = (f"setpts=(PTS-STARTPTS)/{speed:.4f},fps={FPS},"
                  f"scale={W}:{H}:force_original_aspect_ratio=decrease,"
                  f"pad={W}:{H}:(ow-iw)/2:(oh-ih)/2,{caption}")
            out = os.path.join(work, f'{i:02d}{j:01d}_scene.mp4')
            encode(['-ss', f'{a:.3f}', '-to', f'{b:.3f}', '-i', raw,
                    '-vf', vf, '-t', f'{dur:.3f}'], out)
            parts.append(out)
            scene_len += dur
        used += scene_len
        print(f"scene {i}: {sc['b'] - sc['a']:5.1f}s raw -> {scene_len:4.1f}s "
              f"(x{sc['speed']:.1f}, {len(sc['waits'])} waits)  {sc['caption']}")

    parts.append(os.path.join(work, '999_end.mp4'))
    card(work, parts[-1], max(END_MIN, TOTAL - used), 'No account.\nNo tracking.',
         'Your lists stay on your phone.\n\nFree on GitHub:\nObamna1234/WatchedLedger',
         title_size=58)

    listing = text_file(work, 'list.txt', ''.join(f"file '{p}'\n" for p in parts))
    tmp = output[:-4] + '.part.mp4'
    run(['-f', 'concat', '-safe', '0', '-i', listing, '-c', 'copy',
         '-movflags', '+faststart', tmp])
    os.replace(tmp, output)
    if len(sys.argv) > 3:  # add the backing track, faded out at the end
        tmp = output[:-4] + '.part.mp4'
        run(['-i', output, '-i', sys.argv[3], '-map', '0:v', '-map', '1:a',
             '-c:v', 'copy', '-af', f'afade=t=out:st={TOTAL - 2.5}:d=2.5',
             '-c:a', 'aac', '-b:a', '192k', '-shortest',
             '-movflags', '+faststart', tmp])
        os.replace(tmp, output)
    print('wrote', output)


if __name__ == '__main__':
    main()
