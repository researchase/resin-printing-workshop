#!/usr/bin/env bash
# Push the landing page to the Pi, where Violet serves it at /resinlab/.
#
# Only site/ goes across. The Godot simulator is a ~37 MB build that stays on
# GitHub Pages; the landing page links out to it absolutely, so the same files
# work from either host.
set -euo pipefail
cd "$(dirname "$0")"

PI="${PI:-researchase@researchase.local}"
KEY="${KEY:-$HOME/.ssh/id_openclaw}"
DEST="research/resin-workshop-site/"

echo "==> syncing site/ to $PI:$DEST"
ssh -i "$KEY" "$PI" "mkdir -p ~/$DEST"
rsync -av --delete -e "ssh -i $KEY" site/ "$PI:$DEST"

echo "==> live at https://reasoning.school/resinlab/"
