#!/usr/bin/env bash
#
#
set -o nounset
set -o errexit
set -o pipefail
export VERSION="$1"
TPL="$HOME/git/tf3-website/content/docs/references/${VERSION%%-*}/._index.md"
OUT="$HOME/git/tf3-website/content/docs/references/${VERSION%%-*}/_index.md"
go run projects/gendocs/gendocs.go --tpl "$TPL" --out "$OUT"