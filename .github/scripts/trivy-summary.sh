#!/usr/bin/env bash
# Markdown summary of a Trivy JSON report: findings per target.
# usage: trivy-summary.sh <title> <report.json>
set -euo pipefail

title=$1
report=$2

if [ ! -s "$report" ]; then
  echo "### Trivy: $title"
  echo "No report (scan failed)."
  exit 0
fi

echo "### Trivy: $title"
jq -r '
  def n(s): [.[] | select(.Severity == s)] | length;
  [.Results[]? | {
    t: .Target,
    c: .Class,
    f: ((.Vulnerabilities // []) + (.Secrets // [])
        + [(.Misconfigurations // [])[] | select(.Status == "FAIL")])
  } | select(.f | length > 0)]
  | if length == 0 then "No HIGH/CRITICAL findings with a fix."
    else
      "| Target | Type | Critical | High |",
      "|---|---|---|---|",
      (.[] | "| `\(.t)` | \(.c) | \(.f | n("CRITICAL")) | \(.f | n("HIGH")) |")
    end
' "$report"
echo
echo "Full list: Security -> Code scanning, tool Trivy."
