#!/bin/bash
# Regenerates games.json from .js files in this directory.
# Preserves existing entries (so manual edits like playerCount aren't lost).
# Only adds new entries for .js files not already in games.json.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="$SCRIPT_DIR/games.json"
python3 -c "
import json, os, sys, re

games_dir = sys.argv[1]
output_path = sys.argv[2]

# Load existing entries
existing = []
if os.path.isfile(output_path):
    try:
        with open(output_path) as f:
            existing = json.load(f)
    except (json.JSONDecodeError, IOError):
        existing = []

# Index existing by filename (skip empty-file entries)
existing_by_file = {e['file']: e for e in existing if e.get('file')}

# Scan for .js files
js_files = sorted(f for f in os.listdir(games_dir)
                  if f.endswith('.js') and os.path.isfile(os.path.join(games_dir, f))
                  and not f.startswith('logo'))

result = []
for fname in js_files:
    if fname in existing_by_file:
        # Preserve the existing entry as-is
        result.append(existing_by_file[fname])
    else:
        # Generate new entry
        stem = fname[:-3]  # strip .js
        # Split camelCase into words
        words = re.sub(r'([a-z])([A-Z])', r'\1 \2', stem)
        words = re.sub(r'([A-Z])([A-Z][a-z])', r'\1 \2', words).split()
        author = words[0] if words else ''
        name = ' '.join(words[1:]) if len(words) > 1 else stem
        result.append({
            'name': name,
            'author': author,
            'playerCount': 1,
            'file': fname
        })

# Always append the sales pitch tile at the end
result.append({
    'name': 'Your Game Here!',
    'author': '',
    'playerCount': 1,
    'file': '',
    'image': 'ChrisYourGame.png'
})

new_count = len(result) - len(existing_by_file) - 1

with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)
    f.write('\n')

print(f'Updated {output_path} with {len(result)} game(s). ({new_count} new)')
" "$SCRIPT_DIR" "$OUTPUT"
