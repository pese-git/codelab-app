# CodeLab app: эксплуатация

Здесь — как собрать CodeLab app для macOS, где приложение хранит данные и логи, какие переменные окружения оно читает и какие сетевые соединения открывает.

## Схема развёртывания

На схеме — процесс приложения, его файлы и сетевые соединения.

```mermaid
flowchart LR
  subgraph host["Mac пользователя"]
    subgraph proc["Процесс codelab_app"]
      ui["Окно и клиентский слой"]
      embedded["Встроенный агент"]
      term["Терминал пользователя"]
    end
    child["Агент-процесс, профиль stdio"]
    shell["Оболочка, процесс PTY"]
    mcpproc["MCP-серверы stdio"]
    home[("CODELAB_HOME: config.yaml, profiles.json, recent_projects.json, secrets.yaml, sessions/")]
    support[("Application Support: logs/")]
    prefs[("NSUserDefaults: снимок рабочего места, раскладка")]
  end
  ui -->|"ACP в памяти"| embedded
  ui -->|"stdin/stdout"| child
  term --> shell
  ui -->|"WebSocket"| remote["Агент по ws:// или wss://"]
  embedded -->|"HTTP(S)"| llm["Провайдер модели"]
  embedded --> mcpproc
  embedded -->|"HTTP"| mcphttp["MCP-серверы http"]
  proc --- home
  proc --- support
  proc --- prefs
```

- По умолчанию работает один процесс: встроенный агент выполняется внутри приложения.
- Агент-процесс появляется, только если выбран профиль `stdio`. Приложение запускает его и завершает при выходе.
- Терминал пользователя запускает оболочку входа (`-l`) через PTY (псевдотерминал) в папке сессии: `SHELL`, если это абсолютный путь к исполняемому файлу, иначе `/bin/zsh`, `/bin/bash` или `/bin/sh`. При выходе приложение посылает ей сигнал завершения, а через 3 секунды завершает принудительно.
- Приложение не открывает портов на приём. Исходящие соединения: к провайдеру модели, к MCP-серверам типа `http`, к агенту по WebSocket и загрузка изображения из ответа агента — только `https` и только после нажатия «Show image» (до 32 МБ). Ссылки `http`/`https` из ленты, терминала, страницы «Legal» и раздела «About» («Release notes») открывает браузер, а `mailto:` из ленты — почтовый клиент; само приложение по ним не ходит. Документы страницы «Legal» читаются из ресурсов сборки, без сети.

## Сборка

