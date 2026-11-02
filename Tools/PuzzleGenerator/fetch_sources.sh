#!/usr/bin/env bash
# Downloads the raw word sources used by generate.py into ./.sources (git-ignored).
# Every source is pinned to a commit so that the generated packs are reproducible, and checked
# against its SHA-256 in sources.sha256: a truncated or altered download would otherwise build a
# different lexicon without any error. generate.py checks the same list before it starts, so a
# .sources folder fetched before a source was pinned, or edited since, is caught there too.
set -euo pipefail
cd "$(dirname "$0")"
DEST=".sources"
# Checked up front: without them a download would fail later as "download failed" or "checksum
# mismatch", which reads like a problem with the source rather than with this machine.
for tool in curl shasum awk; do
    command -v "$tool" >/dev/null || { echo "  ✗ $tool is not installed; it is needed to fetch the sources" >&2; exit 1; }
done
mkdir -p "$DEST/enable" "$DEST/hunspell_en" "$DEST/hunspell_cs" "$DEST/blocklist"

ENABLE="https://raw.githubusercontent.com/dolph/dictionary/233d25a56b9ac8bef906916ccf091a976995cce0"
HUNSPELL="https://raw.githubusercontent.com/LibreOffice/dictionaries/4f1df64b2e8e14751aa7c2205d170ca016071315"
BLOCKLIST="https://raw.githubusercontent.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words/5faf2ba42d7b1c0977169ec3611df25a3c08eb13"

# Downloads to a temporary file next to the destination and moves it into place only once its
# checksum matches, so that a failed run never leaves a partial file behind; one interrupted
# (Ctrl-C) removes its temporary file on the way out.
tmp=""
trap '[ -n "$tmp" ] && rm -f "$tmp"' EXIT
fetch() {
    local url="$1" file="$2" sha
    local dest="$DEST/$file"
    sha="$(awk -v f="$file" '$2 == f { print $1 }' sources.sha256)"
    if [ -z "$sha" ]; then
        echo "  ✗ $dest: no checksum in sources.sha256" >&2
        return 1
    fi
    tmp="$(mktemp "$dest.XXXXXX")"
    if ! curl -sSfL --retry 3 -o "$tmp" "$url"; then
        rm -f "$tmp"
        echo "  ✗ $dest: download failed" >&2
        return 1
    fi
    if [ "$(shasum -a 256 "$tmp" | cut -d ' ' -f 1)" != "$sha" ]; then
        rm -f "$tmp"
        echo "  ✗ $dest: checksum mismatch (expected $sha)" >&2
        return 1
    fi
    # mktemp makes the file readable by its owner only.
    chmod 644 "$tmp"
    mv "$tmp" "$dest"
    tmp=""
    echo "  ✓ $dest"
}

echo "Fetching word sources…"
fetch "$ENABLE/enable1.txt" enable/enable1.txt
fetch "$HUNSPELL/en/en_US.dic" hunspell_en/en_US.dic
fetch "$HUNSPELL/en/en_US.aff" hunspell_en/en_US.aff
fetch "$HUNSPELL/cs_CZ/cs_CZ.dic" hunspell_cs/cs_CZ.dic
fetch "$HUNSPELL/cs_CZ/cs_CZ.aff" hunspell_cs/cs_CZ.aff
fetch "$BLOCKLIST/en" blocklist/en
fetch "$BLOCKLIST/cs" blocklist/cs
echo "Done."
