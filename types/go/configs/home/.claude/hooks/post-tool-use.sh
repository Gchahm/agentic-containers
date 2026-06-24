#!/bin/bash
# Logs tool usage for activity tracking
input=$(cat)
tool=$(echo "$input" | jq -r '.tool_name // empty')

case "$tool" in
  Read|Write|Edit|Bash|Grep|Glob|Agent) ;;
  *) exit 0 ;;
esac
