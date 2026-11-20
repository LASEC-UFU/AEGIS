#!/usr/bin/env bash
# Runs the given command at BelowNormal priority (Windows children inherit it).
# Used for every Phase-0 build and run while other experiments share the machine.
if [ -r /proc/$$/winpid ]; then
  powershell.exe -NoProfile -Command "(Get-Process -Id $(cat /proc/$$/winpid)).PriorityClass = 'BelowNormal'" >/dev/null 2>&1
fi
exec "$@"
