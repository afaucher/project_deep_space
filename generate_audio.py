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
    duration = 0.3
    samples = []
    for i in range(int(SAMPLE_RATE * duration)):
        t = i / SAMPLE_RATE
        # Frequency descends exponentially from 1200 to 200
        freq = 200 + 1000 * math.exp(-t * 15)
        # Add slight tremolo
        amp = math.exp(-t * 5) * (0.8 + 0.2 * math.sin(2 * math.pi * 30 * t))
        s = math.sin(2 * math.pi * freq * t) * amp
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

if __name__ == "__main__":
    os.makedirs("assets/audio", exist_ok=True)
    write_wav("assets/audio/engine.wav", generate_engine())
    write_wav("assets/audio/rcs.wav", generate_rcs())
    write_wav("assets/audio/laser.wav", generate_laser())
    write_wav("assets/audio/missile_launch.wav", generate_missile())
    print("Audio files generated in assets/audio/")
