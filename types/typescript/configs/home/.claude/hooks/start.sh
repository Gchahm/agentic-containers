#!/bin/bash
input=$(cat)
ts=$(date +%s)
prompt=$(echo "$input" | jq -r '.prompt // empty' | head -c 500)
tp=$(echo "$input" | jq -r '.transcript_path // empty')
[ -n "$tp" ] && echo "$tp" > /tmp/claude-transcript-file

case "$prompt" in
  *"<task-notification"*|*"<system-reminder"*|*"[Request interrupted"*) exit 0 ;;
esac

jq -nc --arg p "$prompt" --argjson t "$ts" \
  '{type:"start",prompt:$p,ts:$t}' >> /tmp/claude-activity.log
