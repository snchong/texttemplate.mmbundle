#!/usr/bin/env python3

import os

def insert_text_at_line(filepath, line_number, text):
    with open(filepath, 'r') as f:
        lines = f.readlines()
    # Adjust for zero-based index
    idx = max(0, int(line_number) - 1)
    lines.insert(idx, text + '\n')
    with open(filepath, 'w') as f:
        f.writelines(lines)

if __name__ == "__main__":
    line_number = os.environ.get('MM_LINE_NUMBER')
    filepath = os.environ.get('MM_EDIT_FILEPATH')
    if not line_number or not filepath:
        raise ValueError("MM_LINE_NUMBER and MM_EDIT_FILEPATH must be set in the environment.")
        
    insert_text_at_line(filepath, line_number, "Hello World")