import os

for f in ['scripts/helm_panel.gd', 'scripts/sensor_panel.gd', 'scripts/terminal_display.gd']:
    with open(f, 'r') as fp:
        lines = fp.readlines()
        for i, line in enumerate(lines):
            if 'update' in line.lower():
                print(f"{f}:{i+1}: {line.strip()}")