Требования и подготовка репозитория (`fvm install`, `melos bootstrap`, генерация `*.freezed.dart`) — в [запуске из исходников](../../../docs/user/run-from-source.md#1-подготовка). Версия Flutter закреплена в `.fvmrc`. Нужен Xcode с командной строкой.

```bash
cd apps/codelab_desktop
fvm flutter build macos
```

Получится `apps/codelab_desktop/build/macos/Build/Products/Release/codelab_app.app`. Отдельного скрипта Melos для сборки приложения нет.

Параметры сборки:

| Параметр | Значение | Где задан |
|---|---|---|
| имя приложения | `codelab_app` | `macos/Runner/Configs/AppInfo.xcconfig` |
| идентификатор бандла | `com.example.codelabApp` — значение шаблона Flutter | `macos/Runner/Configs/AppInfo.xcconfig` |
| версия | `0.1.0` | `pubspec.yaml` |
| минимальная macOS | 12.0 | `macos/Podfile`, `macos/Runner.xcodeproj` |

### Платформы

Собирается и проверяется только macOS. Каталоги `linux/`, `windows/`, `android/`, `ios/` и `web/` в `apps/codelab_desktop` созданы командой `flutter create`, в них лежат иконки CodeLab, а для Linux — ещё иконка окна GTK и ярлык `linux/packaging/*.desktop`. Сборки и проверки для этих платформ в проекте нет, поддержка не заявлена.

### Ресурсы сборки

В бандл входят шесть правовых документов из `assets/legal/`: `LICENSE`, `THIRD_PARTY_NOTICES.md`, `PRIVACY.md`, `PRIVACY.ru.md`, `TERMS.md`, `TERMS.ru.md` (объявлены в `pubspec.yaml`). Это побайтные копии одноимённых файлов корня репозитория: Flutter не берёт ресурсы вне каталога пакета. Тест `test/app/legal_assets_test.dart` называет разошедшийся или необъявленный файл, поэтому после правки корневого документа копию обновляют вместе с ним. Приложение читает их при показе страницы «Legal», раздела «About» и шага «Privacy» приветственных шагов; список лицензий пакетов Flutter собирает при сборке по `package_config.json` — в pub workspace он включает все пакеты рабочего пространства, в том числе инструменты разработки.

Язык меню macOS задаёт `CFBundleLocalizations` (`en`, `ru`) в `macos/Runner/Info.plist` и `macos/Runner/ru.lproj/MainMenu.strings`: меню следует языку системы, а не выбору в приложении. Пункт «Preferences…» (⌘,) меню приложения открывает настройки через канал `codelab/app_menu` (`macos/Runner/AppDelegate.swift`).

### Подпись и entitlements

- Сборка подписывается ad-hoc (`CODE_SIGN_IDENTITY = "-"`): без сертификата разработчика и без нотаризации. Для распространения за пределы своей машины подпись и нотаризацию нужно настроить отдельно.
- App Sandbox выключен: `com.apple.security.app-sandbox = false` в `macos/Runner/Release.entitlements` и `DebugProfile.entitlements`. Приложению нужен доступ к папкам проектов, к `CODELAB_HOME` и запуск процессов (агент, оболочка, MCP-серверы). Включение песочницы потребует пересмотра хранилищ секретов — это отдельное изменение.
- Для отладочной и profile-сборки (`DebugProfile.entitlements`) добавлены `com.apple.security.cs.allow-jit` и `com.apple.security.network.server` (сервис отладки Dart).

## Запуск

Из Finder или Dock приложение получает минимальное окружение macOS и не видит переменных, заданных в профиле оболочки. Чтобы передать приложению переменные (`CODELAB_HOME`, ключи), запустите исполняемый файл из терминала:

```bash
CODELAB_HOME="$HOME/.codelab-test" \
  apps/codelab_desktop/build/macos/Build/Products/Release/codelab_app.app/Contents/MacOS/codelab_app
```

Для запуска из Finder ключи лучше хранить в файловом хранилище секретов — [шаг 2 настройки агента](../../../docs/user/configuration.md#шаг-2-задайте-ключ-api).

При запуске приложение восстанавливает последний проект и запускает агента в его папке. Без сохранённого проекта агент не стартует, пока пользователь не откроет папку.

## Где лежат данные

### `CODELAB_HOME`

Конфигурация агента, профили подключения, секреты, журналы сессий встроенного агента и пользовательские цветовые темы app лежат в `CODELAB_HOME` (по умолчанию `~/.codelab`) и общие с терминальным клиентом `codelab` — [каталог `CODELAB_HOME`](../../../docs/ops/codelab-home.md).

Темы — файлы `$CODELAB_HOME/themes/<имя>.json`: их кладёт пользователь или «Import JSON…» на странице «Appearance» (файл копируется без изменений, замена атомарная). Если каталога нет, своих тем просто нет; app создаёт его при «Import JSON…» и при «Open folder»; файл больше 64 КиБ не загружается. Формат и правила — [руководство пользователя](user/09-settings.md#своя-тема). В каталог app ничего другого не пишет, а файлы тем сам не открывает.

Если `CODELAB_HOME` задан неверно (например, `~user/…`), страница «Connection» показывает причину, а профили недоступны для записи.

### Данные приложения вне `CODELAB_HOME`

| Где | Что |
|---|---|
| `~/Library/Preferences/com.example.codelabApp.plist` | настройки окна через `shared_preferences` (ключи с префиксом `flutter.`): снимок рабочего места `codelab.workspace.snapshot` (проект и активная сессия), профиль по умолчанию `codelab.connection.default_profile`, раскладка панелей `codelab.dock.*`, последняя страница настроек `codelab.settings.last_page`, язык интерфейса `codelab.app.language` (`en` или `ru`; для «System» ключа нет), оформление `codelab.app.appearance` (JSON: `version`, `mode` — `light`, `dark` или `system`, `light_theme`, `dark_theme`, `system_accent`; ключа нет, пока оформление не меняли), флаг «приветственные шаги пройдены» `codelab.app.onboarding_done` (только `true`; ключа нет, пока шаги не пройдены), переключатель «Reopen the last project and its tabs» `codelab.workspace.reopen_last_project` (включено — ключа нет; записывается только значение `false`) |
| `~/Library/Application Support/com.example.codelabApp/logs/` | логи приложения — [ниже](#логи-и-диагностика) |

Имя файла настроек и каталога берётся из идентификатора бандла: другая сборка с другим идентификатором получит отдельные настройки.

Недавние проекты в этом домене больше не хранятся: список лежит в `$CODELAB_HOME/recent_projects.json` и общий с `codelab` ([общие файлы](../../../docs/ops/codelab-home.md#общие-файлы)). В предвыпускных сборках при первом обращении к списку app один раз переносит в файл прежний ключ `codelab.recent_projects` и удаляет его из домена. В журнал пишутся события `recent_projects.migrated`, `recent_projects.legacy_unreadable` (значение ключа не разобрано, ключ удалён) и `recent_projects.migration_failed` (например, файл нечитаем: ключ остаётся); пути в них не попадают. Нечитаемый `recent_projects.json` app не перезаписывает: список пуст, пока вы не удалите файл. Если `CODELAB_HOME` задан неверно, список недоступен, причина видна в диагностике, а ключ в домене остаётся нетронутым. Перенос есть только в предвыпускных сборках: при обновлении с предвыпускной сборки сразу на 1.0 недавние проекты и настройки окна начинаются заново (идентификатор бандла меняется); проекты, открытые в `codelab`, остаются в списке — они в `CODELAB_HOME`.

Сбросить все настройки окна (раскладку, снимок рабочего места, профиль по умолчанию, последнюю страницу настроек, язык, оформление, флаги «открывать последний проект» и «приветственные шаги пройдены») можно, удалив домен настроек при закрытом приложении:

```bash
defaults delete com.example.codelabApp
```

Сессии, профили, недавние проекты и конфигурация агента при этом не затрагиваются: они в `CODELAB_HOME`. Чтобы сбросить недавние проекты, закройте приложение и `codelab` и удалите `$CODELAB_HOME/recent_projects.json`.

## Переменные окружения

Переменные `CODELAB_*` (`CODELAB_HOME`, `CODELAB_CONFIG`, `CODELAB_SECRET_<ИМЯ>`, `CODELAB_DEBUG_SECRETS` и другие) общие для приложений CodeLab — их таблица в [переменных окружения](../../../docs/ops/environment.md). Здесь — только то, что относится к app.

| Переменная | Для чего |
|---|---|
| `HOME` | также сокращает пути до `~` в интерфейсе |
| переменная из `api_key_env` провайдера | ключ API провайдера для встроенного агента |
| переменная из ссылки `env:<ИМЯ>` профиля | токен WebSocket-профиля |
| `SHELL` | оболочка терминала пользователя; без неё — `/bin/zsh`, `/bin/bash`, `/bin/sh` |

Диагностика секретов `CODELAB_DEBUG_SECRETS=1` — в [переменных окружения](../../../docs/ops/environment.md#диагностика). Встроенный агент получает окружение процесса приложения.

### Секреты

- Ключи провайдеров и токены профилей хранятся в общем хранилище секретов CodeLab, как у `codelab` и `codelab-agent`. Отдельного хранилища у приложения нет, связку ключей macOS эта версия не использует.
- По умолчанию хранилище — `env`: только чтение переменных `CODELAB_SECRET_*`. На странице «Providers» оно помечено «read-only». Записывать ключи из приложения можно после `secrets.backend: file` в глобальном `config.yaml`; файл `$CODELAB_HOME/secrets.yaml` хранит значения открытым текстом с правами `0600`.
- Токен профиля сохраняется в `profiles.json` только ссылкой (`env:<ИМЯ>` или `secret:<имя>`), значение читается при подключении.
- Значения ключей и токенов не попадают в состояние приложения, на экран и в логи: только имя секрета и признак «задан».
- Если секреты записаны прямо в `config.yaml`, приложение показывает баннер «Secrets are stored in the agent config file.» с кнопкой «Migrate secrets»: перенос в хранилище и затем перезапуск встроенного агента.

## Логи и диагностика

| Где | Что | Когда пишется |
|---|---|---|
| `~/Library/Application Support/com.example.codelabApp/logs/application.log` | события приложения строками JSON | только в релизной сборке |
| консоль процесса | те же события в читаемом виде | только в отладочной сборке |
| `~/Library/Application Support/com.example.codelabApp/logs/protocol.log` | полная трассировка сообщений ACP; ротация по 10 МБ, до 5 файлов | по умолчанию выключена; в интерфейсе приложения переключателя нет, а режим «Trace» панели «Protocol» её не включает |
| панель «Protocol» (`/logs`) | вид «Frames» — кадры ACP соединения, вид «Log» — журнал приложения в памяти; в области сессия в фокусе и элементы соединения (без сессии); [подробности](#панель-protocol) | всегда, пока приложение открыто |
| `$CODELAB_HOME/sessions/` | журналы сессий встроенного агента | всегда для встроенного агента |

- Перед записью в любой лог секреты маскируются. События настроек, терминала и файлов проекта не содержат токенов, путей, ввода и вывода терминала, текста файлов. Правила маскирования — в [«Маскирование секретов»](../../../packages/dart/codelab_client_acp/doc/redaction.md).
- Язык интерфейса пишет события (поля — в `context`):

  | Событие | Компонент, уровень | Поля | Когда |
  |---|---|---|---|
  | `app.locale_resolved` | `app`, info | `preference` (`system`, `en`, `ru`), `locale` | один раз при сборке приложения |
  | `settings.language_changed` | `settings`, info | `language`, `locale` | пользователь выбрал язык |
  | `app.locale_applied` | `app`, debug | `locale`, `subscribers` | выбор сменил локаль у подписчиков |
  | `settings.language_save_failed` | `settings`, warning | `error_class` | запись выбора не удалась; текста ошибки нет, потому что в нём бывают пути |
  | `settings.language_save_timeout` | `settings`, warning | `timeout_ms` | при выходе запись выбора языка не завершилась за 3 с; выбор мог не сохраниться |
  | `app.language_preference_invalid` | `app`, warning | нет | при старте после настройки журнала: сохранённое значение незнакомо или не строка; приложение читает его как «System», само значение не пишется |
  | `app.language_preference_read_failed` | `app`, warning | `error_class` | при старте после настройки журнала: хранилище настроек не прочиталось (например, повреждено); приложение стартует как при «System», текста ошибки нет |

- Оформление пишет события в компоненте `settings` (имя своей темы в них не попадает — вместо него `custom`; путей, ключей и значений из файла нет):

  | Событие | Уровень | Поля | Когда |
  |---|---|---|---|
  | `app.appearance_resolved` | info | `mode`, `light_theme`, `dark_theme`, `system_accent`, `fallback` | один раз при сборке приложения |
  | `settings.appearance_changed` | info | `field` (`mode`, `light_theme`, `dark_theme`, `system_accent`), `value`; у тем — `light`, `dark`, `high-contrast` или `custom` | пользователь изменил оформление |
  | `appearance.theme_loaded` | info | `theme`, `extends`, `warnings`, `code_counts` (число предупреждений по кодам) | пользовательская тема прочитана и применена |
  | `appearance.theme_invalid` | warning | `theme`, `code`, `line`, `column`, `error_class` | файл темы отклонён; `code` — код проблемы, например `invalidJson` |
  | `appearance.theme_imported` | info | `outcome`, `error_class` | исход «Import JSON…» |
  | `appearance.system_accent_failed` | warning | `error_class` | не удалось прочитать системный акцент |
  | `appearance.catalog_failed` | warning | `error_class`, `failure` (`notADirectory` или `unreadable`) | каталог тем не прочитался; страница показывает встроенные темы и предупреждение с «Reload», пути в событии нет |
  | `appearance.catalog_discarded` | debug | `reason` | результат устаревшего чтения каталога отброшен |
  | `appearance.stored_value_invalid`, `appearance.read_failed` | warning | `error_class` (у второго) | при старте: сохранённое значение незнакомо или хранилище не прочиталось |
  | `appearance.save_failed` | warning | `error_class` | запись выбора не удалась |
  | `appearance.save_timeout` | warning | `timeout_ms` | при выходе запись не завершилась в срок; выбор мог не сохраниться |

- Приветственные шаги, экран «Open a project», страница «Legal» и запуск без прошлого проекта пишут события (пути, имена секретов и переменных, адреса, id моделей, текст запроса поиска и тексты исключений в них не попадают; для сбоев — только имя типа в `error_type` или `error_class`):

  | Событие | Компонент, уровень | Поля | Когда |
  |---|---|---|---|
  | `onboarding.shown` | `onboarding`, info | нет | при сборке приложения: флага «шаги пройдены» нет |
  | `onboarding.flag_invalid` | `onboarding`, warning | нет | в флаге неожиданное значение: шаги не показываются, значение не перезаписывается |
  | `onboarding.flag_unreadable` | `onboarding`, warning | `error_type` | хранилище настроек не прочиталось: шаги не показываются |
  | `onboarding.step_shown` | `onboarding`, debug | `step` | показан шаг |
  | `onboarding.facts_loaded` | `onboarding`, debug | `access` (`editable` или `external`), `readiness`, `backend`, `duration_ms` | настройки агента для шагов «Permissions» и «Choose a model» прочитаны |
  | `onboarding.facts_unavailable` | `onboarding`, warning | `error_type` или данные таймаута | настройки не прочитались или не уложились в 5 с |
  | `onboarding.facts_late` | `onboarding`, debug | `duration_ms` | настройки пришли после таймаута; шаги их не применяют |
  | `onboarding.model_step_skipped` | `onboarding`, info | `reason` | шаг модели пропущен: провайдер готов или агент внешний |
  | `onboarding.model_saved` | `onboarding`, info | нет | мастер на шаге модели сохранил провайдера |
  | `onboarding.document_opened`, `onboarding.document_closed` | `onboarding`, info и debug | `tab` (`privacy_policy` или `terms_of_use`) | открыт и закрыт документ на шаге «Privacy» |
  | `onboarding.project_pick_cancelled` | `onboarding`, debug | нет | окно выбора папки закрыто без выбора |
  | `onboarding.project_port_failed`, `onboarding.save_failed` | `onboarding`, warning | `error_type` | не открылся выбор папки; не записался флаг (шаги всё равно завершаются) |
  | `onboarding.completed` | `onboarding`, info | `model_step` (`skipped`, `saved` или `later`), `project` (`picker`, `drop`, `recent`, `restored` или `skipped`) | шаги пройдены |
  | `project.drop` | `app`, info | `outcome` (`opened` или `rejected`), `reason` (при отказе), `count` | папка брошена на экран «Open a project» или на шаг «Open a project» |
  | `project.picker_failed` | `app`, warning | `error_class` | не открылось окно выбора папки |
  | `project.start_held` | `app`, debug | нет | папка выбрана на шаге «Open a project»: агент стартует после завершения шагов |
  | `app.reopen_last_project_skipped` | `app`, info | нет | переключатель «Reopen the last project and its tabs» выключен: проект не восстанавливается |
  | `app.reopen_last_project_unreadable` | `app`, warning | `error_class` (только при сбое хранилища) | значение переключателя не прочиталось; приложение читает его как «включено» |
  | `settings.reopen_last_project_changed` | `settings`, info | `enabled` | пользователь переключил настройку |
  | `settings.reopen_last_project_save_failed` | `settings`, warning | `error_type` | запись настройки не удалась |
  | `legal.tab_selected` | `settings`, debug | `tab`, `source` (`open`, `tab` или `link`) | на странице «Legal» (и в документе шага «Privacy», где работает та же страница) выбрана вкладка |
  | `legal.link_opened` | `settings`, info | `target` (`tab` или `external`), `outcome` | нажата ссылка в документе (в том числе на шаге «Privacy») |
  | `legal.licenses_collected` | `settings`, info | `packages`, `failed` | собран список лицензий пакетов |
  | `legal.document_load_failed` | `settings`, warning | `tab`, `error_type` | документ не прочитался |
  | `settings.legal_link` | `settings`, info | `from` (`privacy_block` или `about`), `tab` | переход на «Legal» со страницы «General» |
  | `settings.about_action` | `settings`, info | `action`, `outcome` | действие раздела «About» |
  | `settings.about_load_failed` | `settings`, warning | `error_type` | раздел «About» не загрузился |

- До выпуска 1.0 тексты сообщений и вывод инструментов в журналах сессий не редактируются — [что попадает в логи и журналы](../../../docs/user/configuration.md#что-попадает-в-логи-и-журналы).
- Отправка событий на сервер логов включается только при сборке разработчиком через `--dart-define=CODELAB_LOG_SERVER_URL=…` и `--dart-define=CODELAB_LOG_SERVER_KEY=…`. В обычной сборке её нет.

### Панель Protocol

Панель хранит данные только в памяти приложения. Как ею пользоваться — [в руководстве пользователя](user/05-workbench-tools.md#смотреть-подробности-соединения).

- Буфер кадров ACP один на соединение. Он держит до 2000 кадров и до 8 MiB суммарных данных кадров; при превышении вытесняются самые старые. Кадр с данными больше 256 KiB сохраняется без данных. Панель показывает из буфера сессию в фокусе и элементы соединения; «Clear» очищает буфер целиком.
- В release-сборке хранятся только метаданные кадров: направление, метод, id, сессия, размер, код ошибки. Полные данные кадров (промпты, содержимое файлов, вывод инструментов, аргументы и результаты вызовов инструментов) хранятся в debug-сборке и в release-сборке, пока пользователь держит включённым переключатель «Trace». Запись журнала `protocol_message` несёт полный кадр только в debug-сборке; «Trace» записи журнала не меняет.
- В release-сборке записи журнала о сбоях — запроса к агенту, старта и перезапуска подключения, создания сессии, восстановления рабочего пространства — содержат только префикс CodeLab и метаданные: метод, код ошибки JSON-RPC, стандартное имя кода, класс ошибки. Текста ошибки агента (`error.message`, `data`) в них нет. Пользователь по-прежнему видит этот текст в транскрипте и в баннере подключения; для разбора по журналу нужен режим «Trace» панели Protocol (кадр-ошибка с текстом, замаскированным от секретов) или debug-сборка.
- «Trace» выключен при каждом запуске, не сохраняется и не включается сам. Выключение стирает данные кадров из буфера. Секреты маскируются до сохранения кадра всегда, в том числе в «Trace».
- «Trace» не включает файл `protocol.log` и ничего не пишет на диск. На диск попадает только то, что пользователь сохранил кнопкой «Export…»: файл JSON Lines (`codelab-protocol-<frames|log>-<дата>-<время>.jsonl`) с замаскированными данными. В release без «Trace» в нём нет данных кадров; в debug-сборке и в «Trace» перед экспортом кадров с данными приложение спрашивает подтверждение. Файл записывается целиком или не записывается: существующий файл при сбое не меняется.
- События журнала приложения: `protocol_pane.trace` (info, поле `enabled`) при каждом переключении «Trace»; `protocol_pane.clear` (info, `view`, `count`) при «Clear»; `protocol_pane.export` (info, `view`, `outcome` — `saved`, `cancelled` или `failed`, `count`, при `failed` — `error_class`); `protocol_pane.view` (debug, `view`) при смене вида. `protocol_pane.action_failed` (error, `action` — `copy`, `expand` или `export`, `error_class`) пишется, когда действие панели завершилось исключением. Путей, данных кадров и значений фильтров в них нет.

## Выход из приложения

При закрытии приложение закрывает вкладки терминала и параллельно — сессии, встроенного агента, агент-процесс и ядро клиента. Отдельными параллельными ветвями приложение дожидается записи выбранного языка и оформления (до 3 секунд каждая); они не задерживают закрытие рабочего пространства, агента и транспорта. Если запись не уложилась в эти 3 секунды, приложение пишет `settings.language_save_timeout` или `appearance.save_timeout`. На всё отводится 5 секунд. Не уложилось — приложение пишет событие `app.exit_timeout` с полем `pending`: имена незавершённых шагов (например, `terminal`, `workspace`, `embedded`, `client`, `language`, `appearance`), — и всё равно завершается. Закрытие встроенного агента при этом не укорачивается и идёт, пока процесс не остановится; отдельного события о нём при выходе нет.

Предел 10 секунд на закрытие встроенного агента и событие `embedded.close_timeout` относятся к закрытию корневого scope приложения без запроса на выход; при выходе раньше срабатывает общий предел 5 секунд.

## Сеть и безопасность

- Портов на приём приложение не открывает.
- Файловые операции и команды, которые агент просит у приложения, ограничены папкой сессии; выход за неё отклоняется. Для сессии в корне диска приложение спрашивает подтверждение.
- Терминал пользователя не ограничен папкой сессии и не проходит через одобрения агента: это оболочка от имени пользователя. Терминал не даёт программам читать и писать системный буфер обмена управляющими последовательностями и открывает из вывода только ссылки `http` и `https` после подтверждения.
- `ws://` на другую машину (не локальный адрес) передаёт данные без шифрования: при сохранении такого профиля приложение требует подтверждения «Save anyway» — с токеном и без. Для локального адреса подтверждения нет. Ключ к провайдеру по `http://` на нелокальный адрес мастер помечает предупреждением `The key is sent unencrypted to <host>.`

## Смотрите также

- [Эксплуатация CodeLab](../../../docs/ops/README.md)
- [Каталог `CODELAB_HOME`](../../../docs/ops/codelab-home.md)
- [Руководство пользователя CodeLab app](user-guide.md)
