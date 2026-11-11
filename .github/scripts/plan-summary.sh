#!/usr/bin/env bash
# Prints a Markdown summary of a Terraform plan for $GITHUB_STEP_SUMMARY.
# Usage: plan-summary.sh <environment> <plan.txt>
set -uo pipefail

environment="$1"
plan_file="$2"

summary="$(grep -E '^(Plan:|No changes\.)' "$plan_file" 2>/dev/null || echo 'Plan unavailable')"

echo "### Plan: \`${environment}\`"
echo ""
echo "**${summary}**"
echo ""
echo "<details>"
echo "<summary>Terraform plan (${environment})</summary>"
echo ""
echo '```text'
# Step summaries are limited to 1 MiB.
head -c 500000 "$plan_file" 2>/dev/null || echo "Plan unavailable"
echo '```'
echo "</details>"
echo ""
