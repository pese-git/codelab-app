# Сборка проекта под Windows

Инструкция по настройке окружения и сборке десктопного приложения (`codelab_desktop`), CLI-клиента (`codelab`), агента (`codelab-agent`) и установщика `.msix` на Windows (x64 / ARM64).

---

## 1. Предварительные требования

### 1.1. Flutter и FVM
Убедитесь, что установлен **FVM** и активирована версия Flutter, указанная в проекте (например, `3.47.0` или выше согласно `pubspec.yaml`):

```powershell
fvm install
fvm flutter --version
```

### 1.2. Visual Studio / Build Tools (C++ и Windows SDK)
Для компиляции нативной части Flutter под Windows необходимы инструменты сборки C++:

1. Установите **Visual Studio 2026** (Community или Build Tools).
2. В **Visual Studio Installer** выберите рабочую нагрузку **«Разработка классических приложений на C++» (Desktop development with C++)** и отметьте в правой панели:
   - **MSVC — средства сборки C++ (x64/x86 и/или ARM64)**
   - **Пакет SDK для Windows 11 (Windows 11 SDK)**
   - **Средства C++ CMake для Windows (C++ CMake tools for Windows)**
3. Дождитесь полного завершения установки (100%) и перезапустите терминал.

### 1.3. Проверка окружения
Выполните из корня репозитория:

```powershell
fvm flutter doctor
```

Убедитесь, что пункты `[√] Flutter`, `[√] Windows Version` и `[√] Visual Studio - develop Windows apps` отмечены зелёной галочкой (ошибку `Android toolchain` можно игнорировать, если вы собираете только под Windows).

---

## 2. Подготовка зависимостей

Выполните инициализацию монорепозитория из корня проекта:

```powershell
fvm dart pub get
fvm dart run melos bootstrap
```

---

## 3. Сборка CLI и агента (`codelab.exe` и `codelab-agent.exe`)

Сборка бинарных файлов выполняется через кроссплатформенный скрипт `scripts/build_bin.dart`, который автоматически создаёт директорию `build/bin` и добавляет расширение `.exe` на Windows.

```powershell
# Сборка терминального клиента
fvm dart run melos run build:cli

# Сборка агента
fvm dart run melos run build:agent
```

**Результат сборки:**
- `build\bin\codelab.exe`
- `build\bin\codelab-agent.exe`

---

## 4. Сборка десктопного приложения (`codelab_desktop.exe`)

Для сборки релизной версии Windows-приложения выполните:

```powershell
fvm dart run melos run build:windows
```

**Результат сборки:**
- `apps\codelab_desktop\build\windows\x64\runner\Release\codelab_desktop.exe` *(или `arm64\runner\Release\` на ARM-устройствах)*

> **Примечание:** Если при пересборке после обновления SDK возникают ошибки `C1083` с отсутствующими файлами в `windows\flutter\ephemeral\`, выполните очистку:
> ```powershell
> cd apps\codelab_desktop
> fvm flutter clean
> Remove-Item -Recurse -Force -ErrorAction SilentlyContinue windows\flutter\ephemeral
> fvm flutter pub get
> cd ..\..
> ```

---

## 5. Сборка и установка MSIX-пакета

### 5.1. Сборка `.msix`
Убедитесь, что в `apps/codelab_desktop/pubspec.yaml` настроен блок `msix_config`:

```yaml
msix_config:
  display_name: CodeLab Desktop
  publisher_display_name: CodeLab
  identity_name: com.example.codelabDesktop
  msix_version: 0.1.0.1
  sign_msix: true
  install_certificate: true
```

Запустите сборку установщика:

```powershell
fvm dart run melos run build:windows:msix
```

При первом запуске подтвердите установку тестового сертификата (`y`), когда появится запрос `Do you want to install the certificate: "test_certificate.pfx" ? (y/N)`.

**Результат сборки:**
- `apps\codelab_desktop\build\windows\x64\runner\Release\codelab_desktop.msix`

### 5.2. Установка `.msix`
После сборки пакет можно установить двойным кликом в Проводнике или через PowerShell:

```powershell
Add-AppxPackage .\apps\codelab_desktop\build\windows\x64\runner\Release\codelab_desktop.msix
```

### 5.3. Устранение ошибок подписи при локальной установке
Если при установке `.msix` возникает ошибка `0x800B010A` (сертификат не проверен) или `0x800B0100` (пакет не подписан), выполните в **PowerShell от имени администратора** однократную настройку тестового сертификата:

```powershell
\$msix = Resolve-Path ".\apps\codelab_desktop\build\windows\x64\runner\Release\codelab_desktop.msix"

# 1. Читаем Publisher из манифеста пакета
Add-Type -AssemblyName System.IO.Compression.FileSystem
\(zip = [System.IO.Compression.ZipFile]::OpenRead(\)msix)
\(manifest = ([System.IO.StreamReader](\)zip.GetEntry("AppxManifest.xml").Open())).ReadToEnd()
\$zip.Dispose()
\(publisher = ([xml]\)manifest).Package.Identity.Publisher

# 2. Создаём сертификат и добавляем в доверенные корневые центры
cert = New-SelfSignedCertificate -Type Custom -Subject publisher -KeyUsage DigitalSignature `
  -FriendlyName "Codelab MSIX Cert" -CertStoreLocation "Cert:\CurrentUser\My" `
  -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}")
Export-Certificate -Cert cert -FilePath "env:TEMP\codelab_msix.cer"
Import-Certificate -FilePath "\$env:TEMP\codelab_msix.cer" -CertStoreLocation Cert:\LocalMachine\Root

# 3. Подписываем пакет через signtool.exe и устанавливаем
signtool = Get-ChildItem "{env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe" | Sort-Object FullName -Descending | Select-Object -First 1
& \$signtool.FullName sign /fd SHA256 /sha1 cert.Thumbprint msix
Add-AppxPackage \$msix
```
