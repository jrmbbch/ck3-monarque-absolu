#!/bin/sh
# Copies only the files the game needs into the game's mod folder, ready to be uploaded
# from the launcher (Steam Workshop or Paradox Mods). The repository itself also holds
# .git, tools/ and art/, which must not be published.
#
#   sh tools/build_release.sh
#
# Result:
#   <mod folder>/monarque_absolu/        the mod files (descriptor, thumbnail, common, localization)
#   <mod folder>/monarque_absolu.mod     the launcher entry pointing to it
#
# After the first upload, the launcher writes remote_file_id into
# <mod folder>/monarque_absolu/descriptor.mod: copy that line back into the repository's
# descriptor.mod and commit it, so later uploads update the same Workshop item.
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
MOD_DIR="${CK3_MOD_DIR:-$HOME/Documents/Paradox Interactive/Crusader Kings III/mod}"
TARGET="$MOD_DIR/monarque_absolu"

python3 "$REPO/tools/check_localization.py"

# Keep a remote_file_id written by the launcher in a previous build
REMOTE_ID=""
if [ -f "$TARGET/descriptor.mod" ]; then
	REMOTE_ID="$(grep '^remote_file_id=' "$TARGET/descriptor.mod" || true)"
fi

rm -rf "$TARGET"
mkdir -p "$TARGET"
cp -R "$REPO/common" "$REPO/localization" "$TARGET/"
cp "$REPO/descriptor.mod" "$REPO/thumbnail.png" "$TARGET/"
if [ -n "$REMOTE_ID" ] && ! grep -q '^remote_file_id=' "$TARGET/descriptor.mod"; then
	printf '%s\n' "$REMOTE_ID" >> "$TARGET/descriptor.mod"
fi
find "$TARGET" -name '.DS_Store' -delete

{
	grep -v '^remote_file_id=' "$TARGET/descriptor.mod"
	printf 'path="%s"\n' "$TARGET"
	[ -n "$REMOTE_ID" ] && printf '%s\n' "$REMOTE_ID"
} > "$MOD_DIR/monarque_absolu.mod"

echo "Release ready in $TARGET"
