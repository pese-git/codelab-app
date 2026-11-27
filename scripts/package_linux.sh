#!/usr/bin/env bash
set -euo pipefail

APP_NAME="codelab_desktop"
PKG_NAME="codelab-app"
VERSION="1.0.0"

# Определяем архитектуру для путей Flutter и имён пакетов
UNAME_ARCH=$(uname -m)
if [ "$UNAME_ARCH" = "aarch64" ]; then
  FLUTTER_ARCH="arm64"
  DEB_ARCH="arm64"
else
  FLUTTER_ARCH="x64"
  DEB_ARCH="amd64"
fi

BUNDLE_DIR="build/linux/${FLUTTER_ARCH}/release/bundle"
OUT_DIR="build/linux/packages"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# 1. Сборка tar.gz
tar -czf "${OUT_DIR}/${PKG_NAME}-linux-${UNAME_ARCH}.tar.gz" -C "$BUNDLE_DIR" .

# 2. Сборка .deb
DEB_DIR="${OUT_DIR}/deb_root"
mkdir -p "${DEB_DIR}/DEBIAN" "${DEB_DIR}/opt/${APP_NAME}" "${DEB_DIR}/usr/local/bin" "${DEB_DIR}/usr/share/applications"
cp -r "${BUNDLE_DIR}/"* "${DEB_DIR}/opt/${APP_NAME}/"
ln -s "/opt/${APP_NAME}/${APP_NAME}" "${DEB_DIR}/usr/local/bin/${APP_NAME}"

cat << CONTROL > "${DEB_DIR}/DEBIAN/control"
Package: ${PKG_NAME}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${DEB_ARCH}
Depends: libgtk-3-0, libblkid1, liblzma5
Maintainer: Developer <dev@example.com>
Description: Codelab Desktop Application
CONTROL

cat << DESKTOP > "${DEB_DIR}/usr/share/applications/${PKG_NAME}.desktop"
[Desktop Entry]
Name=Codelab App
Exec=/opt/${APP_NAME}/${APP_NAME}
Type=Application
Categories=Development;Utility;
Terminal=false
DESKTOP

dpkg-deb --build --root-owner-group "$DEB_DIR" "${OUT_DIR}/${PKG_NAME}_${VERSION}_${DEB_ARCH}.deb"
rm -rf "$DEB_DIR"

# 3. Сборка .AppImage (если установлен appimagetool в PATH или в ~/bin)
if command -v appimagetool >/dev/null 2>&1; then
  APPDIR="${OUT_DIR}/AppDir"
  mkdir -p "${APPDIR}/usr/bin"
  cp -r "${BUNDLE_DIR}/"* "${APPDIR}/usr/bin/"

  cat << APPRUN > "${APPDIR}/AppRun"
#!/bin/sh
HERE="\$(dirname "\$(readlink -f "\${0}")")"
exec "\${HERE}/usr/bin/${APP_NAME}" "\$@"
APPRUN
  chmod +x "${APPDIR}/AppRun"

  cat << DESKTOP > "${APPDIR}/${PKG_NAME}.desktop"
[Desktop Entry]
Name=Codelab App
Exec=${APP_NAME}
Icon=${PKG_NAME}
Type=Application
Categories=Development;
DESKTOP

  # Берём первую найденную PNG-иконку из проекта или генерируем валидный 1x1 PNG
  ICON_SRC=$(find . -name "*.png" | head -n 1 || true)
  if [ -n "$ICON_SRC" ]; then
    cp "$ICON_SRC" "${APPDIR}/${PKG_NAME}.png"
  else
    python3 -c 'import base64; open("'"${APPDIR}/${PKG_NAME}.png"'","wb").write(base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="))'
  fi

  ARCH="$UNAME_ARCH" appimagetool --appimage-extract-and-run "$APPDIR" "${OUT_DIR}/${PKG_NAME}-${VERSION}-${UNAME_ARCH}.AppImage"
  rm -rf "$APPDIR"
else
  echo "WARNING: appimagetool не найден в PATH, шаг .AppImage пропущен."
fi

echo "Готовые пакеты лежат в: $(pwd)/${OUT_DIR}"
