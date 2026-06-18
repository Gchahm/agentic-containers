#!/bin/bash
input=$(cat)

if [ -n "$CONTAINER_NAME" ]; then
    printf "\033[31m%s\033[0m |\033[0m " "$CONTAINER_NAME"
fi

current_dir=$(echo "$input" | jq -r '.workspace.current_dir // "unknown"')
folder=$(basename "$current_dir")

branch=$(git --no-optional-locks branch --show-current 2>/dev/null || echo "no-git")
changed=$(git --no-optional-locks status --porcelain 2>/dev/null | wc -l | tr -d ' ')
stashed=$(git --no-optional-locks stash list 2>/dev/null | wc -l | tr -d ' ')

model=$(echo "$input" | jq -r '.model.display_name // "unknown"')

context_size=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

if [ -n "$remaining" ] && [ "$context_size" -gt 0 ]; then
    used=$((100 - remaining))
    ctx="${used}%"
else
    ctx="0%"
fi

printf "\033[36m%s\033[0m" "$folder"

if [ "$branch" != "no-git" ]; then
    printf " \033[90m|\033[0m "
    if [ "$changed" -gt 0 ]; then
        printf "\033[33m%s" "$branch"
    else
        printf "\033[32m%s" "$branch"
    fi
    if [ "$changed" -gt 0 ]; then
        printf "\033[31m+%s\033[0m" "$changed"
    fi
    if [ "$stashed" -gt 0 ]; then
        printf "\033[36m stash:%s\033[0m" "$stashed"
    fi
fi

printf " \033[90m|\033[0m \033[35m%s\033[0m" "$model"
printf " \033[90m|\033[0m \033[90m%s\033[0m\n" "$ctx"
