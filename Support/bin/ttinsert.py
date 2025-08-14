#!/usr/bin/env python3
"""
MailMate Text Template Insertion Script

This script allows users to insert the contents of a selected template file into a target file at a specified line. The template root directory is persistently stored in ~/.texttemplate_config and can be changed by the user. If not set, the user is prompted to select a directory using a GUI dialog.
"""
import os
import subprocess

def get_config_path():
    """Returns the path to the config file storing the template root directory."""
    return os.path.expanduser('~/.texttemplate_config')

def get_templates_root():
    """Gets the templates root directory from the config file."""
    config_path = get_config_path()
    if os.path.isfile(config_path):
        with open(config_path, 'r') as f:
            path = f.read().strip()
            if path:
                return path
    return None

def update_templates_root(path):
    """Writes the templates root directory to the config file."""
    config_path = get_config_path()
    with open(config_path, 'w') as f:
        f.write(path.strip() + '\n')

def prompt_for_templates_root():
    # Use pick-root.swift to select a directory
    script_path = os.path.join(os.path.dirname(__file__), 'pick-root.swift')
    result = subprocess.run([script_path, os.path.expanduser('~/Documents')], capture_output=True, text=True)
    if result.returncode == 0:
        selected_dir = result.stdout.strip()
        if os.path.isdir(selected_dir):
            update_templates_root(selected_dir)
            return selected_dir
    return None


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

def get_config_path():
    """
    Returns the path to the config file storing the template root directory.
    """
    return os.path.expanduser('~/.texttemplate_config')

def get_template_root():
    """
    Gets the template root directory from the config file.
    Returns:
        str or None: The template root path, or None if not set.
    """
    config_path = get_config_path()
    if os.path.isfile(config_path):
        with open(config_path, 'r') as f:
            path = f.read().strip()
            if path:
                return path
    return None

def write_template_root(path):
    """
    Writes the template root directory to the config file.
    Args:
        path (str): Directory path to store.
    """
    config_path = get_config_path()
    with open(config_path, 'w') as f:
        f.write(path.strip() + '\n')

def prompt_for_template_root():
    """
    Prompts the user to select a template root directory using pick-template.swift.
    Stores the selected directory in the config file.
    Returns:
        str or None: The selected directory path, or None if cancelled.
    """
    script_path = os.path.join(os.path.dirname(__file__), 'pick-template.swift')
    result = subprocess.run([script_path, os.path.expanduser('~')], capture_output=True, text=True)
    if result.returncode == 0:
        selected_dir = result.stdout.strip()
        if os.path.isdir(selected_dir):
            write_template_root(selected_dir)
            return selected_dir
    return None

def get_template(template_root):
    """
    Prompts the user to select a template file from the template root directory.
    Returns the contents of the selected file, or None if cancelled.
    Args:
        template_root (str): Directory to search for templates.
    Returns:
        str or None: Contents of the selected template file, or None.
    """
    script_path = os.path.join(os.path.dirname(__file__), 'pick-template.swift')
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

if __name__ == "__main__":
    line_number = os.environ.get('MM_LINE_NUMBER')
    filepath = os.environ.get('MM_EDIT_FILEPATH')

    if not line_number or not filepath:
        raise ValueError("MM_LINE_NUMBER and MM_EDIT_FILEPATH must be set in the environment.")

    templates_root = get_templates_root()
    if not templates_root:
        templates_root = prompt_for_templates_root()
    if templates_root:
        template_contents = get_template(templates_root)
        if template_contents is not None:
            insert_text_at_line(filepath, line_number, replace_tags(template_contents))
            # mm_env = {k: v for k, v in os.environ.items() if k.startswith('MM_')}
            # env_output = '\n'.join(f'{k}={v}' for k, v in mm_env.items())
            # insert_text_at_line(filepath, line_number, env_output)
    else:
        # Give user an error message, in a GUI
        subprocess.run(["osascript", "-e", 'display dialog "Can not get a template root directory." with title "Text Template Error"buttons {"OK"} default button "OK" '])


