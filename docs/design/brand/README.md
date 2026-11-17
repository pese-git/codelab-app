# Бренд CodeLab

Знак — колба (Lab) с промптом агента `>_` в жидкости (Code). Цвет — акцент Fluent `#005FB8` из макетов `docs/design/claude-design`, плашка — градиент `#1A7FE0 → #003E8A`.

| Файл | Что это |
|---|---|
| `codelab-glyph.svg` | исходник: знак без фона |
| `codelab-glyph-mono.svg` | исходник: одноцветный знак (промпт вырезан) для тематических иконок Android 13+ |
| `codelab-wordmark.svg` | исходник: надпись «CodeLab» линиями толщиной 30 со скруглёнными концами, как у колбы; без шрифта, поэтому не зависит от установленных шрифтов и их лицензий |
| `codelab-logo.svg`, `codelab-logo-dark.svg` | эталон: горизонтальный логотип для светлого и тёмного фона («Lab» — `#005FB8` и `#4CC2FF`), плюс PNG-превью |
| `launcher/*.svg` | эталон: каждый вариант иконки приложения по платформам (таблица ниже) |
| `codelab-icon-1024.png` | превью иконки macOS |

Эталоны генерируются из исходников (ниже) — правится только исходник, затем генератор.

## Иконки приложения

Платформенные иконки и эталоны бренда собирает один генератор из исходников `codelab-glyph*.svg` и `codelab-wordmark.svg`:

```bash
fvm dart run tool/brand/generate_app_icons.dart
```

Он пишет в `apps/codelab_desktop` только платформы, каталог которых уже есть, и пропускает остальные. Предпросмотр всех платформ — `--out <каталог>`, выбор — `--platforms macos,web`. Нужны `rsvg-convert` (librsvg) и `magick` (ImageMagick).

Все шесть платформ `apps/codelab_desktop` уже созданы и подключены. Для новой платформы — `fvm flutter create --platforms=<p> .` в `apps/codelab_desktop`, затем генератор, затем подключение по таблице.

| Платформа | Эталон `launcher/` | Что пишет генератор | Где подключено |
|---|---|---|---|
| macOS | `macos.svg` | `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_*.png` — плашка по сетке Apple | `Contents.json` шаблона |
| iOS | `ios.svg` | `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-*.png` — на весь квадрат, без альфа-канала | `Contents.json` шаблона |
| Android | `android-{foreground,background,monochrome,legacy,round,play-store}.svg` | `mipmap-*/ic_launcher{,_round,_foreground,_background,_monochrome}.png`, `mipmap-anydpi-v26/ic_launcher{,_round}.xml`, `play_store_512.png` | `android:icon` и `android:roundIcon` в `AndroidManifest.xml`; `play_store_512.png` загружается в Play Console и в сборку не входит |
| Windows | `windows.svg` | `windows/runner/resources/app_icon.ico` (16–256) | `IDI_APP_ICON` в `windows/runner/Runner.rc` |
| Linux | `linux.svg` | `linux/assets/icons/hicolor/<N>x<N>/apps/codelab.png`, `scalable/apps/codelab.svg` | `install(DIRECTORY …/assets/icons)` в `linux/CMakeLists.txt` кладёт их в `data/icons` бандла; окно берёт `256x256` в `linux/runner/my_application.cc`. Для пакета — `linux/packaging/com.example.codelab_desktop.desktop` (`Icon=codelab`), см. ниже |
| Web | `web-{icon,maskable,favicon}.svg` | `web/favicon.png`, `web/icons/Icon-{192,512}.png`, `Icon-maskable-{192,512}.png` | `web/index.html` и `web/manifest.json` (цвета `#005FB8`) |

## Пакеты Linux

Ярлык — `apps/codelab_desktop/linux/packaging/com.example.codelab_desktop.desktop`. Имя файла и `StartupWMClass` равны `APPLICATION_ID` из `linux/CMakeLists.txt`: по ним среда рабочего стола связывает окно с ярлыком и его иконкой. При смене `APPLICATION_ID` (сейчас шаблонный `com.example.*`) файл переименовывается вместе с ним.

Пакет ставит:

| Что | Куда |
|---|---|
| бандл `build/linux/x64/release/bundle/` | например, `/opt/codelab/`; `codelab_desktop` — в `PATH` (ссылка в `/usr/bin`), иначе поправить `Exec` |
| `linux/packaging/com.example.codelab_desktop.desktop` | `/usr/share/applications/` |
| `linux/assets/icons/hicolor/*` | `/usr/share/icons/hicolor/` (после установки — `gtk-update-icon-cache`) |

Особенности форматов:

* **flatpak** требует, чтобы иконка и ярлык назывались ID приложения: в манифесте модуля — `rename-icon: codelab` и `rename-desktop-file`, либо установка иконок сразу как `<app-id>.png`.
* **snap** берёт ярлык и иконку из `snap/gui/`: ярлык копируется туда как `<snap-name>.desktop` с `Icon=${SNAP}/meta/gui/<snap-name>.png`.
