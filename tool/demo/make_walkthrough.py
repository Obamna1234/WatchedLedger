#!/usr/bin/env python3
"""Turns the raw demo recording into a slow, step-by-step how-to video.

Usage: make_walkthrough.py <demo-out dir> <output.mp4> [music.wav]

Unlike make_video.py (a fast 40-second ad), this plays every step at real
speed, pauses before and after each one, and shows the phone a little
smaller with an explanation panel underneath, so nothing is covered.
Network waits (lookups) are shortened to about a second.
"""
import os
import re
import subprocess
import sys
import tempfile
import textwrap

import make_video as mv

W, H, FPS = mv.W, mv.H, mv.FPS
PHONE_W, PHONE_H = 520, 1156  # 720x1600 scaled to ~72%
PHONE_Y = 36
PANEL_Y = PHONE_Y + PHONE_H + 28
HOLD_IN = 2.0   # still frame at the start of a step, to read the text
HOLD_OUT = 1.6  # still frame at the end, to see the result
WAIT_SHOW = 1.0
BG = mv.BG

# One entry per caption in integration_test/demo_test.dart, in order.
STEPS = [
    ('Add something',
     'Tap the green Add button. Pick the type (Movies, Series...), choose To '
     'Watch or Watched, type the title and tap +. The year, genre and cover '
     'are found for you.'),
    ('Typos are fine',
     'Spelled it wrong? A "Did you mean...?" list pops up. Tap the right one.'),
    ('Switch lists',
     'Tap the name at the top (Movies ▾) to switch to Series, Books, '
     'Games and more. It shows how much is in each.'),
    ('Save videos from links',
     'Paste a YouTube, TikTok, Instagram or Facebook link instead of a title. '
     'The name and picture fill in by themselves.'),
    ('Track a series',
     'Tap a show, then "Seasons & episodes". Tick a whole season in one go, '
     'or single episodes. Tap Save when done.'),
    ('Tick it off',
     'Swipe right on a title (or tap its box) to move it to Watched. Mistake? '
     'Tap Undo at the bottom.'),
    ('Add your own details',
     'Tap any title to rate it, add a note, and pick where you watched it. '
     'Tap Save.'),
    ('Folders',
     'Tap Folders at the bottom, then New folder. Name it, tick what goes in, '
     'tap Done. Share sends a simple message with the links.'),
    ("Can't decide?",
     'Tap Pick at the bottom, then "Pick for me". It chooses something from '
     'your To Watch lists.'),
    ('Everything else',
     'Import a list, back up, reminders and themes (light, dark, black) are '
     'all under More.'),
]


def panel(work, name, step_no, title, body):
    """drawtext filters for the explanation panel."""
    head = mv.draw_lines(work, name + '.h', [f'Step {step_no} of {len(STEPS)}'],
                         mv.FONT_REG, 28, '0x9FD6C6', 0, PANEL_Y)
    ttl = mv.draw_lines(work, name + '.t', [title], mv.FONT, 44, 'white', 0,
                        PANEL_Y + 44)
    body_lines = textwrap.wrap(body, 36)
    txt = mv.draw_lines(work, name + '.b', body_lines, mv.FONT_REG, 31,
                        '0xE8F3EF', 11, PANEL_Y + 112)
    return f'{head},{ttl},{txt}'


def framed(caption_filters):
    """Phone video scaled into the frame, on the green background."""
    return (f"scale={PHONE_W}:{PHONE_H},"
            f"pad={W}:{H}:({W}-{PHONE_W})/2:{PHONE_Y}:color={BG},"
            f"{caption_filters}")


def still(raw, at, dur, vf, out):
    """A held frame of the recording, with the panel drawn on it."""
    png = out + '.png'
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
                    '-ss', f'{at:.3f}', '-i', raw, '-frames:v', '1', png],
                   check=True)
    mv.encode(['-framerate', str(FPS), '-i', png, '-vf',
               f'format=yuv420p,loop=-1:1,trim=duration={dur:.3f},'
               f'setpts=PTS-STARTPTS,{vf}'], out)


RING_R = 44  # touch ring radius in screen pixels


def make_ring(path):
    """A white ring with a dark edge, like Android's "show taps" dot."""
    from PIL import Image, ImageDraw
    size = RING_R * 2 + 8
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    box = (4, 4, size - 4, size - 4)
    d.ellipse(box, fill=(255, 255, 255, 70), outline=(20, 20, 20, 200), width=9)
    d.ellipse((8, 8, size - 8, size - 8), outline=(255, 255, 255, 235), width=5)
    img.save(path)


def touches(marks):
    """(time, x, y, kind) for every '~tap x y' / '~swipe x y' mark."""
    out = []
    for t, c in marks:
        m = re.match(r'~(tap|swipe) (\d+) (\d+)$', c)
        if m:
            out.append((t, int(m.group(2)), int(m.group(3)), m.group(1)))
    return out


