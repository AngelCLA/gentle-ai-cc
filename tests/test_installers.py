"""Installer fixtures moved to native shell runners; no Python tests remain here.

Bash:       bash tests/test_installers.sh
PowerShell: pwsh -NoProfile -File tests/installers.ps1

The Python-dependent help/state suites remain in test_help.py and test_wrapper.py.
This migration notice intentionally contains no unittest delegation or test cases.
"""
