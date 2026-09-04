#!/bin/bash
# pace-statusline-segment.sh — one short segment for the Claude Code statusline.
# Reads ~/Library/Application Support/Pace/report.json. No network. Prints nothing if absent.
# PACE_REPORT env var overrides the report path (used for testing the stale branch).
set -u
F="${PACE_REPORT:-$HOME/Library/Application Support/Pace/report.json}"
[ -r "$F" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
now=$(date +%s)
gen=$(jq -r '.generatedAt' "$F" 2>/dev/null) || exit 0
gen_s=$(TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%SZ' "$gen" +%s 2>/dev/null || echo 0)
if [ $((now - gen_s)) -gt 600 ]; then printf 'pace stale'; exit 0; fi
jq -r '
  def short: if .kind=="fableWeek" then "Fable wk" elif .kind=="allModelsWeek" then "All wk" elif .kind=="session" then "5h"
             elif .kind=="codexSession" then "Codex 5h" elif .kind=="codexWeek" then "Codex wk" else .kind end;
  def arrow: if .status=="ahead" or .status=="capped" then "↑" else "" end;
  def cap: if .projectedCapAt then " caps " + (.projectedCapAt | sub("\\.[0-9]+";"") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime | localtime | strftime("%H:%M")) else "" end;
  (.headline.kind // "") as $hk |
  ([.headline | select(.!=null) | (short + " " + (.percentUsed|tostring) + "%" + arrow + cap)]
   + [.windows[] | select(.kind=="session" and .kind != $hk) | ("5h " + (.percentUsed|tostring) + "%")]
  ) | join(" · ")' "$F" 2>/dev/null | tr -d '\n'
