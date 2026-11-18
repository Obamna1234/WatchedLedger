#!/usr/bin/env python3
"""Writes an original, royalty-free backing track for the demo video.

Usage: make_music.py <out.wav> [seconds]

Everything is synthesised here (no samples), so the track can be used
anywhere. Upbeat chill-pop: 112 BPM, Am-F-C-G, with a soft kick, claps,
hats, bass, a plucked arpeggio, a warm pad and a bell melody after the
intro. Needs numpy.
"""
import sys
import wave

import numpy as np

SR = 44100
BPM = 112
BEAT = 60 / BPM
BAR = 4 * BEAT
rng = np.random.default_rng(7)


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def env(n, attack, release):
    """Linear attack, exponential release, n samples long."""
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-t / release)


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):  # one-pole; fine for a 40 s track
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def add(buf, at, sig):
    i = int(at * SR)
    if i >= len(buf):
        return
    sig = sig[: len(buf) - i]
    buf[i:i + len(sig)] += sig


def kick():
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    f = 45 + 85 * np.exp(-t * 28)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t * 7.5) * 0.6


def clap():
    n = int(0.25 * SR)
    noise = rng.standard_normal(n)
    noise = noise - lowpass(noise, 900)  # thin out the lows
    e = np.zeros(n)
    for k, d in enumerate((0.0, 0.011, 0.022)):  # three quick hits
        s = int(d * SR)
        e[s:] += np.exp(-np.arange(n - s) / SR * (60 if k < 2 else 18))
    return noise * e * 0.16


def hat(open_=False):
    n = int((0.18 if open_ else 0.05) * SR)
    noise = rng.standard_normal(n)
    noise = np.diff(noise, prepend=0)  # crude high-pass
    return noise * env(n, 0.001, 0.05 if open_ else 0.012) * 0.05


def saw(freq, n, harmonics=12):
    t = np.arange(n) / SR
    return sum(np.sin(2 * np.pi * freq * k * t) / k for k in range(1, harmonics))


def bass(note, dur):
    n = int(dur * SR)
    tone = saw(hz(note), n, 8) * 0.5 + np.sin(2 * np.pi * hz(note) * np.arange(n) / SR)
    return lowpass(tone * env(n, 0.005, dur * 0.9), 420) * 0.24


def pluck(note, dur=0.5):
    """Karplus-Strong string."""
    n = int(dur * SR)
    period = int(SR / hz(note))
    buf = rng.uniform(-1, 1, period)
    out = np.empty(n)
    for i in range(n):
        out[i] = buf[i % period]
        buf[i % period] = 0.5 * (buf[i % period] + buf[(i + 1) % period]) * 0.996
    return out * 0.26


def pad(notes, dur):
    n = int(dur * SR)
    tone = np.zeros(n)
    for m in notes:
        for detune in (-0.12, 0.0, 0.12):
            tone += saw(hz(m + detune), n, 6)
    tone = lowpass(tone, 1100)
    t = np.arange(n) / SR
    shape = np.clip(t / 0.6, 0, 1) * np.clip((dur - t) / 0.4, 0, 1)
    return tone * shape * 0.04


def bell(note, dur=0.9):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = hz(note)
    tone = (np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * f * 2.0 * t)
            + 0.12 * np.sin(2 * np.pi * f * 3.01 * t) * np.exp(-t * 6))
    return tone * env(n, 0.004, 0.35) * 0.2


def reverb(x, wet=0.25):
    out = x.copy()
    for d, g in ((0.0297, 0.62), (0.0371, 0.6), (0.0411, 0.58), (0.0437, 0.56)):
        k = int(d * SR)
        y = x.copy()
        for i in range(k, len(y), k):  # block-wise feedback comb
            y[i:i + k] += g * y[i - k:i][: len(y[i:i + k])]
        out += wet * 0.25 * y
    return out


