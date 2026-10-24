#!/usr/bin/env bash
# shellcheck disable=SC2016 # jq programs are single-quoted on purpose
# Scan the container images a PR adds or bumps with trivy and post the
# HIGH/CRITICAL (fixable) delta against the images they replace as a sticky PR comment.
set -euo pipefail

: "${FORGEJO_API_URL:?}" "${FORGEJO_REPOSITORY:?}" "${FORGEJO_TOKEN:?}" "${PR_NUMBER:?}"
DRY_RUN="${DRY_RUN:-false}" # true = print the comment, don't post it
BASE_REF="${BASE_REF:-main}"
GATE="${GATE:-false}" # true = fail the check when a PR introduces a fixable CRITICAL
MAX_IMAGES="${MAX_IMAGES:-25}"
MARKER="<!-- image-scan -->"

FLATE="$(mise which flate)"
TRIVY="$(mise which trivy)"
JQ="$(mise which jq)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Diff against the merge-base so a branch that is behind main doesn't report main's newer images as removed
base="$(git merge-base "origin/${BASE_REF}" HEAD)"
"$FLATE" diff images -p ./kubernetes/flux/cluster --base "$base" -o json >"$WORK/new.json"
"$FLATE" diff images -p ./kubernetes/flux/cluster --base "$base" --include-removed -o json >"$WORK/all.json"

# repository without tag/digest (keeps registry ports like host:5000)
REPO='sub("@.*$"; "") | if (split("/") | last | contains(":")) then sub(":[^:/]*$"; "") else . end'
# repo:tag without digest, for display
SHORT='sub("@.*$"; "")'

"$JQ" -c --slurpfile all "$WORK/all.json" '
  . as $new | ($all[0] - $new) as $old
  | [ $new[] | . as $n
      | { new: $n, old: ([ $old[] | select((. | '"$REPO"') == ($n | '"$REPO"')) ] | first) } ]
' "$WORK/new.json" >"$WORK/pairs.json"

count="$("$JQ" length "$WORK/pairs.json")"

# Findings for one image as a sorted JSON array of {id,pkg,sev,fixed}; "error" on scan failure
scan() {
  local img="$1" out="$WORK/scan.json" attempt
  for attempt in 1 2; do
    # The runner sets GITHUB_TOKEN to the Forgejo job token; trivy would send it to ghcr.io
    # (DENIED) instead of pulling anonymously, so drop it for these public image pulls
    if env -u GITHUB_TOKEN -u GH_TOKEN "$TRIVY" image --quiet --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed \
      --format json --output "$out" "$img" >&2; then
      break
    fi
    if [[ "$attempt" -eq 2 ]]; then
      echo '"error"'
      return
    fi
    sleep 10
  done
  "$JQ" -c '[.Results[]?.Vulnerabilities[]? | {id: .VulnerabilityID, pkg: .PkgName, sev: .Severity, fixed: .FixedVersion}] | unique' "$out"
}

gate_failed=false
if [[ "$count" -eq 0 ]]; then
  body="No container image changes."
elif [[ "$count" -gt "$MAX_IMAGES" ]]; then
  body="$count images changed (more than $MAX_IMAGES); skipped. Run the trivy runbook instead."
else
  rows=""
  details=""
  for i in $(seq 0 $((count - 1))); do
    new="$("$JQ" -r ".[$i].new" "$WORK/pairs.json")"
    old="$("$JQ" -r ".[$i].old // empty" "$WORK/pairs.json")"
    echo "::group::trivy $new" >&2
    new_f="$(scan "$new")"
    old_f='[]'
    [[ -n "$old" ]] && old_f="$(scan "$old")"
    echo "::endgroup::" >&2

    new_s="$("$JQ" -rn --arg i "$new" '$i | '"$SHORT")"
    from="new"
    [[ -n "$old" ]] && from="$("$JQ" -rn --arg i "$old" '$i | '"$SHORT" | sed 's/.*://')"

    if [[ "$new_f" == '"error"' ]]; then
      rows+="| \`$new_s\` | $from | ⚠️ scan failed | | | |"$'\n'
      continue
    fi
    [[ "$old_f" == '"error"' ]] && old_f='[]'

    row="$("$JQ" -rn --argjson n "$new_f" --argjson o "$old_f" '
      ($n - $o) as $intro | ($o - $n) as $fixed
      | [ ($n | map(select(.sev == "HIGH")) | length),
          ($n | map(select(.sev == "CRITICAL")) | length),
          ($intro | length),
          ($intro | map(select(.sev == "CRITICAL")) | length),
          ($fixed | length) ] | @tsv')"
    read -r high crit intro intro_crit fixed <<<"$row"

    status="✅"
    if [[ "$intro_crit" -gt 0 ]]; then
      status="❌"
      gate_failed=true
    elif [[ "$intro" -gt 0 ]]; then
      status="⚠️"
    fi
    rows+="| \`$new_s\` | $from | $status | $high / $crit | $intro | $fixed |"$'\n'

    if [[ "$intro" -gt 0 ]]; then
      list="$("$JQ" -rn --argjson n "$new_f" --argjson o "$old_f" '
        ($n - $o) | sort_by(.sev != "CRITICAL", .id)[]
        | "- \(if .sev == "CRITICAL" then "**CRITICAL**" else "HIGH" end) [\(.id)](https://avd.aquasec.com/nvd/\(.id | ascii_downcase)) in `\(.pkg)` (fixed in \(.fixed))"')"
      details+=$'\n'"<details><summary>Introduced by <code>$new_s</code></summary>"$'\n\n'"$list"$'\n\n'"</details>"$'\n'
    fi
  done

  body="| Image | From | | HIGH / CRIT | Introduced | Fixed |
|---|---|---|---|---|---|
${rows}${details}
Fixable HIGH/CRITICAL only (\`trivy image --ignore-unfixed\`). \"Introduced\" and \"Fixed\" compare against the image being replaced."
fi

comment="$MARKER
### 🔍 Image scan

$body"

echo "$comment"

# Upsert one sticky comment
if [[ "$DRY_RUN" == "true" ]]; then
  exit 0
fi
api="$FORGEJO_API_URL/repos/$FORGEJO_REPOSITORY/issues"
auth=(-H "Authorization: token $FORGEJO_TOKEN" -H "Content-Type: application/json")
# Only edit our own comment (a comment left by another account can't be edited); empty = any author
me="$(curl -fsS "${auth[@]}" "$FORGEJO_API_URL/user" 2>/dev/null | "$JQ" -r '.login // empty' || true)"
existing="$(curl -fsS "${auth[@]}" "$api/$PR_NUMBER/comments?limit=50" |
  "$JQ" -r --arg m "$MARKER" --arg me "$me" \
    '[.[] | select((.body | startswith($m)) and ($me == "" or .user.login == $me))] | first | .id // empty')"
payload="$("$JQ" -n --arg b "$comment" '{body: $b}')"
if [[ -n "$existing" ]]; then
  curl -fsS -X PATCH "${auth[@]}" -d "$payload" "$api/comments/$existing" >/dev/null
elif [[ "$count" -gt 0 ]]; then
  curl -fsS -X POST "${auth[@]}" -d "$payload" "$api/$PR_NUMBER/comments" >/dev/null
fi

if [[ "$GATE" == "true" && "$gate_failed" == "true" ]]; then
  echo "::error::PR introduces a fixable CRITICAL vulnerability"
  exit 1
fi
