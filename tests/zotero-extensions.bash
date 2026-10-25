#!/usr/bin/env bash

set -euo pipefail

: "${ZOTERO_PACKAGE:?ZOTERO_PACKAGE must be set}"

# Older Zotero releases crash indexing HTML with newer ESR 140 runtimes.
# 10.0.2 contains the upstream compatibility fix (nixpkgs#561292).
zotero_version=""
while IFS='=' read -r key value; do
  if [[ "$key" == "Version" ]]; then
    zotero_version="$value"
    break
  fi
done < "$ZOTERO_PACKAGE/lib/app/application.ini"
if [[ -z "$zotero_version" ]] ||
  [[ "$(printf '%s\n' 10.0.2 "$zotero_version" | sort -V | head -n1)" != "10.0.2" ]]; then
  printf 'Zotero must be >= 10.0.2 for HTML indexing compatibility; got %s\n' "$zotero_version" >&2
  exit 1
fi

better_bibtex_xpi="$ZOTERO_PACKAGE/lib/distribution/extensions/better-bibtex@iris-advies.com.xpi"

if [[ ! -s "$better_bibtex_xpi" ]]; then
  printf 'Better BibTeX is not bundled in Zotero: %s\n' "$better_bibtex_xpi" >&2
  exit 1
fi

if [[ "$(od -An -tx1 -N4 "$better_bibtex_xpi" | tr -d ' \n')" != "504b0304" ]]; then
  printf 'Better BibTeX is not an XPI/ZIP archive: %s\n' "$better_bibtex_xpi" >&2
  exit 1
fi
