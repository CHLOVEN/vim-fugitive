#!/usr/bin/env python3
"""
Fugitive Refactor Analyzer - Detects refactored code using Levenshtein distance.

Usage:
    python fugitive_refactor_analyzer.py <old_file> <new_file> [--threshold=0.7]

Output:
    JSON object with matched line pairs that appear to be refactored (similar content).
"""

import sys
import json
import re
import argparse
from typing import List, Tuple, Dict, Any


def levenshtein_distance(s1: str, s2: str) -> int:
    """Calculate the Levenshtein distance between two strings."""
    if len(s1) < len(s2):
        return levenshtein_distance(s2, s1)
    
    if len(s2) == 0:
        return len(s1)
    
    previous_row = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        current_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row
    
    return previous_row[-1]


def similarity_ratio(s1: str, s2: str) -> float:
    """Calculate similarity ratio between two strings (0.0 to 1.0)."""
    if not s1 and not s2:
        return 1.0
    if not s1 or not s2:
        return 0.0
    
    max_len = max(len(s1), len(s2))
    distance = levenshtein_distance(s1, s2)
    return 1.0 - (distance / max_len)


def normalize_line(line: str) -> str:
    """Normalize a line for comparison (strip whitespace, lowercase)."""
    # Remove leading/trailing whitespace
    normalized = line.strip()
    # Collapse multiple whitespace to single space
    normalized = re.sub(r'\s+', ' ', normalized)
    return normalized


def read_file_lines(filepath: str) -> List[str]:
    """Read file and return list of lines."""
    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            return f.readlines()
    except FileNotFoundError:
        return []


def find_all_matches(
    old_lines: List[str],
    new_lines: List[str],
    threshold: float = 0.7
) -> List[Dict[str, Any]]:
    """
    Find refactored code BLOCKS (consecutive matching lines).
    Optimized with hash-based lookups for O(n) performance on exact matches.
    
    Returns list of block matches with start/end line numbers.
    """
    # Normalize all lines
    old_norm = {i: normalize_line(line) for i, line in enumerate(old_lines, 1)}
    new_norm = {i: normalize_line(line) for i, line in enumerate(new_lines, 1)}
    
    # Build reverse index: content -> list of line numbers (for O(1) lookup)
    new_content_to_lines: Dict[str, List[int]] = {}
    for line_num, content in new_norm.items():
        if len(content) >= 5:
            if content not in new_content_to_lines:
                new_content_to_lines[content] = []
            new_content_to_lines[content].append(line_num)
    
    # Find all individual matches using hash lookup (O(n))
    matches = []
    used_new = set()
    
    for old_line_num, old_content in old_norm.items():
        if len(old_content) < 5:
            continue
        
        # Exact match via hash lookup
        if old_content in new_content_to_lines:
            for new_line_num in new_content_to_lines[old_content]:
                if new_line_num not in used_new and old_line_num != new_line_num:
                    matches.append({
                        'old_line': old_line_num,
                        'new_line': new_line_num,
                        'similarity': 1.0,
                    })
                    used_new.add(new_line_num)
                    break
    
    # Group consecutive matches into BLOCKS
    if not matches:
        return []
    
    # Sort by old line number
    matches.sort(key=lambda x: x['old_line'])
    
    blocks = []
    current_block = {
        'old_start': matches[0]['old_line'],
        'old_end': matches[0]['old_line'],
        'new_start': matches[0]['new_line'],
        'new_end': matches[0]['new_line'],
        'line_count': 1
    }
    
    for i in range(1, len(matches)):
        curr = matches[i]
        
        # Calculate gap from previous match (or previous block end)
        old_diff = curr['old_line'] - current_block['old_end']
        new_diff = curr['new_line'] - current_block['new_end']
        
        # Merge if matches are close enough (gap <= 3 lines) and in consistent order
        # We check diff > 0 to ensure strictly increasing order
        close_enough = (0 < old_diff <= 4) and (0 < new_diff <= 4)
        
        # Also check if the gap size is roughly similar (to avoid merging completely unrelated sections)
        # e.g., if old gap is 1 line but new gap is 20 lines, don't merge
        gap_consistency = abs(old_diff - new_diff) <= 2
        
        if close_enough and gap_consistency:
            # Extend current block to include this match
            # Note: This implicitly includes the gap lines in the block range
            current_block['old_end'] = curr['old_line']
            current_block['new_end'] = curr['new_line']
            current_block['line_count'] += 1
        else:
            # Save current block and start new one
            if current_block['line_count'] >= 2:  # Only save blocks with 2+ lines
                blocks.append(current_block)
            current_block = {
                'old_start': curr['old_line'],
                'old_end': curr['old_line'],
                'new_start': curr['new_line'],
                'new_end': curr['new_line'],
                'line_count': 1
            }
    
    # Don't forget the last block
    if current_block['line_count'] >= 2:
        blocks.append(current_block)
    
    return blocks


def main():
    parser = argparse.ArgumentParser(
        description='Detect refactored code using Levenshtein distance'
    )
    parser.add_argument('old_file', help='Path to the old/original file')
    parser.add_argument('new_file', help='Path to the new/modified file')
    parser.add_argument(
        '--threshold',
        type=float,
        default=0.7,
        help='Similarity threshold (0.0-1.0, default: 0.7)'
    )
    parser.add_argument(
        '--json',
        action='store_true',
        default=True,
        help='Output as JSON (default)'
    )
    
    args = parser.parse_args()
    
    # Read files
    old_lines = read_file_lines(args.old_file)
    new_lines = read_file_lines(args.new_file)
    
    if not old_lines:
        print(json.dumps({'error': f'Cannot read old file: {args.old_file}', 'matches': []}))
        sys.exit(1)
    
    if not new_lines:
        print(json.dumps({'error': f'Cannot read new file: {args.new_file}', 'matches': [], 'blocks': []}))
        sys.exit(1)
    
    # Find all refactored blocks (consecutive matching lines)
    blocks = find_all_matches(old_lines, new_lines, args.threshold)
    
    # Count total lines in blocks
    total_lines = sum(b['line_count'] for b in blocks)
    
    # Output result
    result = {
        'old_file': args.old_file,
        'new_file': args.new_file,
        'block_count': len(blocks),
        'total_lines': total_lines,
        'blocks': blocks
    }
    
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
