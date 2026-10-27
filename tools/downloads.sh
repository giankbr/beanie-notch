#!/bin/bash
# Downloads of every release asset on GitHub, and the total. Needs the gh CLI signed in.
set -euo pipefail
repo="${1:-giankbr/brow}"
gh api "repos/$repo/releases" --paginate --jq '.[] | .tag_name as $t | .assets[] | "\($t)\t\(.name)\t\(.download_count)"' \
  | awk -F'\t' '{ printf "%-8s %-14s %6d\n", $1, $2, $3; total += $3 } END { printf "%-23s %6d\n", "total", total }'
