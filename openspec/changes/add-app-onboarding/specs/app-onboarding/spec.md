## ADDED Requirements

### Requirement: Показ onboarding при первом запуске
App SHALL показывать onboarding (`OnboardingDestination`, ключ `onboarding`) вместо рабочего места, если в `shared_preferences` нет ключа `codelab.app.onboarding_done`. Ключ SHALL читаться до `runApp`, чтобы первый кадр уже был экраном onboarding или рабочим местом, без промежуточного кадра другого экрана (design.md change `add-app-onboarding`, D2, D3).

Значение `true` SHALL означать, что onboarding пройден. Значение другого типа или содержания SHALL читаться как «пройден» и НЕ SHALL перезаписываться; журнал SHALL содержать `onboarding.flag_invalid`. Сбой хранилища при чтении SHALL давать рабочее место без onboarding и событие `onboarding.flag_unreadable` с именем типа ошибки, без её текста.

Onboarding НЕ SHALL входить в шаги сторожа запуска; когда сторож появится (D-15, §12.4.7), onboarding SHALL показываться после `BootReady`.

#### Scenario: Первый запуск
- **WHEN** app запускается с пустым `shared_preferences`
- **THEN** первый кадр показывает экран `onboarding` на шаге «What CodeLab does», рабочего места (`CodeLabShell`) в дереве нет, журнал содержит `onboarding.shown`

#### Scenario: Onboarding пройден
- **WHEN** в `shared_preferences` лежит `codelab.app.onboarding_done: true`
- **THEN** первый кадр показывает рабочее место, экрана `onboarding` нет

#### Scenario: Повреждённое значение флага
- **WHEN** в ключе `codelab.app.onboarding_done` лежит строка `"yes"`
- **THEN** app показывает рабочее место, значение ключа после запуска осталось `"yes"`, журнал содержит `onboarding.flag_invalid`

#### Scenario: Хранилище не читается
- **WHEN** чтение `shared_preferences` бросает исключение с путём в тексте
- **THEN** app показывает рабочее место, журнал содержит `onboarding.flag_unreadable` с `error_type` и не содержит пути

### Requirement: Шаги onboarding и переходы
Onboarding SHALL состоять из четырёх шагов в порядке: «What CodeLab does» (`onboarding-step-welcome`), «Permissions» (`onboarding-step-permissions`), «Choose a model» (`onboarding-step-model`), «Privacy» (`onboarding-step-privacy`). Над шагом SHALL стоять строка шагов со всеми четырьмя подписями: пройденные (и пропущенный) — с отметкой, текущий — выделен. Кнопки: «Back» (`onboarding-back`; нет на первом шаге), «Next» (`onboarding-next`; на шаге «Privacy» вместо неё — «Start using CodeLab», `onboarding-finish`).

Переходы SHALL следовать таблице design.md change `add-app-onboarding`, D4: «Back» на шаге «Privacy» SHALL вести на «Choose a model», если этот шаг не пропущен, иначе на «Permissions». Esc НЕ SHALL закрывать onboarding. Cmd/Ctrl+, и пункт меню macOS «Preferences…» НЕ SHALL открывать настройки, пока показан onboarding. Выход из app до «Start using CodeLab» НЕ SHALL записывать флаг.

«Next» на шаге «Permissions» SHALL ждать итога чтения фактов (требование «Пропуск шага выбора модели») не дольше его таймаута; повторное нажатие во время ожидания НЕ SHALL давать второго перехода.

#### Scenario: Проход без пропуска
- **WHEN** готовность — `NoProviderConfigured`, и пользователь нажимает «Next», «Next», «Set up later»
- **THEN** экран последовательно показывает шаги `welcome`, `permissions`, `model`, `privacy`; на шаге `privacy` есть «Start using CodeLab»

#### Scenario: Back при пропущенном шаге модели
- **WHEN** готовность — `ProviderReady`, пользователь дошёл до шага «Privacy» и нажимает «Back»
- **THEN** показан шаг «Permissions»; строка шагов показывает «Choose a model» с отметкой

#### Scenario: Esc и настройки на onboarding
- **WHEN** на шаге «Permissions» пользователь нажимает Esc, затем Cmd/Ctrl+,
- **THEN** показан тот же шаг, назначение навигации — `OnboardingDestination`

#### Scenario: Выход до конца
- **WHEN** пользователь закрывает app на шаге «Choose a model» и запускает его снова
- **THEN** ключ `codelab.app.onboarding_done` не записан, onboarding снова начинается с «What CodeLab does»

