import os
import re
from collections import defaultdict

def normalize_line(line):
    # Remove comments and whitespace
    line = re.sub(r'#.*', '', line)
    return ''.join(line.split())

def scan_for_duplicates(directory, window_size=5):
    # Map from hash to list of (filepath, start_line)
    seen_blocks = defaultdict(list)
    
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.gd'):
                filepath = os.path.join(root, file)
                with open(filepath, 'r', encoding='utf-8') as f:
                    lines = f.readlines()
                
                # Create normalized lines with original line numbers
                norm_lines = []
                for i, line in enumerate(lines):
                    nl = normalize_line(line)
                    if nl:  # Skip empty lines
                        norm_lines.append((i + 1, nl, line.strip()))
                
                if len(norm_lines) < window_size:
                    continue
                    
                # Sliding window
                for i in range(len(norm_lines) - window_size + 1):
                    window = norm_lines[i:i+window_size]
                    block_text = "".join([l[1] for l in window])
                    if len(block_text) > 30: # Ignore very small generic blocks
                        seen_blocks[block_text].append({
                            'file': filepath,
                            'start': window[0][0],
                            'end': window[-1][0],
                            'sample': "\\n".join([l[2] for l in window])
                        })

    # Filter to only duplicates across different files or same file but different lines
    duplicates = []
    for block_hash, occurrences in seen_blocks.items():
        if len(occurrences) > 1:
            # Check if they are actually distinct occurrences (not just overlapping windows of identical code like array declarations)
            distinct = []
            for occ in occurrences:
                # Simple check to avoid overlapping windows
                if not distinct or occ['file'] != distinct[-1]['file'] or occ['start'] > distinct[-1]['end'] + 2:
                    distinct.append(occ)
            
            if len(distinct) > 1:
                # Group by file path to easily see cross-file vs intra-file
                files = set(o['file'] for o in distinct)
                if len(files) > 1: # Prioritize cross-file duplicates
                    duplicates.append((block_hash, distinct))

    # Sort by number of occurrences, then by size
    duplicates.sort(key=lambda x: (len(x[1]), len(x[0])), reverse=True)
    
    for i, (block_hash, occs) in enumerate(duplicates[:20]):
        print(f"\\n--- Duplicate Pattern {i+1} (Found {len(occs)} times) ---")
        print("Sample Code:")
        print(occs[0]['sample'])
        print("Locations:")
        for o in occs:
            file_short = os.path.relpath(o['file'], directory)
            print(f"  - {file_short}:{o['start']}-{o['end']}")

if __name__ == "__main__":
    scan_for_duplicates(".", window_size=6)
