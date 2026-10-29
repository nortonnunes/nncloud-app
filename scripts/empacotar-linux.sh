#!/usr/bin/env bash
# Gera o NN Cloud para Linux. Rodar NUMA MÁQUINA LINUX (o Flutter não compila
# para Linux a partir do macOS/Windows) — no GitHub, `.github/workflows/linux.yml`.
#
# Pré-requisitos (Ubuntu/Debian):
#   sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
#        libstdc++-12-dev libsecret-1-dev libjsoncpp-dev libayatana-appindicator3-dev dpkg-dev
#   + Flutter 3.41.6 no PATH (o mesmo do macOS e do Windows)
#
#   bash scripts/empacotar-linux.sh
#   (opcional) MANTENEDOR="Nome <email>" — o responsável que aparece no .deb
#
# Saem DOIS arquivos em build/instaladores/:
#   - nncloud_<versão>_<arq>.deb          Ubuntu, Debian, Mint, Pop!_OS…
#     (instala em /opt/nncloud, com atalho no menu de aplicativos)
#   - NN-Cloud-<versão>-linux-<arq>.tar.gz  as demais distribuições
#     (desempacotar e rodar ./instalar.sh — instala só para o usuário, sem sudo)
#
# ⚠️ O binário é compilado contra a glibc da máquina de build: compilado no
# Ubuntu 22.04, roda no 22.04+ e Debian 12+ (e equivalentes). Por isso o workflow
# usa o ubuntu-22.04, e não o "latest".
set -euo pipefail
cd "$(dirname "$0")/.."

ID="br.com.nortonnunes.nncloud"
versao="$(grep -E '^version:' pubspec.yaml | sed -E 's/version:[[:space:]]*//; s/\+.*//' | tr -d '[:space:]')"
case "$(uname -m)" in
  x86_64) arq_flutter=x64; arq_deb=amd64 ;;
  aarch64|arm64) arq_flutter=arm64; arq_deb=arm64 ;;
  *) echo "Arquitetura $(uname -m) não suportada." >&2; exit 1 ;;
esac
echo "NN Cloud $versao ($arq_deb)"

flutter build linux --release
bundle="build/linux/$arq_flutter/release/bundle"
[ -x "$bundle/nncloud" ] || { echo "O build não gerou $bundle/nncloud." >&2; exit 1; }

saida="build/instaladores"
rm -rf "$saida" build/pacote-linux
mkdir -p "$saida"

desktop() {   # $1 = comando do Exec
  cat <<EOF
[Desktop Entry]
Type=Application
Name=NN Cloud
GenericName=Sincronização de arquivos
Comment=Mantém pastas do computador sincronizadas com o NN Conecta
Exec=$1
Icon=$ID
Terminal=false
Categories=Network;FileTransfer;Utility;
StartupWMClass=$ID
Keywords=nnconecta;nuvem;sincronizar;drive;
EOF
}

# ------------------------------------------------------------------ .deb
raiz="build/pacote-linux/deb"
mkdir -p "$raiz/DEBIAN" "$raiz/opt/nncloud" "$raiz/usr/bin" "$raiz/usr/share/applications"
cp -a "$bundle/." "$raiz/opt/nncloud/"
# O Flutter acha os dados pelo caminho real do executável (/proc/self/exe): o link funciona.
ln -s /opt/nncloud/nncloud "$raiz/usr/bin/nncloud"
desktop "/opt/nncloud/nncloud" > "$raiz/usr/share/applications/$ID.desktop"
for t in 128 256 512; do
  mkdir -p "$raiz/usr/share/icons/hicolor/${t}x${t}/apps"
  cp "linux/pacote/nncloud-$t.png" "$raiz/usr/share/icons/hicolor/${t}x${t}/apps/$ID.png"