### Requirement: Шаг «What CodeLab does»
Шаг SHALL показывать заголовок `An AI coding agent that works in your project`, вводный текст и четыре карточки по артборду 07b: «Works in one project folder», «You approve the changes», «Your model, your key», «The agent runs inside the app» (с тегом `Built-in`), и строку `Setup takes four short steps. You can change every choice later in Settings.` Текст карточки «Your model, your key» SHALL быть `Connect a cloud provider or a local model. The key stays on this computer.` и НЕ SHALL называть системную связку ключей (design.md change `add-app-onboarding`, D9).

#### Scenario: Нет обещания связки ключей
- **WHEN** показан шаг «What CodeLab does» при бэкенде секретов `env`
- **THEN** на экране нет текста `keychain`, есть `The key stays on this computer.`

### Requirement: Шаг «Permissions»
Шаг SHALL показывать заголовок `The agent asks before it changes anything`, текст об одобрениях в разговоре и таблицу режима `standard` по артборду 07: «Read files in the project» — `No prompt`; «Edit and create files» — `Asks each time`; «Run commands» — `Asks each time`; «Anything outside the project folder» — `Blocked`. InfoBar под таблицей SHALL зависеть от действующего режима новой сессии (`sessionDefaultsOf` моста, правило страницы «Agents & modes»; design.md change `add-app-onboarding`, D7):
- режим `standard` или факты недоступны — `New sessions start in standard mode` и текст артборда со ссылкой на «Settings › Agents & modes»;
- настраиваемый агент с другим режимом — `New sessions start in <mode> mode` с пометкой `Your config sets this; the table above describes standard mode.`;
- профиль по умолчанию — внешний агент — `Your default connection is an external agent. It applies its own rules; approvals still appear in the conversation.`

#### Scenario: Режим по умолчанию
- **WHEN** `CODELAB_HOME` пуст
- **THEN** InfoBar — `New sessions start in standard mode`

#### Scenario: Режим из общего с CLI конфига
- **WHEN** `~/.codelab/config.yaml` задаёт `permissions.mode: bypass`
- **THEN** InfoBar называет `bypass` и содержит `the table above describes standard mode`

### Requirement: Пропуск шага выбора модели
При создании onboarding SHALL один раз читать факты для шагов через порт `OnboardingProbe` с таймаутом 5 с (design.md change `add-app-onboarding`, D6). Доступ к настройкам SHALL определяться по профилю по умолчанию (`DefaultProfileResolver`, `resolveSettingsAccess` моста `codelab_setup`) без папки проекта. Для `EditableSettings` готовность SHALL вычислять функция моста `checkProviderReadiness` (spec client-agent-setup «Готовность провайдера»); значения ключей НЕ SHALL читаться.

Шаг «Choose a model» SHALL:
- пропускаться при `ProviderReady` (журнал — `onboarding.model_step_skipped {reason: ready}`);
- пропускаться, если профиль по умолчанию не `EditableSettings` (`reason: external`);
- показываться при `NoProviderConfigured`, `ProviderKeyMissing`, `ConfigBroken`, сбое и таймауте чтения.

Итог чтения после таймаута или после закрытия onboarding НЕ SHALL менять состояние.

#### Scenario: Провайдер уже настроен
- **WHEN** `config.yaml` задаёт провайдера с моделью и `api_key_env: K`, а `K` задана в окружении app
- **THEN** после «Next» на шаге «Permissions» показан шаг «Privacy», журнал содержит `onboarding.model_step_skipped` с `reason: ready`

#### Scenario: Внешний агент по умолчанию
- **WHEN** профиль по умолчанию — WebSocket-профиль
- **THEN** шаг «Choose a model» пропущен с `reason: external`, конфиг агента не читается

#### Scenario: Медленное хранилище
- **WHEN** чтение фактов не завершается за 5 с, и пользователь на шаге «Permissions» нажимает «Next»
- **THEN** через 5 с от начала чтения показан шаг «Choose a model» с пояснением `Agent settings could not be read.`, журнал содержит `onboarding.facts_unavailable` с `timeout: true`; результат чтения, пришедший позже, шаг не меняет

### Requirement: Шаг «Choose a model» и мастер провайдера
Шаг SHALL показывать заголовок `Choose where the model runs`, карточки пресетов (ключи `onboarding-preset-<id>`) из той же таблицы, что шаг «API type» мастера, с подписями мастера, и кнопку «Set up <preset>…» (`onboarding-model-setup`) для выбранной карточки. Кнопка SHALL открывать `ProviderWizardDialog` (spec app-settings «Мастер провайдера в app») для встроенного профиля с целью `user`, неснимаемым «Make default», без «This project only», с `entry: onboarding` и уже выбранным пресетом: первым показанным шагом диалога SHALL быть «Base URL» (design.md change `add-app-onboarding`, D8, D11).

