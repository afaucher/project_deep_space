import wave
import math
import random
import struct
import os

SAMPLE_RATE = 44100

def write_wav(filename, samples):
    with wave.open(filename, 'w') as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(SAMPLE_RATE)
        for s in samples:
            # Clamp and convert to 16-bit PCM
            s = max(-1.0, min(1.0, s))
            wav_file.writeframesraw(struct.pack('<h', int(s * 32767.0)))

def generate_engine():
    duration = 1.0 # Will be looped
    samples = []
    # Mix of low sine (60Hz), slightly higher sine (80Hz), and a bit of noise
    for i in range(int(SAMPLE_RATE * duration)):
        t = i / SAMPLE_RATE
        s1 = math.sin(2 * math.pi * 60 * t) * 0.5
        s2 = math.sin(2 * math.pi * 82 * t) * 0.3
        noise = random.uniform(-0.1, 0.1)
        samples.append(s1 + s2 + noise)
    return samples

def generate_rcs():
    duration = 0.5 # Will be looped or played quickly
    samples = []
    for i in range(int(SAMPLE_RATE * duration)):
        # High pass white noise (simplified by just using fast varying random)
        noise = random.uniform(-0.5, 0.5)
        samples.append(noise)
    return samples

def generate_laser():
    # High-voltage gap discharge: a low "thump" (capacitor dump) overlapped with a
    # harsh electrical "bzzt" (the arc), plus a snap transient at contact. Replaces
    # the old descending-sine "pew" -- reads as a spark gap closing, not a toy blaster.
    duration = 0.22
    n = int(SAMPLE_RATE * duration)
    samples = []
    prev = 0.0
    for i in range(n):
        t = i / SAMPLE_RATE

        # Thump: capacitor dump. Punchy low sine with a tiny downward chirp, fast decay.
        thump_freq = 70 + 40 * math.exp(-t * 60)
        thump = math.sin(2 * math.pi * thump_freq * t) * math.exp(-t * 38) * 0.9

        # Arc buzz: broadband crackle gated by a harsh square-ish buzz oscillator whose
        # pitch sags as the gap closes. Quick decay so it's a "bzzt", not a sustained hum.
        buzz_freq = 115 - 25 * t / duration
        buzz = 1.0 if math.sin(2 * math.pi * buzz_freq * t) > -0.3 else 0.2
        arc = random.uniform(-1, 1) * buzz * math.exp(-t * 14) * 0.7

        # Snap: the tick of contact in the first ~3ms.
        snap = random.uniform(-1, 1) * math.exp(-t * 900) * 0.6

        # One-pole low-pass to shave the harshest fizz off the top.
        s = thump + arc + snap
        s = prev * 0.25 + s * 0.75
        prev = s
        samples.append(s)
    return samples

def generate_missile():
    duration = 0.6
    samples = []
    for i in range(int(SAMPLE_RATE * duration)):
        t = i / SAMPLE_RATE
        # Initial thump
        thump_freq = max(20, 150 - (t * 1000))
        thump = math.sin(2 * math.pi * thump_freq * t) * math.exp(-t * 20)
        
        # Followed by noisy woosh
        woosh_amp = math.sin(t * math.pi / duration) * 0.4
        woosh = random.uniform(-1, 1) * woosh_amp
        
        samples.append(thump + woosh)
    return samples

def generate_fan():
    # Looping coolant "wind": heavily filtered noise that whooshes rather than hisses,
    # ramped (volume + pitch, in-engine) as heat climbs. Two cascaded one-pole low-passes
    # kill the high-frequency fizz that read as static; slow overlapping swells make it
    # breathe like moving air; a faint low body keeps it from sounding thin. 2.0s loop so
    # the swell doesn't obviously repeat.
    duration = 2.0
    n = int(SAMPLE_RATE * duration)
    samples = []
    lp1 = 0.0
    lp2 = 0.0
    for i in range(n):
        t = i / SAMPLE_RATE
        lp1 = lp1 * 0.93 + random.uniform(-1, 1) * 0.07   # cascaded low-pass -> airy rush
        lp2 = lp2 * 0.93 + lp1 * 0.07
        swell = 0.7 + 0.3 * math.sin(2 * math.pi * 0.5 * t) * math.sin(2 * math.pi * 0.17 * t + 1.0)
        body = math.sin(2 * math.pi * 90 * t) * 0.05       # faint low body, loops over 2.0s
        samples.append(lp2 * 22.0 * swell + body)
    return samples

def generate_alarm():
    # Looping overheat klaxon: a harsh pulsing square tone. 660 Hz over 0.6s = 396
    # whole cycles, so it loops seamlessly. On ~0.25s, off the rest -> "beep ... beep".
    duration = 0.6
    n = int(SAMPLE_RATE * duration)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        gate = 1.0 if t < 0.25 else 0.0
        tone = 1.0 if math.sin(2 * math.pi * 660 * t) > 0 else -1.0   # square klaxon
        samples.append(tone * gate * 0.5)
    return samples

def generate_impact():
    # One-shot hull impact: a low body thud + a brief metallic ring + an initial
    # crunch. Played (and haptically punched) whenever the player ship takes damage.
    duration = 0.3
    n = int(SAMPLE_RATE * duration)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        body = math.sin(2 * math.pi * (90 + 30 * math.exp(-t * 40)) * t) * math.exp(-t * 12) * 0.9
        ring = (math.sin(2 * math.pi * 430 * t) * 0.4 + math.sin(2 * math.pi * 970 * t) * 0.25) * math.exp(-t * 9)
        crunch = random.uniform(-1, 1) * math.exp(-t * 50) * 0.7
        samples.append(body + ring + crunch)
    return samples

if __name__ == "__main__":
    os.makedirs("assets/audio", exist_ok=True)
    write_wav("assets/audio/engine.wav", generate_engine())
    write_wav("assets/audio/rcs.wav", generate_rcs())
    write_wav("assets/audio/laser.wav", generate_laser())
    write_wav("assets/audio/missile_launch.wav", generate_missile())
    write_wav("assets/audio/fan.wav", generate_fan())
    write_wav("assets/audio/alarm.wav", generate_alarm())
    write_wav("assets/audio/impact.wav", generate_impact())
    print("Audio files generated in assets/audio/")
