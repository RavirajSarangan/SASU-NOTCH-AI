#!/bin/zsh
# Sends sample agent events to a running Nova.
#   scripts/send_test_event.sh start|prompt|tool|done|stop|error|notify|demo
set -euo pipefail
SOCK="${NOVA_SOCKET:-$HOME/Library/Application Support/Nova/nova.sock}"
SID="${SESSION_ID:-demo-session}"
CWD="${PWD}"

send() { print -r -- "$1" | nc -U "$SOCK"; }
event() { send "{\"agent\":\"${AGENT:-claude}\",\"sessionId\":\"$SID\",\"workingDirectory\":\"$CWD\",$1}"; }

case "${1:-demo}" in
  start)  event '"event":"session_start"' ;;
  prompt) event '"event":"prompt","description":"Refactor the networking layer"' ;;
  tool)   event '"event":"tool_start","tool":"Edit","description":"Editing APIClient.swift","filePath":"'"$CWD"'/Sources/APIClient.swift"' ;;
  done)   event '"event":"tool_end","tool":"Edit"' ;;
  bash)   event '"event":"tool_start","tool":"Bash","description":"Running npm test","command":"npm test"' ;;
  stop)   event '"event":"stop"' ;;
  error)  event '"event":"error","message":"API rate limit reached"' ;;
  notify) event '"event":"notification","message":"Claude is waiting for your input"' ;;
  demo)
    for step in start prompt tool done bash; do "$0" "$step"; sleep 1.2; done
    "$0" done; sleep 1; "$0" stop ;;
  *) echo "usage: $0 start|prompt|tool|done|bash|stop|error|notify|demo" >&2; exit 1 ;;
esac