Ключ SHALL вводиться и сохраняться только мастером: хранилище секретов агента, порядок «секрет → конфиг», откат секрета при неудачной записи (SETUP-1, SETUP-5). Состояние onboarding, его события и журнал НЕ SHALL содержать значения ключа.

После `ConfigSaved` шаг SHALL показывать `<preset> is connected`, модель по умолчанию `<id>/<model>` и способ хранения ключа (имя секрета и `backend.id`, имя переменной или `No key`), «Set up again…» и активную «Next». Отмена мастера SHALL оставлять шаг как был, без записи.

Кнопка «Set up later» (`onboarding-model-later`) SHALL быть доступна, пока провайдер не сохранён, и SHALL вести на шаг «Privacy» без записи. Пояснения:
- `ProviderKeyMissing` — InfoBar с id провайдера и ссылкой на ключ (имя секрета и `backend.id` либо имя переменной) и путём `Settings › Providers › Edit`; карточки доступны;
- `ConfigBroken` — InfoBar с числом проблем и подсказкой `codelab config check`; карточки и «Set up <preset>…» неактивны, файл конфига НЕ SHALL меняться;
- сбой или таймаут чтения фактов — InfoBar `Agent settings could not be read. You can set up a provider later in Settings › Providers.`; карточки неактивны.

InfoBar о мастере SHALL называть хранилище по фактическому бэкенду: `The key is stored in <backend.id> or read from an environment variable.` при записываемом бэкенде, иначе `The key is read from an environment variable.`

#### Scenario: Провайдер с ключом в файле
- **WHEN** при `secrets.backend: file` и пустом конфиге пользователь выбирает «Custom OpenAI-compatible», нажимает «Set up…», вводит адрес тестового сервера, ключ `sk-test-leak-0123456789`, выбирает модель и сохраняет
- **THEN** диалог начинался с «Base URL»; `config.yaml` содержит `api_key_secret: codelab/<id>` и `agent.default_model`, секрет есть в `secrets.yaml`; шаг показывает `is connected`, `codelab/<id>` и `file`; журнал и состояние onboarding не содержат `sk-test-leak-0123456789`; журнал содержит `provider_wizard.started` с `entry: onboarding`

#### Scenario: Только переменная окружения
- **WHEN** бэкенд секретов — `env`
- **THEN** InfoBar шага — `The key is read from an environment variable.`; в мастере нет варианта «Store in …»

#### Scenario: Отмена мастера
- **WHEN** пользователь открывает мастер на шаге «Choose a model» и нажимает Cancel на шаге ключа
- **THEN** шаг остаётся на выборе пресета, «Next» нет, «Set up later» доступна, файлы не изменены

#### Scenario: Битый конфиг
- **WHEN** `config.yaml` содержит `budget.max_steps: 0`
- **THEN** шаг показывает InfoBar с подсказкой `codelab config check`, «Set up <preset>…» неактивна, после «Set up later» и завершения onboarding `config.yaml` побайтно не изменился

#### Scenario: Ключ не найден
- **WHEN** `config.yaml` задаёт провайдера `openai` с `api_key_secret: codelab/openai`, а секрета нет
- **THEN** InfoBar называет `openai`, `codelab/openai` и `Settings › Providers › Edit`, карточки доступны

### Requirement: Шаг «Privacy»
Шаг SHALL показывать заголовок `What leaves this computer`, текст `Only what the agent needs for the work you ask for, and only to services you set up. CodeLab itself collects nothing.` и строки по артборду 07a:
- «Your model provider» — `Every turn`;
- «MCP servers and web tools» — `When used`, с пометкой, что web-доступ спрашивается;
- «Telemetry, crash reports, usage analytics» — `Never`;
- «Stays here» — `Local`.

Текст строки «Stays here» SHALL строиться по фактам сборки, а не по артборду (design.md change `add-app-onboarding`, D9): каталог конфига и сессий (`CODELAB_HOME` с `~` вместо домашнего каталога), каталог логов app и способ хранения ключей по `id` бэкенда секретов. Шаг НЕ SHALL называть системную связку ключей, если бэкенд — не хранилище ОС.

