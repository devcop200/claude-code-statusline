#!/bin/bash
# Claude Code status line: model, dir, context %, tokens, 5h limit, cache stats
input=$(cat)

# Colors
R=$'\033[0m'; B=$'\033[1m'; D=$'\033[2m'
RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; BLU=$'\033[34m'; MAG=$'\033[35m'; CYN=$'\033[36m'
SEP=" ${D}│${R} "

model=$(echo "$input" | jq -r '.model.display_name // "?"')
dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "?"')
dir="${dir/#$HOME/\~}"
ctx=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
five=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')

fmt() { awk -v n="$1" 'BEGIN{ if(n>=1000000) printf "%.1fM", n/1000000; else if(n>=1000) printf "%.1fk", n/1000; else printf "%d", n }'; }
# Color for a "used" percentage: green < 50, yellow < 80, red otherwise
usecolor() { local p=${1%.*}; if [ "$p" -lt 50 ]; then echo "$GRN"; elif [ "$p" -lt 80 ]; then echo "$YEL"; else echo "$RED"; fi; }
# 10-cell bar plus percentage, colored by usage; "-" when unknown
bar() {
  [ -z "$1" ] && { printf '%s-%s' "$D" "$R"; return; }
  local p=${1%.*} c f i out=""
  c=$(usecolor "$p"); f=$(( (p + 5) / 10 )); [ "$f" -gt 10 ] && f=10
  for ((i = 0; i < 10; i++)); do [ "$i" -lt "$f" ] && out+="▰" || out+="▱"; done
  printf '%s%s %d%%%s' "$c" "$out" "$p" "$R"
}

line1="${B}${MAG}◆ ${model}${R}  ${BLU}${dir}${R}"
line1+="${SEP}${D}ctx${R} $(bar "$ctx")"
# Session tokens that were not cache re-reads: input + cache writes + output,
# summed over the transcript (deduped by message id, last entry wins).
tp=$(echo "$input" | jq -r '.transcript_path // empty')
new=""
if [ -n "$tp" ] && [ -r "$tp" ]; then
  new=$(jq -n -r '
    [inputs | select(.message.usage != null) | {id: (.message.id // .uuid), u: .message.usage}]
    | group_by(.id) | map(last.u)
    | map((.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.output_tokens // 0)) | add // 0' "$tp" 2>/dev/null)
fi
line1+="${SEP}${D}tokens${R} ${B}${CYN}$( [ -n "$new" ] && fmt "$new" || echo '-' )${R}"
line1+="${SEP}${D}5h${R} $(bar "$five")"

# Cache statistics
kv() { printf '%s%s%s %s' "$D" "$1" "$R" "$2"; }
if [ "$(echo "$input" | jq -r '.prompt_cache != null')" != "true" ]; then
  cache="${D}cache n/a${R}"
else
  IFS=$'\x1f' read -r hit exp miss reb mrc crc cause written causes lm <<< "$(echo "$input" | jq -r '
    .prompt_cache as $c | [
      (if $c.hit_ratio == null then "" else (($c.hit_ratio * 100) | floor | tostring) end),
      ($c.expires_at // "" | tostring),
      ($c.misses // 0), ($c.expected_rebuilds // 0),
      ($c.miss_recache_tokens // 0), ($c.recache_tokens_if_cold // ""),
      (if $c.last_miss_cause == null then "" else ($c.last_miss_cause.causes | join(",")) end),
      ($c.cache_write_tokens // 0),
      (($c.miss_causes // {}) | to_entries | map(.key + ":" + (.value | tostring)) | join(",")),
      ($c.last_miss_at // "" | tostring)
    ] | map(tostring) | join("\u001f")')"

  # hit: green >= 90, yellow >= 70, red otherwise
  if [ -z "$hit" ]; then hit_s="${D}-${R}"
  elif [ "$hit" -ge 90 ]; then hit_s="${GRN}${hit}%${R}"
  elif [ "$hit" -ge 70 ]; then hit_s="${YEL}${hit}%${R}"
  else hit_s="${RED}${hit}%${R}"; fi

  # expires: mm:ss countdown; green > 5m, yellow > 1m, red otherwise
  if [ -z "$exp" ]; then exp_s="${D}-${R}"
  else
    left=$(( exp - $(date +%s) )); [ "$left" -lt 0 ] && left=0
    if [ "$left" -gt 300 ]; then c=$GRN; elif [ "$left" -gt 60 ]; then c=$YEL; else c=$RED; fi
    exp_s=$(printf '%s%s%d:%02d%s' "$B" "$c" $((left / 60)) $((left % 60)) "$R")
  fi

  # miss: red when there are misses without an expected cause
  if [ "$miss" -gt "$reb" ]; then miss_s="${RED}${miss}${R}"; else miss_s="$miss"; fi

  cache="${D}cache${R}  $(kv hit "$hit_s")  $(kv '⏱' "$exp_s")"
  cache+="${SEP}$(kv miss "$miss_s")  $(kv rebuilds "$reb")"
  cache+="${SEP}$(kv miss_recache "$(fmt "$mrc")")  $(kv cold_recache "$( [ -n "$crc" ] && fmt "$crc" || echo '-' )")"
  cache+="${SEP}$(kv last_miss_cause "${cause:--}")  $(kv written "$(fmt "$written")")"
  [ -n "$causes" ] && cache+="  $(kv causes "$causes")"
  cache+="  $(kv last_miss "$( [ -n "$lm" ] && date -d @"$lm" +%H:%M:%S || echo '-' )")"
fi

printf '%s\n%s\n' "$line1" "$cache"
