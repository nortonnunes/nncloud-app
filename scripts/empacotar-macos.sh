#!/bin/bash
# Gera o instalador do Conecta Callcenter para macOS (Apple Silicon e Intel):
# build universal, assinatura com o Developer ID deste Mac (runtime endurecido),
# DMG e — se as credenciais da Apple estiverem no chaveiro — notarização.
#
#   CALLAPP_API=https://api.nnconecta.com scripts/empacotar-macos.sh
#   IDENTIDADE="Developer ID Application: …" scripts/empacotar-macos.sh
#   PERFIL_NOTARIZACAO=NNCLOUD scripts/empacotar-macos.sh
#
# ⚠️ CALLAPP_API é o endereço da API do NN Conecta que o app usa (só https).
#    Sem ele vale o padrão de lib/config.dart.
# ⚠️ A atualização automática só troca o app por uma versão assinada pelo MESMO
#    time (52YUD97UMR) e com o MESMO bundle id (br.com.nortonnunes.callcenter).
# ⚠️ Com o runtime endurecido, TODO framework de dentro do app precisa da mesma
#    assinatura — por isso a assinatura é de dentro para fora, sem `--deep`.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSAO=$(grep '^version:' pubspec.yaml | sed 's/version: //; s/+.*//')
APP="build/macos/Build/Products/Release/Conecta Callcenter.app"
SAIDA="build/instaladores"
DMG="$SAIDA/Conecta-Callcenter-$VERSAO.dmg"
DIREITOS="macos/Runner/Release.entitlements"
PERFIL="${PERFIL_NOTARIZACAO:-NNCLOUD}"

IDENTIDADE="${IDENTIDADE:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
if [ -z "$IDENTIDADE" ]; then
  echo "Nenhum certificado 'Developer ID Application' no chaveiro deste Mac." >&2
  exit 1
fi
echo "Assinando com: $IDENTIDADE"

DEFINES=()
[ -n "${CALLAPP_API:-}" ] && DEFINES+=("--dart-define=CALLAPP_API=$CALLAPP_API")
flutter build macos --release "${DEFINES[@]+"${DEFINES[@]}"}"

assinar() { codesign --force --timestamp --options runtime --sign "$IDENTIDADE" "$@"; }

# 1. Bibliotecas soltas e frameworks (de dentro para fora).
find "$APP/Contents/Frameworks" -type f \( -name "*.dylib" -o -name "*.so" \) -print0 | while IFS= read -r -d '' f; do assinar "$f"; done
for fw in "$APP/Contents/Frameworks/"*.framework; do
  assinar "$fw"
done
# 2. O app, com os direitos do Release.
assinar --entitlements "$DIREITOS" "$APP"

codesign --verify --strict --deep --verbose=2 "$APP"
echo "Assinatura conferida."
if [ "${SEM_DMG:-0}" = "1" ]; then
  echo "SEM_DMG=1: app assinado em $APP (sem DMG)."
  exit 0
fi

# 3. DMG (arrastar para Aplicativos).
mkdir -p "$SAIDA"
TMP=$(mktemp -d)
cp -R "$APP" "$TMP/"
ln -s /Applications "$TMP/Aplicativos"
rm -f "$DMG"
hdiutil create -volname "Conecta Callcenter $VERSAO" -srcfolder "$TMP" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$TMP"
codesign --force --timestamp --sign "$IDENTIDADE" "$DMG"

# 4. Notarização (opcional: só se o perfil existir no chaveiro).
if xcrun notarytool history --keychain-profile "$PERFIL" >/dev/null 2>&1; then
  echo "Enviando para a notarização da Apple (perfil $PERFIL)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$PERFIL" --wait
  xcrun stapler staple "$DMG"
  spctl -a -t open --context context:primary-signature -v "$DMG"
else
  echo "⚠️  Sem o perfil de notarização '$PERFIL': o DMG está assinado, mas NÃO notarizado."
  echo "    Rode uma vez: xcrun notarytool store-credentials $PERFIL --apple-id <e-mail> --team-id 52YUD97UMR"
fi

shasum -a 256 "$DMG"
echo "Pronto: $DMG - publique em Sistema > App do Callcenter > Aplicativo (macOS)."
