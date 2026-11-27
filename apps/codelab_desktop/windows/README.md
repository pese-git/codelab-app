# Сборка и дистрибуция Flutter-приложения для Windows

Документация описывает требования к окружению, настройку конфигурации, команды Melos и способы упаковки релиза для прямой дистрибуции (`.zip` / `Setup.exe`) и публикации в Microsoft Store (`.msix`).

> **Важно:** Сборка Windows-версии выполняется только на ОС Windows (локально или в CI-раннере `windows-latest`). Кросс-компиляция с macOS или Linux не поддерживается.

---

## 1. Требования к окружению сборки

Перед первой сборкой на Windows-машине необходимо подготовить системные компоненты:

1. **Visual Studio 2022** (Community, Professional или Build Tools):
   * В установщике Visual Studio Installer отметьте рабочую нагрузку **«Разработка классических приложений на C++» (Desktop development with C++)**.
   * Убедитесь, что в составе выбраны: *MSVC v143 C++ x64/x86 build tools*, *Windows 10/11 SDK* и *C++ CMake tools for Windows*.
2. **Режим разработчика (Developer Mode):**
   * Откройте *Параметры Windows → Система → Для разработчиков* (или *Конфиденциальность и защита → Для разработчиков*) и включите **Режим разработчика** (необходимо для создания символических ссылок плагинами Flutter).
3. **Проверка окружения:**
   ```powershell
   flutter doctor -v
   ```
   Убедитесь, что пункт **Visual Studio - develop Windows apps** отмечен галочкой `[✓]`.

---

## 2. Настройка метаданных и иконки приложения

### Иконка приложения
Замените стандартную иконку Flutter на свою в формате `.ico` (должна содержать размеры от `16x16` до `256x256`):
* Путь: `windows/runner/resources/app_icon.ico`

### Метаданные исполняемого файла (`Runner.rc`)
Отредактируйте информацию о компании, названии продукта и копирайте в файле `windows/runner/Runner.rc`:

```rc
VALUE "CompanyName", "OpenIdeaLab" "\0"
VALUE "FileDescription", "CodeLab Desktop" "\0"
VALUE "ProductName", "CodeLab" "\0"
VALUE "LegalCopyright", "Copyright (C) 2026 OpenIdeaLab. All rights reserved." "\0"
```

### Имя итогового `.exe` файла
Задаётся в `windows/CMakeLists.txt` в переменной `BINARY_NAME`:
```cmake
set(BINARY_NAME "codelab_app")
```

---

## 3. Скрипты сборки в Melos

Добавьте команды сборки в корневой `pubspec.yaml` вашего монорепозитория:

```yaml
melos:
  scripts:
    build:windows:
      description: Сборка Windows release приложения (.exe и библиотеки)
      run: >
        melos exec --scope="codelab_desktop" --
        flutter build windows --release

    build:windows:zip:
      description: Сборка Windows release и упаковка в портативный ZIP-архив
      run: >
        melos exec --scope="codelab_desktop" --
        powershell -Command "
          flutter build windows --release;
          if (LASTEXITCODE -ne 0) exit LASTEXITCODE }
          New-Item -ItemType Directory -Force -Path build/windows/dist | Out-Null;
          Compress-Archive -Path build/windows/x64/runner/Release/* -DestinationPath build/windows/dist/codelab_app-windows-x64.zip -Force
        "

    build:windows:msix:
      description: Сборка Windows MSIX пакета для Microsoft Store или прямой установки
      run: >
        melos exec --scope="codelab_desktop" --
        dart run msix:create
```

### Артефакты сборки
* **Распакованный релиз:** `apps/codelab_desktop/build/windows/x64/runner/Release/`
  > Приложение запускается **только в комплекте со всеми соседними файлами** (`flutter_windows.dll`, `data/`, `.dll` плагинов и Microsoft Visual C++ Runtime). Отдельно скопированный `.exe` не запустится.
* **Портативный архив:** `apps/codelab_desktop/build/windows/dist/codelab_app-windows-x64.zip`

---

## 4. Упаковка для Microsoft Store (`.msix`)

Для публикации в Microsoft Store используется пакетный формат `.msix`.

### Шаг 1. Подключите пакет `msix`
В папке пакета `apps/codelab_desktop` выполните:
```powershell
flutter pub add --dev msix
```

### Шаг 2. Настройте `msix_config` в `apps/codelab_desktop/pubspec.yaml`
```yaml
msix_config:
  display_name: CodeLab
  publisher_display_name: OpenIdeaLab
  identity_name: OpenIdeaLab.CodeLab
  msix_version: 0.1.0.0 # строго 4 числа: X.Y.Z.0
  logo_path: windows/runner/resources/app_icon.ico
  capabilities: internetClient
  store: true # true — для Microsoft Store (подпись выполнит сам магазин при загрузке)
```

### Шаг 3. Соберите `.msix`
```powershell
melos run build:windows:msix
```
Готовый пакет появится в `apps/codelab_desktop/build/windows/x64/runner/Release/codelab_app.msix`.

---

## 5. Создание классического инсталлятора `Setup.exe` (Inno Setup)

Если для прямой дистрибуции с сайта нужен мастер установки с ярлыками и деинсталлятором:

1. Установите бесплатный компилятор **Inno Setup** (`winget install JRSoftware.InnoSetup`).
2. Создайте скрипт `windows/installer.iss`:

```iss
[Setup]
AppName=CodeLab
AppVersion=0.1.0
DefaultDirName={autopf}\CodeLab
DefaultGroupName=CodeLab
OutputDir=..\build\windows\dist
OutputBaseFilename=CodeLab-Setup-0.1.0
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\CodeLab"; Filename: "{app}\codelab_app.exe"
Name: "{autodesktop}\CodeLab"; Filename: "{app}\codelab_app.exe"

[Run]
Filename: "{app}\codelab_app.exe"; Description: "Запустить CodeLab"; Flags: nowait postinstall skipifsilent
```

3. Соберите инсталлятор:
```powershell
iscc windows\installer.iss
```

---

## 6. Особенности рантайма Windows

* **Динамические переменные окружения (`.env`):**
  На Windows `getApplicationSupportDirectory()` из пакета `path_provider` указывает в:
  `C:\Users\<Username>\AppData\Roaming\com.openidealab\codelab_app\`
  Кладите внешний `.env` файл в эту директорию — приложение сможет читать и обновлять его без прав администратора.
* **Предупреждение Windows SmartScreen:**
  При скачивании неподписанного `.exe` или `.zip` из интернета Windows Defender SmartScreen покажет предупреждение *«Система Windows защитила ваш компьютер»*. Для его устранения при прямой дистрибуции (вне Microsoft Store) бинарник и инсталлятор подписываются сертификатом **Code Signing** (или через **Azure Trusted Signing**).
