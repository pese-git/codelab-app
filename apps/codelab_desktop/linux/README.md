# Сборка и дистрибуция Flutter-приложения для Linux

Документация описывает подготовку системного окружения, настройку проекта, команды Melos и способы упаковки релиза для прямой дистрибуции (`.tar.gz` и `.deb`).

> **Важно:** Сборка Linux-версии выполняется только на ОС Linux (локально, в WSL2, Docker или в CI-раннере `ubuntu-latest`). Кросс-компиляция с macOS или Windows не поддерживается.

---

## 1. Требования к окружению сборки

Перед первой сборкой на Ubuntu / Debian необходимо установить компилятор C++, CMake и заголовочные файлы GTK 3:

```bash
sudo apt-get update && sudo apt-get install -y \
  clang cmake git ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libstdc++-12-dev
```

*(Опционально: если в проекте используются плагины хранения секретов или системного трея, например `flutter_secure_storage`, дополнительно установите `libsecret-1-dev` и `libjsoncpp-dev`).*

### Проверка окружения
```bash
flutter doctor -v
```
Убедитесь, что пункт **Linux toolchain - develop for Linux desktop** отмечен галочкой `[✓]`.

---

## 2. Настройка метаданных и иконки приложения

### Имя бинарника и App ID (`linux/CMakeLists.txt`)
Откройте `apps/codelab_desktop/linux/CMakeLists.txt` и проверьте идентификатор приложения и имя исполняемого файла:

```cmake
set(BINARY_NAME "codelab_app")
set(APPLICATION_ID "com.openidealab.codelab")
```

### Заголовок окна (`linux/my_application.cc`)
Убедитесь, что заголовок главного GTK-окна задан корректно:
```cpp
gtk_window_set_title(window, "CodeLab");
```

---

## 3. Скрипты сборки в Melos

Добавьте задачи сборки и упаковки в корневой `pubspec.yaml` вашего монорепозитория:

```yaml
melos:
  scripts:
    build:linux:
      description: Сборка Linux release бандла
      run: >
        melos exec --scope="codelab_desktop" --
        flutter build linux --release

    build:linux:tar:
      description: Сборка Linux release и упаковка в архив .tar.gz
      run: >
        melos exec --scope="codelab_desktop" --
        sh -c '
          flutter build linux --release &&
          mkdir -p build/linux/dist &&
          rm -f build/linux/dist/codelab_app-linux-x64.tar.gz &&
          tar -czf build/linux/dist/codelab_app-linux-x64.tar.gz -C build/linux/x64/release/bundle .
        '
```

*(Если сборка выполняется на ARM64-устройстве, путь к бандлу будет `build/linux/arm64/release/bundle`).*

### Артефакты сборки
* **Распакованный бандл:** `apps/codelab_desktop/build/linux/x64/release/bundle/`
  > Приложение запускается **только в комплекте с соседними директориями `lib/` и `data/`** (они содержат `libflutter_linux_gtk.so`, нативные библиотеки плагинов и ассеты). Отдельно скопированный бинарник `codelab_app` не запустится.
* **Портативный архив:** `apps/codelab_desktop/build/linux/dist/codelab_app-linux-x64.tar.gz`

---

## 4. Упаковка в `.deb` пакет (для Ubuntu / Debian / Linux Mint)

Чтобы пользователи могли установить приложение через `sudo apt install ./codelab.deb` с созданием ярлыка в меню приложений, соберите `.deb` поверх готового бандла:

### Шаг 1. Подготовьте структуру пакета и иконку
Положите PNG-иконку приложения (`512x512` или `256x256`) в `linux/packaging/icon.png` и выполните скрипт упаковки (можно добавить как задачу `build:linux:deb` в Melos):

```bash
#!/usr/bin/env bash
set -e

APP_NAME="codelab-app"
BINARY_NAME="codelab_app"
VERSION="0.1.0"
ARCH="amd64"
PKG_DIR="build/linux/deb/\${APP_NAME}_\({VERSION}_\){ARCH}"

rm -rf "\$PKG_DIR"
mkdir -p "\$PKG_DIR/DEBIAN"
mkdir -p "\(PKG_DIR/opt/\)APP_NAME"
mkdir -p "\$PKG_DIR/usr/bin"
mkdir -p "\$PKG_DIR/usr/share/applications"
mkdir -p "\$PKG_DIR/usr/share/icons/hicolor/256x256/apps"

# 1. Копируем собранный Flutter-бандл
cp -r build/linux/x64/release/bundle/* "\(PKG_DIR/opt/\)APP_NAME/"

# 2. Создаём симлинк для запуска из терминала
ln -s "/opt/\(APP_NAME/\)BINARY_NAME" "\(PKG_DIR/usr/bin/\)BINARY_NAME"

# 3. Копируем иконку и .desktop файл
cp linux/packaging/icon.png "\(PKG_DIR/usr/share/icons/hicolor/256x256/apps/\)APP_NAME.png"

cat <<EOF > "\(PKG_DIR/usr/share/applications/\)APP_NAME.desktop"
[Desktop Entry]
Name=CodeLab
Comment=CodeLab Desktop Application
Exec=/opt/\(APP_NAME/\)BINARY_NAME
Icon=\$APP_NAME
Terminal=false
Type=Application
Categories=Development;Utility;
EOF

# 4. Файл метаданных пакета
cat <<EOF > "\$PKG_DIR/DEBIAN/control"
Package: \$APP_NAME
Version: \$VERSION
Section: devel
Priority: optional
Architecture: \$ARCH
Depends: libgtk-3-0, liblzma5
Maintainer: OpenIdeaLab <support@openidealab.com>
Description: CodeLab Desktop Application
EOF

# 5. Собираем .deb
mkdir -p build/linux/dist
dpkg-deb --build --root-owner-group "\(PKG_DIR" "build/linux/dist/\){APP_NAME}_\({VERSION}_\){ARCH}.deb"
```

---

## 5. Особенности рантайма Linux

* **Динамические переменные окружения (`.env`):**
  На Linux `getApplicationSupportDirectory()` из пакета `path_provider` указывает в директорию по стандарту XDG:
  `~/.local/share/com.openidealab.codelab/` (или `~/.local/share/codelab_app/`).
  Внешний файл `.env` можно размещать в этой папке для динамической подгрузки при старте приложения.
* **Совместимость со старыми версиями Ubuntu / Debian:**
  Скомпилированный бинарник привязывается к версии `glibc` той ОС, на которой проводилась сборка. Чтобы `.tar.gz` и `.deb` запускались у большинства пользователей, собирайте релиз на **Ubuntu 22.04 LTS** (а не на самой свежей версии), так как обратная совместимость `glibc` работает только от старых версий к новым.
