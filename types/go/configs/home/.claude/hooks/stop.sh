#!/bin/bash
input=$(cat)
ts=$(date +%s)
transcript=$(echo "$input" | jq -r '.transcript_path // empty')
[ -n "$transcript" ] && echo "$transcript" > /tmp/claude-transcript-file

full_summary=$(echo "$input" | jq -r '.last_assistant_message // empty')
if [ ${#full_summary} -gt 2000 ]; then
  summary="${full_summary:0:2000}..."
else
  summary="$full_summary"
fi

jq -nc --argjson t "$ts" --arg s "$summary" \
  '{type:"stop",summary:$s,ts:$t}' >> /tmp/claude-activity.log
