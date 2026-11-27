# Конфигурация подписи, прав доступа и сборки Apple (iOS и macOS)

Документация описывает назначение и ключевые флаги конфигурационных файлов `*.entitlements`, `Info.plist` и `ExportOptions-AppStore.plist` для сборки и публикации Flutter-приложения в App Store (iOS / macOS) и прямого распространения (`.dmg`).

---

## 1. Файлы прав доступа (`*.entitlements`)

Файлы прав доступа определяют возможности песочницы (App Sandbox) и разрешения на уровне ядра ОС. Они вшиваются в цифровую подпись бинарника на этапе компиляции.

* **Расположение в проекте:**
  * `macos/Runner/DebugProfile.entitlements` — для сборок `Debug` и `Profile`.
  * `macos/Runner/Release.entitlements` — для релизных сборок (`Release` / App Store).
  * `ios/Runner/Runner.entitlements` — для iOS (создаётся при добавлении Capabilities в Xcode).

### Флаги безопасности и сети (macOS)

| Ключ | Тип | Обязательность | Описание |
| :--- | :--- | :--- | :--- |
| `com.apple.security.app-sandbox` | `Boolean` | **Обязателен для Mac App Store** (`true`) | Включает изоляцию приложения в контейнере `~/Library/Containers/<bundle-id>/`. Для прямого распространения через `.dmg` можно установить `false`. |
| `com.apple.security.cs.allow-jit` | `Boolean` | Только для `Debug` / `Profile` | Разрешает JIT-компиляцию для работы Dart VM в режиме отладки. В `Release` не требуется. |
| `com.apple.security.network.client` | `Boolean` | При работе с сетью | Разрешает **исходящие** сетевые подключения (HTTP/HTTPS, WebSockets, API). Без этого флага сеть в macOS Sandbox заблокирована. |
| `com.apple.security.network.server` | `Boolean` | Опционально | Разрешает **входящие** сетевые подключения (если приложение поднимает локальный HTTP/TCP-сервер). |

### Флаги доступа к файловой системе в песочнице (macOS)

| Ключ | Тип | Описание |
| :--- | :--- | :--- |
| `com.apple.security.files.user-selected.read-only` | `Boolean` | Доступ на чтение к файлам и директориям, которые пользователь явно выбрал через системный диалог (`NSOpenPanel` / `file_selector`). |
| `com.apple.security.files.user-selected.read-write` | `Boolean` | Доступ на чтение и запись к выбранным пользователем файлам/папкам (например, сохранение проектов или импорт `.env`). |
| `com.apple.security.files.bookmarks.app-scope` | `Boolean` | Разрешает сохранять *Security-Scoped Bookmarks*, чтобы приложение сохраняло доступ к выбранной пользователем папке после перезапуска. |
| `com.apple.security.files.downloads.read-write` | `Boolean` | Прямой доступ на чтение и запись в системную папку `~/Downloads` без вызова диалога выбора. |

### Пример `macos/Runner/Release.entitlements` (для Mac App Store)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://apple.com">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
	<key>com.apple.security.files.bookmarks.app-scope</key>
	<true/>