Шаг НЕ SHALL просить принять условия и НЕ SHALL записывать согласие ни в `shared_preferences`, ни в файлы (D-29, §12.7.7а); InfoBar — `Nothing to agree to`. Ссылки на «Privacy policy» и «Terms of use» НЕ SHALL показываться, пока в сборке нет страницы «Settings › Legal» (SETUP-17; design.md change `add-app-onboarding`, D10).

#### Scenario: Ключи из переменных окружения
- **WHEN** бэкенд секретов — `env`, `CODELAB_HOME` — `~/.codelab`
- **THEN** строка «Stays here» содержит `~/.codelab`, каталог логов app и `API keys are read from environment variables`, и не содержит `keychain`

#### Scenario: Ключи в файле
- **WHEN** бэкенд секретов — `file`
- **THEN** строка «Stays here» содержит `secrets.yaml` и `unencrypted`

#### Scenario: Нечего принимать
- **WHEN** пользователь проходит шаг «Privacy» и нажимает «Start using CodeLab»
- **THEN** на шаге нет флажка или кнопки согласия и ссылок на документы; после завершения в `shared_preferences` новых ключей, кроме `codelab.app.onboarding_done`, нет

### Requirement: Завершение onboarding и старт рабочего места
Пока показан onboarding, app НЕ SHALL строить рабочее место и НЕ SHALL запускать агента окна, в том числе для проекта, восстановленного из снимка прошлого запуска. «Start using CodeLab» SHALL записывать `codelab.app.onboarding_done: true`, переводить навигацию на рабочее место и запускать триггер старта при запуске (spec agent-workbench-ui «Агент стартует сам», триггер 1) ровно один раз (design.md change `add-app-onboarding`, D5). Повторное нажатие во время записи НЕ SHALL давать второй записи и второго перехода. Сбой записи флага SHALL давать событие `onboarding.save_failed` с именем типа ошибки и НЕ SHALL мешать переходу на рабочее место.

#### Scenario: Проект восстановлен, агент ждёт конца onboarding
- **WHEN** снимок прошлого запуска содержит проект `/work/app`, флага нет, и пользователь проходит onboarding с сохранением провайдера
- **THEN** до «Start using CodeLab» открыватель встроенного агента не вызывался; после — вызван один раз с папкой `/work/app`, баннера «Add provider» нет

#### Scenario: Двойное нажатие
- **WHEN** пользователь дважды быстро нажимает «Start using CodeLab»
- **THEN** флаг записан один раз, триггер старта вызван один раз, журнал содержит одно `onboarding.completed`

#### Scenario: Флаг не записался
- **WHEN** запись `shared_preferences` бросает исключение
- **THEN** app показывает рабочее место, журнал содержит `onboarding.save_failed`; при следующем запуске onboarding показан снова

### Requirement: Локализация и доступность onboarding
Все тексты onboarding SHALL браться из каталогов ARB `en` и `ru` (spec app-settings «Локализация интерфейса app»). Имена пресетов, id провайдеров и моделей, `id` бэкенда, имена переменных и секретов, пути и имена режимов SHALL показываться как есть. Строка шагов SHALL объявлять список шагов и текущий шаг для экранного диктора. При показе шага фокус SHALL переходить на его заголовок. Контент SHALL быть не шире 920 px; при окне уже 900 px он SHALL прокручиваться по вертикали без обрезки кнопок.

#### Scenario: Русский интерфейс
- **WHEN** язык app — `ru`, и показан шаг «Privacy» при бэкенде `file`
- **THEN** заголовок и строки — из ARB `ru`, а `secrets.yaml` и `~/.codelab` показаны без перевода

#### Scenario: Узкое окно
- **WHEN** окно 760 × 600 px на шаге «Choose a model»
- **THEN** кнопки «Back» и «Set up later» достижимы прокруткой, переполнения нет

### Requirement: События журнала onboarding без секретов и путей
Onboarding SHALL писать события логгера `codelab_desktop.onboarding` из таблицы design.md change `add-app-onboarding`, D13. События НЕ SHALL содержать пути, имена секретов и переменных, адреса, id моделей, значения ключей и тексты исключений (только имя типа). События мастера SHALL писать мост (`provider_wizard.*`); onboarding их НЕ SHALL дублировать.

#### Scenario: Полный проход без утечек
- **WHEN** пользователь проходит onboarding с мастером, ключом `sk-test-leak-0123456789` и `CODELAB_HOME` `/tmp/codelab-home-marker`
- **THEN** журнал содержит `onboarding.shown`, `onboarding.model_saved`, `onboarding.completed {model_step: saved}`, а `sk-test-leak-0123456789` и `codelab-home-marker` в событиях `onboarding.*` нет
