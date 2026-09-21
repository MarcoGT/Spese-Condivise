#!/bin/bash
# Cattura gli screenshot grezzi per l'App Store con i dati demo (build Debug,
# store temporaneo, niente iCloud). Uscita: asc/screenshots/raw/<lingua>/.
# Poi: python3 tools/screenshots/compose.py
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DD="$HOME/Library/Caches/SpeseCondivise-screenshots"
BID="com.marcolagana.Spese-Condivise"
# 6,9": l'unica misura iPhone che App Store Connect richiede, le altre le scala lui.
DEVICE="${DEVICE:-iPhone 17 Pro Max}"

# Simulatore dedicato e senza Apple ID: su quelli di sviluppo compaiono
# popup di sistema ("Verifica di Apple Account") con l'email dell'account.
NAME="SpeseCondivise Screenshots"
SIM=$(xcrun simctl list devices available -j | python3 -c "
import json,sys
d=json.load(sys.stdin)['devices']
print(next((x['udid'] for r in d.values() for x in r if x['name']=='$NAME'), ''))")
if [ -z "$SIM" ]; then
  SIM=$(xcrun simctl create "$NAME" "$DEVICE")
  echo "▸ creato simulatore dedicato $SIM"
fi

echo "▸ build per $DEVICE"
xcodebuild -project "$ROOT/Spese Condivise.xcodeproj" -scheme "Spese Condivise" \
  -destination "id=$SIM" -configuration Debug -derivedDataPath "$DD" build \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
APP="$DD/Build/Products/Debug-iphonesimulator/Spese Condivise.app"

xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null
xcrun simctl status_bar "$SIM" override --time "9:41" --dataNetwork wifi --wifiMode active \
  --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl uninstall "$SIM" "$BID" 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"

shoot() { # lingua, nome file, schermata ("" = lista)
  local lang=$1 name=$2 screen=$3 args
  if [ "$lang" = it ]; then args=(-currentUserPersonName Marco -AppleLanguages "(it)" -AppleLocale it_IT)
  else args=(-currentUserPersonName Alex -AppleLanguages "(en)" -AppleLocale en_US); fi
  [ -n "$screen" ] && args+=(-demoScreen "$screen")
  xcrun simctl terminate "$SIM" "$BID" 2>/dev/null || true
  xcrun simctl launch "$SIM" "$BID" -demoData -hasSeenOnboarding YES "${args[@]}" >/dev/null
  sleep 11
  mkdir -p "$ROOT/asc/screenshots/raw/$lang"
  xcrun simctl io "$SIM" screenshot "$ROOT/asc/screenshots/raw/$lang/$name.png" >/dev/null 2>&1
  echo "  $lang/$name"
}

# Il primo avvio dopo l'installazione è lento: uno a vuoto per scaldare.
xcrun simctl launch "$SIM" "$BID" -demoData -hasSeenOnboarding YES >/dev/null; sleep 10

for lang in it en; do
  shoot $lang 1_list   ""
  shoot $lang 2_detail detail
  shoot $lang 3_add    add
  shoot $lang 4_stats  stats
done
xcrun simctl terminate "$SIM" "$BID" 2>/dev/null || true
echo "▸ fatto: asc/screenshots/raw/"