</dict>
</plist>
```

---

## 2. Метаданные приложения (`Info.plist`)

Файлы содержат базовую конфигурацию бандла, номера версий, системные ограничения и описания запросов приватности.

* **Расположение в проекте:**
  * `ios/Runner/Info.plist`
  * `macos/Runner/Info.plist`

### Идентификация, версии и категории

| Ключ | Платформа | Описание |
| :--- | :--- | :--- |
| `CFBundleDisplayName` | iOS / macOS | Отображаемое имя приложения под иконкой на устройстве пользователя. |
| `CFBundleShortVersionString` | iOS / macOS | Публичная версия приложения (например, `0.1.0`). Во Flutter транслируется из `$(FLUTTER_BUILD_NAME)`. |
| `CFBundleVersion` | iOS / macOS | Внутренний номер сборки (например, `1`). **Обязан быть целым числом** и увеличиваться при каждой новой загрузке в App Store Connect. Во Flutter берётся из `$(FLUTTER_BUILD_NUMBER)`. |
| `LSApplicationCategoryType` | **macOS** | **Обязателен для Mac App Store.** UTI-идентификатор категории приложения (например, `public.app-category.developer-tools`, `public.app-category.education`, `public.app-category.productivity`). |
| `LSMinimumSystemVersion` | **macOS** | Минимальная поддерживаемая версия macOS (например, `12.0`). |

### Экспортное шифрование и интеграция с файловой системой

| Ключ | Платформа | Описание |
| :--- | :--- | :--- |
| `ITSAppUsesNonExemptEncryption` | iOS / macOS | Значение `false` указывает, что приложение использует только стандартное шифрование ОС (HTTPS/TLS). Избавляет от ручного заполнения анкеты *Export Compliance* при каждой загрузке билда. |
| `UIFileSharingEnabled` | **iOS** | Значение `true` делает папку `Documents` приложения видимой в системном приложении **«Файлы» (Files)** на iOS/iPadOS. |
| `LSSupportsOpeningDocumentsInPlace` | **iOS** | Значение `true` (в паре с `UIFileSharingEnabled`) разрешает открывать и изменять файлы приложения напрямую в приложении «Файлы» без создания копий. |

### Системные разрешения (Privacy Usage Descriptions)

Если приложение или подключённые плагины обращаются к аппаратным модулям или личным данным, отсутствие строки с объяснением для пользователя приведёт к автоматическому отклонению сборки при загрузке:

* `NSCameraUsageDescription` — доступ к камере (iOS / macOS).
* `NSMicrophoneUsageDescription` — доступ к микрофону (iOS / macOS).
* `NSPhotoLibraryUsageDescription` — чтение медиатеки фото (iOS).
* `NSLocalNetworkUsageDescription` — обнаружение устройств и сервисов в локальной сети (iOS).

---

## 3. Параметры экспорта и подписи (`ExportOptions-AppStore.plist`)

Файлы используются командами `flutter build ipa` и `xcodebuild -exportArchive` для упаковки скомпилированного архива `.xcarchive` в подписанные дистрибутивы `.ipa` (iOS) и `.pkg` (macOS).

* **Расположение в проекте:**
  * `ios/ExportOptions-AppStore.plist`
  * `macos/ExportOptions-AppStore.plist`

### Описание ключей

| Ключ | Тип | Платформа | Описание |
| :--- | :--- | :--- | :--- |
| `method` | `String` | iOS / macOS | Способ дистрибуции. Для App Store и TestFlight используется `app-store-connect` (или `app-store`). |
| `teamID` | `String` | iOS / macOS | 10-символьный идентификатор команды разработчика из Apple Developer Portal (например, `ZZ786DRM9C`). |
| `signingStyle` | `String` | iOS / macOS | Режим подписи: `manual` (явное указание сертификатов и профилей) или `automatic` (автоматический подбор через Xcode). |
| `signingCertificate` | `String` | iOS / macOS | Сертификат подписи самого приложения (`.app` / `.ipa`). Для App Store используется `Apple Distribution`. |
| `installerSigningCertificate` | `String` | **Только macOS** | Сертификат подписи установочного пакета `.pkg`: `3rd Party Mac Developer Installer: <Name> (<TeamID>)` или `Mac Installer Distribution`. |
| `provisioningProfiles` | `Dictionary` | iOS / macOS | Словарь соответствия: ключ — `Bundle ID` (`com.openidealab.codelab`), значение — точное имя профиля из Apple Developer Portal (отдельное для iOS и macOS). |
| `uploadSymbols` | `Boolean` | iOS / macOS | `true` — включать отладочные символы (`dSYM`) в сборку для дешифровки отчётов о сбоях (Crash Logs) в App Store Connect. |
| `manageAppVersionAndBuildNumber` | `Boolean` | iOS / macOS | `true` — разрешает `xcodebuild` проверять и управлять версиями при экспорте. |
| `stripSwiftSymbols` | `Boolean` | **Только iOS** | `true` — удаляет лишние символы Swift для уменьшения итогового размера `.ipa`. |

### Пример `ios/ExportOptions-AppStore.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://apple.com">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string>XXXXXXXX</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Apple Distribution</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>com.openidealab.codelab</key>
        <string>CodeLab Ios AppStore</string>
    </dict>
    <key>uploadSymbols</key>
    <true/>
    <key>manageAppVersionAndBuildNumber</key>
    <true/>
</dict>
</plist>
```

### Пример `macos/ExportOptions-AppStore.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://apple.com">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>XXXXXXXX</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Apple Distribution</string>
    <key>installerSigningCertificate</key>
    <string>3rd Party Mac Developer Installer: Sergey Penkovsky (XXXXXXXX)</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>com.openidealab.codelab</key>
        <string>CodeLab Mac AppStore</string>
    </dict>
    <key>uploadSymbols</key>
    <true/>
    <key>manageAppVersionAndBuildNumber</key>
    <true/>
</dict>
</plist>
```

---

## 4. Сводная таблица отличий сборок macOS (App Store vs DMG)

| Параметр | Mac App Store (`.pkg`) | Прямое распространение (`.dmg`) |
| :--- | :--- | :--- |
| **App Sandbox** | Обязателен (`true`) | Не требуется (`false`) |
| **Сертификат приложения** | `Apple Distribution` | `Developer ID Application` |
| **Сертификат упаковки** | `3rd Party Mac Developer Installer` | Не требуется (нотаризация через `notarytool`) |
| **Provisioning Profile** | Обязателен (`Mac App Store Connect`) | Не требуется |
| **`LSApplicationCategoryType`** | Обязателен в `Info.plist` | Рекомендуется |
