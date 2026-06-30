#!/bin/sh
set -eu

BRANCH="$1"
REPO="$2"
shift 2

mkdir -p /repos /addons /build
touch /build/requirements.txt

git clone --progress --depth 1 --branch "$BRANCH" "https://github.com/$REPO.git" "/repos/$REPO"

if [ "$#" -gt 0 ]; then
  # Specific module(s) given: copy only those, not the whole repo.
  for module in "$@"; do
    d="/repos/$REPO/$module"
    if [ ! -f "$d/__manifest__.py" ]; then
      echo "fetch_addon_mod.sh: '$module' not found in $REPO@$BRANCH" >&2
      exit 1
    fi
    cp -r "$d" /addons/
  done
else
  for d in "/repos/$REPO"/*/; do
    if [ -f "$d/__manifest__.py" ]; then
      cp -r "$d" /addons/
    fi
  done
fi

if [ -f "/repos/$REPO/requirements.txt" ]; then
  echo "# --- $REPO (branch $BRANCH)" >> /build/requirements.txt
  cat "/repos/$REPO/requirements.txt" >> /build/requirements.txt
fi