def play(raw, a, b, speed, dur, vf, ring, taps, out):
    """One piece of the recording, with a ring drawn at each touch."""
    if not taps:
        mv.encode(['-ss', f'{a:.3f}', '-to', f'{b:.3f}', '-i', raw, '-vf',
                   f'setpts=(PTS-STARTPTS)/{speed:.4f},fps={FPS},{vf}',
                   '-t', f'{dur:.3f}'], out)
        return
    graph = [f'[0:v]setpts=(PTS-STARTPTS)/{speed:.4f},fps={FPS}[v0]',
             f"[1:v]split={len(taps)}" + ''.join(f'[r{k}]' for k in range(len(taps)))]
    for k, (t, x, y, kind) in enumerate(taps):
        start = max(0.0, (t - a) / speed - 0.1)
        end = start + (0.9 if kind == 'swipe' else 0.55)
        graph.append(f"[v{k}][r{k}]overlay=x={x - RING_R - 4}:y={y - RING_R - 4}:"
                     f"enable='between(t,{start:.3f},{end:.3f})'[v{k + 1}]")
    graph.append(f'[v{len(taps)}]{vf}[out]')
    mv.encode(['-ss', f'{a:.3f}', '-to', f'{b:.3f}', '-i', raw,
               '-loop', '1', '-i', ring, '-filter_complex', ';'.join(graph),
               '-map', '[out]', '-t', f'{dur:.3f}'], out)


def main():
    folder, output = sys.argv[1], sys.argv[2]
    raw = os.path.join(folder, 'raw.mp4')
    marks = mv.read_marks(folder)
    scenes = mv.plan_scenes(marks)
    all_taps = touches(marks)
    if len(scenes) != len(STEPS):
        sys.exit(f'{len(scenes)} scenes in the recording, {len(STEPS)} steps')

    work = tempfile.mkdtemp(prefix='walk-')
    ring = os.path.join(work, 'ring.png')
    make_ring(ring)
    parts = [os.path.join(work, '000_title.mp4')]
    mv.card(work, parts[0], 3.5, 'WatchedLedger',
            'How to use it\n\nVersion 1.2')
    total = 3.5
    for i, (sc, (title, body)) in enumerate(zip(scenes, STEPS), 1):
        vf = framed(panel(work, f's{i}', i, title, body))
        # Trim dead time: at most 1.2 s before the first touch and 2.5 s
        # after the last one (the "after" still covers the result).
        scene_taps = [tp[0] for tp in all_taps if sc['a'] <= tp[0] < sc['b']]
        if scene_taps:
            first, last = scene_taps[0], scene_taps[-1]
            pieces = sc['pieces']
            pa, pb, pw = pieces[0]
            if not pw and first - pa > 1.2:
                pieces[0] = (first - 1.2, pb, pw)
            pa, pb, pw = pieces[-1]
            if not pw and pa <= last and pb - last > 2.5:
                pieces[-1] = (pa, last + 2.5, pw)
            sc['b'] = pieces[-1][1]
        out = os.path.join(work, f'{i:02d}0_in.mp4')
        still(raw, sc['a'] + 0.05, HOLD_IN, vf, out)
        parts.append(out)
        total += HOLD_IN
        for j, (a, b, waiting) in enumerate(sc['pieces'], 1):
            length = b - a
            speed = max(1.0, length / WAIT_SHOW) if waiting else 1.0
            dur = length / speed
            out = os.path.join(work, f'{i:02d}{j}_play.mp4')
            taps = [] if waiting else [
                tp for tp in all_taps if a <= tp[0] < b]
            play(raw, a, b, speed, dur, vf, ring, taps, out)
            parts.append(out)
            total += dur
        out = os.path.join(work, f'{i:02d}9_out.mp4')
        still(raw, max(sc['a'], sc['b'] - 0.15), HOLD_OUT, vf, out)
        parts.append(out)
        total += HOLD_OUT
        print(f'step {i:2d}: {sc["b"] - sc["a"]:5.1f}s raw  {title}')

    parts.append(os.path.join(work, '999_end.mp4'))
    mv.card(work, parts[-1], 4.0, 'No account.\nNo tracking.',
            'Your lists stay on your phone.\n\nFree on GitHub:\n'
            'Obamna1234/WatchedLedger', title_size=58)
    total += 4.0

    listing = mv.text_file(work, 'list.txt',
                           ''.join(f"file '{p}'\n" for p in parts))
    tmp = output[:-4] + '.part.mp4'
    mv.run(['-f', 'concat', '-safe', '0', '-i', listing, '-c', 'copy',
            '-movflags', '+faststart', tmp])
    os.replace(tmp, output)
    if len(sys.argv) > 3:  # quiet backing track, faded at both ends
        tmp = output[:-4] + '.part.mp4'
        mv.run(['-i', output, '-i', sys.argv[3], '-map', '0:v', '-map', '1:a',
                '-c:v', 'copy', '-af',
                f'volume=0.45,afade=t=in:d=1.5,afade=t=out:st={total - 3:.2f}:d=3',
                '-c:a', 'aac', '-b:a', '160k', '-shortest',
                '-movflags', '+faststart', tmp])
        os.replace(tmp, output)
    print(f'wrote {output} ({total:.0f}s)')


if __name__ == '__main__':
    main()
