#!/usr/bin/env python3
"""
arcade_stats.py - Simple persistent stats tracking for arcade button presses and game plays
Uses a JSON file for easy cross-language access (Python and Node.js)
"""

import json
import os
import time
from threading import Lock

STATS_FILE = "/home/pi/arcade-stats.json"
STATS_LOCK = Lock()

# Button name mapping for display
BUTTON_NAMES = {
    'a': 'A',
    'b': 'B',
    'up': 'UP',
    'down': 'DOWN',
    'left': 'LEFT',
    'right': 'RIGHT',
}


def _load_stats():
    """Load stats from JSON file or return empty stats"""
    try:
        with open(STATS_FILE, 'r') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {
            'buttons': {},
            'games': {},
            'last_updated': None
        }


def _save_stats(stats):
    """Save stats to JSON file atomically"""
    stats['last_updated'] = time.strftime('%Y-%m-%d %H:%M:%S')
    tmp_file = STATS_FILE + '.tmp'
    with open(tmp_file, 'w') as f:
        json.dump(stats, f, indent=2)
    os.replace(tmp_file, STATS_FILE)


def increment_button(player_num, button):
    """Increment button press counter for a player"""
    key = f"P{player_num}_{BUTTON_NAMES.get(button, button.upper())}"
    with STATS_LOCK:
        stats = _load_stats()
        stats['buttons'][key] = stats['buttons'].get(key, 0) + 1
        _save_stats(stats)


def increment_game(game_name):
    """Increment game play counter"""
    with STATS_LOCK:
        stats = _load_stats()
        stats['games'][game_name] = stats['games'].get(game_name, 0) + 1
        _save_stats(stats)


def get_stats():
    """Get current stats as dict"""
    with STATS_LOCK:
        return _load_stats()


def format_stats():
    """Return human-readable stats string like the requested format"""
    stats = get_stats()
    lines = []
    
    # Button stats sorted by player
    buttons = stats.get('buttons', {})
    for player in range(1, 5):
        player_keys = [k for k in sorted(buttons.keys()) if k.startswith(f'P{player}_')]
        for key in player_keys:
            lines.append(f"{key.replace('_', ' ')}: {buttons[key]}")
    
    if lines:
        lines.append("")
    
    # Game stats with first seen dates
    lines.append("Games:")
    games = stats.get('games', {})
    first_seen = stats.get('first_seen', {})
    for game in sorted(games.keys()):
        line = f"{game}: {games[game]}"
        if game in first_seen:
            line += f" (since {first_seen[game]})"
        lines.append(line)
    
    return '\n'.join(lines)


def print_stats():
    """Print formatted stats to stdout"""
    print(format_stats())


if __name__ == '__main__':
    print_stats()
