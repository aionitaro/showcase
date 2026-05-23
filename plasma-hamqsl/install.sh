#!/usr/bin/env bash
# Instalare widget HF Propagation pentru KDE Plasma 5/6
set -e

WIDGET_DIR="$(cd "$(dirname "$0")" && pwd)"
WIDGET_ID="org.kde.plasma.hamqsl-propagation"

echo "==> Instalare $WIDGET_ID ..."

# Metoda 1: plasmapkg2 (Plasma 5) sau kpackagetool6 (Plasma 6)
if command -v kpackagetool6 &>/dev/null; then
    kpackagetool6 --type Plasma/Applet --install "$WIDGET_DIR" 2>/dev/null \
        || kpackagetool6 --type Plasma/Applet --upgrade "$WIDGET_DIR"
elif command -v plasmapkg2 &>/dev/null; then
    plasmapkg2 --type Plasma/Applet --install "$WIDGET_DIR" 2>/dev/null \
        || plasmapkg2 --type Plasma/Applet --upgrade "$WIDGET_DIR"
else
    # Fallback: copiere manuala
    DEST="$HOME/.local/share/plasma/plasmoids/$WIDGET_ID"
    mkdir -p "$DEST"
    cp -r "$WIDGET_DIR/metadata.json" "$WIDGET_DIR/contents" "$DEST/"
    echo "   Copiat in $DEST"
fi

echo "==> Gata! Reporneste plasma sau:"
echo "    kquitapp6 plasmashell && kstart plasmashell"
echo ""
echo "   Adauga widgetul: clic dreapta pe desktop -> Adauga widget -> cauta 'HF Propagation'"
