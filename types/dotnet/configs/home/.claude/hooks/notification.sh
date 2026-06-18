#!/bin/bash
ts=$(date +%s)
jq -nc --argjson t "$ts" '{type:"needs_input",ts:$t}' >> /tmp/claude-activity.log
