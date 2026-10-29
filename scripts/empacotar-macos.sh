#!/bin/bash
# Gera o instalador do NN Cloud para macOS: build universal, assinatura com o
# Developer ID deste Mac (runtime endurecido), DMG e — se as credenciais da
# Apple estiverem guardadas no chaveiro — notarização.
#
#   scripts/empacotar-macos.sh                 # assina com o 1º "Developer ID Application" do chaveiro
#   IDENTIDADE="Developer ID Application: …" scripts/empacotar-macos.sh
#   PERFIL_NOTARIZACAO=NNCLOUD scripts/empacotar-macos.sh
#
# Notarizar (uma vez por Mac, a senha fica no chaveiro e o script nunca a vê):
#   xcrun notarytool store-credentials NNCLOUD --apple-id <seu e-mail> --team-id <time>
#
# ⚠️ Com o runtime endurecido, TODO framework de dentro do app precisa da mesma
# assinatura do app — senão o macOS recusa carregar ("different Team IDs").
# Por isso a assinatura é feita de dentro para fora, e o `codesign --deep` NÃO
# é usado (a Apple desaconselha: ele não aplica os direitos certos a cada parte).
set -euo pipefail

cd "$(dirname "$0")/.."
VERSAO=$(grep '^version:' pubspec.yaml | sed 's/version: //; s/+.*//')
APP="build/macos/Build/Products/Release/NN Cloud.app"
SAIDA="build/instaladores"
DMG="$SAIDA/NN-Cloud-$VERSAO.dmg"
DIREITOS="macos/Runner/Release.entitlements"
PERFIL="${PERFIL_NOTARIZACAO:-NNCLOUD}"

IDENTIDADE="${IDENTIDADE:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
if [ -z "$IDENTIDADE" ]; then
  echo "Nenhum certificado 'Developer ID Application' no chaveiro deste Mac." >&2
  exit 1
fi
echo "Assinando com: $IDENTIDADE"

flutter build macos --release ${DART_DEFINES:-}

assinar() { codesign --force --timestamp --options runtime --sign "$IDENTIDADE" "$@"; }

# 1. Bibliotecas soltas e frameworks (de dentro para fora).
find "$APP/Contents/Frameworks" -type f \( -name "*.dylib" -o -name "*.so" \) -print0 | while IFS= read -r -d '' f; do assinar "$f"; done
for fw in "$APP/Contents/Frameworks/"*.framework; do
  assinar "$fw"
done
# 2. A extensão do "NN Cloud" no Finder (File Provider), com os direitos DELA
#    (sandbox, rede e o grupo do time). Antes do app: o selo do app cobre a extensão.
for ext in "$APP/Contents/PlugIns/"*.appex; do
  [ -e "$ext" ] || continue
  assinar --entitlements "macos/NNCloudFP/NNCloudFP.entitlements" "$ext"
done
# 3. O app, com os direitos do Release.
assinar --entitlements "$DIREITOS" "$APP"

codesign --verify --strict --deep --verbose=2 "$APP"
echo "Assinatura conferida."
if [ "${SEM_DMG:-0}" = "1" ]; then
  echo "SEM_DMG=1: app assinado em $APP (sem DMG)."
  exit 0
fi

# 4. DMG (arrastar para Aplicativos).
mkdir -p "$SAIDA"
TMP=$(mktemp -d)
cp -R "$APP" "$TMP/"
ln -s /Applications "$TMP/Aplicativos"
rm -f "$DMG"
hdiutil create -volname "NN Cloud $VERSAO" -srcfolder "$TMP" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$TMP"
codesign --force --timestamp --sign "$IDENTIDADE" "$DMG"

# 5. Notarização (opcional: só se o perfil existir no chaveiro).
if xcrun notarytool history --keychain-profile "$PERFIL" >/dev/null 2>&1; then
  echo "Enviando para a notarização da Apple (perfil $PERFIL)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$PERFIL" --wait
  xcrun stapler staple "$DMG"
  spctl -a -t open --context context:primary-signature -v "$DMG"
else
  echo "⚠️  Sem o perfil de notarização '$PERFIL': o DMG está assinado, mas NÃO notarizado."
  echo "    Outros Macs vão avisar que o desenvolvedor não pôde ser verificado."
  echo "    Rode uma vez: xcrun notarytool store-credentials $PERFIL --apple-id <e-mail> --team-id <time>"
fi

shasum -a 256 "$DMG"
echo "Pronto: $DMG"
