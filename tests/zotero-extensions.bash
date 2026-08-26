#!/usr/bin/env bash

set -euo pipefail

: "${ZOTERO_PACKAGE:?ZOTERO_PACKAGE must be set}"

better_bibtex_xpi="$ZOTERO_PACKAGE/lib/distribution/extensions/better-bibtex@iris-advies.com.xpi"

if [[ ! -s "$better_bibtex_xpi" ]]; then
  printf 'Better BibTeX is not bundled in Zotero: %s\n' "$better_bibtex_xpi" >&2
  exit 1
fi

if [[ "$(od -An -tx1 -N4 "$better_bibtex_xpi" | tr -d ' \n')" != "504b0304" ]]; then
  printf 'Better BibTeX is not an XPI/ZIP archive: %s\n' "$better_bibtex_xpi" >&2
  exit 1
fi
