#!/usr/bin/env python3
"""
MailMate TextTemplate Change Root Script

This script allows users to change the template root directory. The template root directory is persistently stored in ~/.texttemplate_config.
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
    default_dir = get_templates_root()
    if not default_dir:
        default_dir = os.path.expanduser('~/Documents')
    result = subprocess.run([script_path, default_dir], capture_output=True, text=True)
    if result.returncode == 0:
        selected_dir = result.stdout.strip()
        if os.path.isdir(selected_dir):
            update_templates_root(selected_dir)
            return selected_dir
    return None

if __name__ == "__main__":
    # If invoked as main, let the user change the template root
    prompt_for_templates_root()

