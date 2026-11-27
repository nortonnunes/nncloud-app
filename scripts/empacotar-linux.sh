#!/usr/bin/env bash
# Gera o NN Unifi (até a 1.0.3: APP Operação UNIFI; até a 1.0.2: Conecta Callcenter) para Linux. Rodar NUMA MÁQUINA LINUX (o Flutter não
# compila para Linux a partir do macOS/Windows) — no GitHub, `.github/workflows/linux.yml`.
#
# Pré-requisitos (Ubuntu/Debian):
#   sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev \
#        libsecret-1-dev libjsoncpp-dev libayatana-appindicator3-dev libgstreamer1.0-dev \
#        libgstreamer-plugins-base1.0-dev dpkg-dev
#   + Flutter 3.41.6 no PATH
#
#   CALLAPP_API=https://api.nnconecta.com bash scripts/empacotar-linux.sh
#
# Sai em build/instaladores/: conecta-callcenter_<versão>_<arq>.deb (Ubuntu, Debian,
# Mint…), que instala em /opt/conecta-callcenter com atalho no menu e inicia com a sessão.
# ⚠️ Compilado no Ubuntu 22.04, roda no 22.04+ e Debian 12+ (glibc da máquina de build).
# ⚠️ O ícone ao lado do relógio precisa do AppIndicator (no GNOME, a extensão "AppIndicator").
set -euo pipefail
cd "$(dirname "$0")/.."

ID="br.com.nortonnunes.callcenter"
versao="$(grep -E '^version:' pubspec.yaml | sed -E 's/version:[[:space:]]*//; s/\+.*//' | tr -d '[:space:]')"
case "$(uname -m)" in
  x86_64) arq_flutter=x64; arq_deb=amd64 ;;
  aarch64|arm64) arq_flutter=arm64; arq_deb=arm64 ;;
  *) echo "Arquitetura $(uname -m) não suportada." >&2; exit 1 ;;
esac
echo "NN Unifi $versao ($arq_deb)"

DEFINES=()
[ -n "${CALLAPP_API:-}" ] && DEFINES+=("--dart-define=CALLAPP_API=$CALLAPP_API")
flutter build linux --release "${DEFINES[@]+"${DEFINES[@]}"}"
bundle="build/linux/$arq_flutter/release/bundle"
[ -x "$bundle/conecta-callcenter" ] || { echo "O build não gerou $bundle/conecta-callcenter." >&2; exit 1; }

saida="build/instaladores"
rm -rf "$saida" build/pacote-linux
mkdir -p "$saida"

desktop() {   # $1 = comando do Exec
  cat <<DESK
[Desktop Entry]
Type=Application
Name=NN Unifi
GenericName=Comunicação interna
Comment=Conversas, comunicados, NN News e avisos do NN Conecta
Exec=$1
Icon=$ID
Terminal=false
Categories=Network;Chat;Office;
StartupWMClass=$ID
Keywords=nnconecta;callcenter;conversas;chat;
DESK
}

raiz="build/pacote-linux/deb"
mkdir -p "$raiz/DEBIAN" "$raiz/opt/conecta-callcenter" "$raiz/usr/bin" "$raiz/usr/share/applications" "$raiz/etc/xdg/autostart"
cp -a "$bundle/." "$raiz/opt/conecta-callcenter/"
ln -s /opt/conecta-callcenter/conecta-callcenter "$raiz/usr/bin/conecta-callcenter"
desktop "/opt/conecta-callcenter/conecta-callcenter" > "$raiz/usr/share/applications/$ID.desktop"
# Inicia com a sessão, escondido na bandeja (o comunicado só chega com o app aberto).
desktop "/opt/conecta-callcenter/conecta-callcenter --oculto" > "$raiz/etc/xdg/autostart/$ID.desktop"
for t in 128 256 512; do
  mkdir -p "$raiz/usr/share/icons/hicolor/${t}x${t}/apps"
  cp "linux/pacote/conecta-callcenter-$t.png" "$raiz/usr/share/icons/hicolor/${t}x${t}/apps/$ID.png"
done
tamanho_kb="$(du -sk "$raiz/opt" "$raiz/usr" | awk '{s+=$1} END {print s}')"
cat > "$raiz/DEBIAN/control" <<CTRL
Package: conecta-callcenter
Version: $versao
Section: net
Priority: optional
Architecture: $arq_deb
Maintainer: ${MANTENEDOR:-Norton Nunes <ti@nortonnunes.com.br>}
Installed-Size: $tamanho_kb
Depends: libgtk-3-0, libsecret-1-0, libjsoncpp25 | libjsoncpp24 | libjsoncpp1, libayatana-appindicator3-1 | libappindicator3-1, libgstreamer1.0-0, libgstreamer-plugins-base1.0-0, gstreamer1.0-plugins-good, zenity | kdialog
Recommends: gnome-keyring | kwalletmanager, xdg-utils, gstreamer1.0-libav
Homepage: https://nnconecta.com
Description: NN Unifi — o app do Tele Atendimento do NN Conecta
 Conversas completas, comunicados com alerta, NN News, quadro de avisos e
 aniversariantes, sempre em tela cheia e com o ícone ao lado do relógio.
CTRL
cat > "$raiz/DEBIAN/postinst" <<'POST'
#!/bin/sh
set -e
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -f /usr/share/icons/hicolor || true
exit 0
POST
cp "$raiz/DEBIAN/postinst" "$raiz/DEBIAN/postrm"
chmod 0755 "$raiz/DEBIAN/postinst" "$raiz/DEBIAN/postrm"
find "$raiz/opt" "$raiz/usr" "$raiz/etc" -type d -exec chmod 0755 {} +
dpkg-deb --root-owner-group --build "$raiz" "$saida/conecta-callcenter_${versao}_${arq_deb}.deb"

echo
ls -lh "$saida"
sha256sum "$saida"/*.deb
echo "Pronto - publique o .deb em Sistema > NN Unifi > Aplicativo (Linux)."
