#!/usr/bin/env python3
"""
MailMate TextTemplate Insertion Script

This script allows users to insert the contents of a selected template file into a target file at a specified line. The template root directory is persistently stored in ~/.texttemplate_config and can be changed by the user. If not set, the user is prompted to select a directory using a GUI dialog.
"""
import os
import subprocess
import templates_root

def insert_text_at_line(filepath, line_number, text):
    """
    Insert the given text at the specified line number in the file.
    Args:
        filepath (str): Path to the file to modify.
        line_number (int or str): Line number (1-based) to insert at.
        text (str): Text to insert.
    """
    with open(filepath, 'r') as f:
        lines = f.readlines()
    idx = max(0, int(line_number) - 1)
    lines.insert(idx, text)
    with open(filepath, 'w') as f:
        f.writelines(lines)

def get_template(template_root):
    """
    Prompts the user to select a template file from the template root directory.
    Returns the contents of the selected file, or None if cancelled.
    Args:
        template_root (str): Directory to search for templates.
    Returns:
        str or None: Contents of the selected template file, or None.
    """
    picker_prog = "pick-template-browser"
    # picker_prog = "pick-template-panel"
    compiled_path = os.path.join(os.path.dirname(__file__), picker_prog)
    script_path = compiled_path if os.path.isfile(compiled_path) and os.access(compiled_path, os.X_OK) else os.path.join(os.path.dirname(__file__), picker_prog + '.swift')
    try:
        result = subprocess.run([script_path, template_root], capture_output=True, text=True)
        if result.returncode == 0:
            selected_file = result.stdout.strip()
            if os.path.isfile(selected_file):
                with open(selected_file, 'r') as tf:
                    return tf.read()
        else:
            # User cancelled or error occurred; do nothing
            pass
    except Exception as e:
        pass    
    return None

def replace_tags(text):
    """Replace QuickText-style tags"""
    # Currently we only support [[TO=firstname]] and [[TO=fullname]]
    text = text.replace('[[TO=firstname]]', os.environ.get('MM_TO_NAME_FIRST', ''))
    text = text.replace('[[TO=fullname]]', os.environ.get('MM_TO_NAME', ''))
    return text

def in_composer():
    """
    Check if the script is running in a MailMate composer window.
    """
    return True

if __name__ == "__main__":
    line_number = os.environ.get('MM_LINE_NUMBER')
    filepath = os.environ.get('MM_EDIT_FILEPATH')

    if not line_number or not filepath:
        raise ValueError("MM_LINE_NUMBER and MM_EDIT_FILEPATH must be set in the environment.")


    if not in_composer():
        subprocess.run(["osascript", "-e", 'display dialog "TextTemplate can only be run from a composer window." with title "TextTemplate Error" buttons {"OK"} default button "OK" '])
        exit(1)

    templates_root = templates_root.get_templates_root()
    if not templates_root:
        templates_root = templates_root.prompt_for_templates_root()
    if templates_root:
        template_contents = get_template(templates_root)
        if template_contents is not None:
            insert_text_at_line(filepath, line_number, replace_tags(template_contents))
            # mm_env = {k: v for k, v in os.environ.items() if k.startswith('MM_')}
            # env_output = '\n'.join(f'{k}={v}' for k, v in mm_env.items())
            # insert_text_at_line(filepath, line_number, env_output)
    else:
        # Give user an error message, in a GUI
        subprocess.run(["osascript", "-e", 'display dialog "Can not get a template root directory." with title "TextTemplate Error" buttons {"OK"} default button "OK" '])