def main():
    path = sys.argv[1]
    seconds = float(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2][0].isdigit() else 40.0
    bars = int(np.ceil(seconds / BAR)) + 1
    total = int((bars * BAR + 2) * SR)
    drums, low, mid, hi = (np.zeros(total) for _ in range(4))

    # Am  F  C  G  (roots for bass, triads for pad and pluck)
    chords = [(57, (69, 72, 76)), (53, (65, 69, 72)),
              (48, (64, 67, 72)), (55, (67, 71, 74))]
    melody = [  # (beat in 4-bar phrase, midi note, length in beats)
        (0, 76, 1), (1, 79, 0.5), (1.5, 81, 1.5), (4, 77, 1), (5, 76, 0.5),
        (5.5, 72, 1.5), (8, 72, 1), (9, 74, 0.5), (9.5, 76, 1.5),
        (12, 74, 1), (13, 71, 1), (14, 79, 2),
    ]
    k, c = kick(), clap()
    for b in range(bars):
        t0 = b * BAR
        root, triad = chords[b % 4]
        intro = b < 2
        outro = b >= bars - 2
        add(mid, t0, pad(triad, BAR + 0.3))
        for s in range(16):  # 16th-note arpeggio
            if intro and s % 2:
                continue
            note = (triad + tuple(x + 12 for x in triad))[(s * 2 + s // 4) % 6]
            add(hi, t0 + s * BEAT / 4, pluck(note, 0.45))
        if intro:
            continue
        for beat in range(4):
            add(drums, t0 + beat * BEAT, k)
            if beat in (1, 3):
                add(drums, t0 + beat * BEAT, c)
            add(drums, t0 + beat * BEAT + BEAT / 2, hat(open_=beat == 3))
            add(drums, t0 + beat * BEAT, hat())
        if not outro:
            add(drums, t0 + 3.75 * BEAT, k * 0.5)  # little push into the next bar
        for e in range(8):  # eighth-note bass, octave jump on the "and" of 4
            note = root - 12 + (12 if e == 7 else 0)
            add(low, t0 + e * BEAT / 2, bass(note, BEAT / 2 * 0.95))
        if b >= 4 and not outro:
            phrase_beat = (b % 4) * 4
            for at, note, length in melody:
                if phrase_beat <= at < phrase_beat + 4:
                    add(hi, t0 + (at - phrase_beat) * BEAT, bell(note, length * BEAT + 0.4))

    # Sidechain: duck pad and bass under each kick for the pumping feel.
    duck = np.ones(total)
    beat_n = int(BEAT * SR)
    shape = 1 - 0.55 * np.exp(-np.arange(beat_n) / SR * 9)
    for b in range(2, bars):
        for beat in range(4):
            i = int((b * BAR + beat * BEAT) * SR)
            duck[i:i + beat_n] = np.minimum(duck[i:i + beat_n], shape[: len(duck[i:i + beat_n])])
    mix = drums + (low + mid) * duck + reverb(hi, 0.35)
    if '--stems' in sys.argv:
        for name, x in (('drums', drums), ('bass', low), ('pad', mid), ('pluck+bell', hi)):
            print(f'{name:11s} rms {20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-9):6.1f} dB'
                  f'  peak {20 * np.log10(np.max(np.abs(x)) + 1e-9):6.1f} dB')

    # Stereo: hats and pluck slightly wide, low end centred.
    left = mix + 0.15 * np.roll(hi, int(0.011 * SR))
    right = mix + 0.15 * np.roll(hi, int(0.017 * SR))
    st = np.stack([left, right], axis=1)[: int(seconds * SR)]
    n_fade = int(0.04 * SR)
    st[:n_fade] *= np.linspace(0, 1, n_fade)[:, None]
    st /= np.max(np.abs(st))
    st = np.tanh(st * 1.2) / np.tanh(1.2)  # gentle glue
    st *= 0.89 / np.max(np.abs(st))  # about -1 dBFS
    data = (st * 32767).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print('wrote', path, f'{seconds:.1f}s')


if __name__ == '__main__':
    main()
