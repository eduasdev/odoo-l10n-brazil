#!/bin/sh
# Usage: fetch_from_lockfile.sh <branch> <lockfile>
#
# Reads <lockfile> and for each entry:
#   - clones the repo at <branch>
#   - checks out the pinned SHA
#   - copies the specified modules (or all addons if * / omitted) to /addons
#   - appends any requirements.txt to /build/requirements.txt
set -eu

BRANCH="$1"
LOCKFILE="$2"

mkdir -p /repos /addons /build
touch /build/requirements.txt

while IFS= read -r line; do
  # Skip comments and blank lines
  case "$line" in '#'*|'') continue ;; esac

  repo=$(printf '%s' "$line"    | awk '{print $1}')
  sha=$(printf '%s' "$line"     | awk '{print $2}')
  modules=$(printf '%s' "$line" | awk '{for(i=3;i<=NF;i++) print $i}')

  echo ">>> $repo @ $sha"

  git clone --depth 1 --branch "$BRANCH" \
    "https://github.com/$repo.git" "/repos/$repo"

  git -C "/repos/$repo" fetch --depth 1 origin "$sha"
  git -C "/repos/$repo" checkout "$sha"

  # Determine if we should fetch all modules or specific ones
  module_list=$(printf '%s' "$modules" | tr -d ' \n')
  if [ -z "$module_list" ] || [ "$module_list" = "*" ]; then
    # Copy all Odoo addons found in the repo root
    for d in "/repos/$repo"/*/; do
      [ -f "${d}__manifest__.py" ] && cp -r "$d" /addons/
    done
  else
    for module in $modules; do
      [ "$module" = "*" ] && continue
      d="/repos/$repo/$module"
      if [ ! -f "$d/__manifest__.py" ]; then
        echo "ERROR: '$module' not found in $repo @ $sha" >&2
        exit 1
      fi
      cp -r "$d" /addons/
    done
  fi

  if [ -f "/repos/$repo/requirements.txt" ]; then
    echo "# --- $repo ($sha)" >> /build/requirements.txt
    cat "/repos/$repo/requirements.txt" >> /build/requirements.txt
  fi

done < "$LOCKFILE"