done
tamanho_kb="$(du -sk "$raiz/opt" "$raiz/usr" | awk '{s+=$1} END {print s}')"
cat > "$raiz/DEBIAN/control" <<EOF
Package: nncloud
Version: $versao
Section: net
Priority: optional
Architecture: $arq_deb
Maintainer: ${MANTENEDOR:-Norton Nunes <ti@nortonnunes.com.br>}
Installed-Size: $tamanho_kb
Depends: libgtk-3-0, libsecret-1-0, libjsoncpp25 | libjsoncpp24 | libjsoncpp1, libayatana-appindicator3-1 | libappindicator3-1
Recommends: gnome-keyring | kwalletmanager, xdg-utils
Homepage: https://nnconecta.com/cloud
Description: NN Cloud — sincronização de pastas com o NN Conecta
 Mantém pastas do computador iguais às do NN Cloud, nos dois sentidos.
 O que muda sem internet sobe quando a conexão voltar.
EOF
cat > "$raiz/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -f /usr/share/icons/hicolor || true
exit 0
EOF
cp "$raiz/DEBIAN/postinst" "$raiz/DEBIAN/postrm"
chmod 0755 "$raiz/DEBIAN/postinst" "$raiz/DEBIAN/postrm"
find "$raiz/opt" "$raiz/usr" -type d -exec chmod 0755 {} +
dpkg-deb --root-owner-group --build "$raiz" "$saida/nncloud_${versao}_${arq_deb}.deb"

# --------------------------------------------------------------- .tar.gz
pasta="build/pacote-linux/NN-Cloud-$versao"
mkdir -p "$pasta"
cp -a "$bundle" "$pasta/nncloud"
cp linux/pacote/nncloud-256.png "$pasta/$ID.png"
cat > "$pasta/instalar.sh" <<EOF
#!/usr/bin/env bash
# Instala o NN Cloud só para este usuário (sem sudo), em ~/.local/share/nncloud,
# com atalho no menu de aplicativos. Para tirar: ./instalar.sh --remover
set -euo pipefail
cd "\$(dirname "\$0")"
dados="\${XDG_DATA_HOME:-\$HOME/.local/share}"
destino="\$dados/nncloud"
atalho="\$dados/applications/$ID.desktop"
icone="\$dados/icons/hicolor/256x256/apps/$ID.png"
if [ "\${1:-}" = "--remover" ]; then
  rm -rf "\$destino" "\$atalho" "\$icone" "\${XDG_CONFIG_HOME:-\$HOME/.config}/autostart/$ID.desktop"
  echo "NN Cloud removido. (Os arquivos sincronizados e as configurações continuam no computador.)"
  exit 0
fi
pkill -x nncloud 2>/dev/null || true
rm -rf "\$destino"
mkdir -p "\$destino" "\$(dirname "\$atalho")" "\$(dirname "\$icone")"
cp -a nncloud/. "\$destino/"
cp "$ID.png" "\$icone"
cat > "\$atalho" <<DESK
$(desktop '"__DESTINO__/nncloud"')
DESK
sed -i "s#__DESTINO__#\$destino#" "\$atalho"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "\$dados/applications" || true
echo "NN Cloud $versao instalado. Abra pelo menu de aplicativos (ou rode \$destino/nncloud)."
EOF
chmod 0755 "$pasta/instalar.sh"
cat > "$pasta/LEIA-ME.txt" <<EOF
NN Cloud $versao para Linux

Instalar (só para você, sem sudo):   ./instalar.sh
Remover:                             ./instalar.sh --remover

Precisa de: GTK 3, libsecret (o chaveiro da sessão guarda o acesso) e, para o
ícone na barra, o suporte a AppIndicator (no GNOME, a extensão "AppIndicator").
No Ubuntu/Debian prefira o arquivo .deb.
EOF
tar -C build/pacote-linux -czf "$saida/NN-Cloud-$versao-linux-$arq_flutter.tar.gz" "NN-Cloud-$versao"

echo
ls -lh "$saida"
