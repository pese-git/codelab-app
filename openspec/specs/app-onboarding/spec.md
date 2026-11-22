# app-onboarding Specification

## Purpose
Экран первого запуска app (onboarding): пять шагов — что делает CodeLab, разрешения, выбор модели, приватность и открытие проекта — показываются до рабочего места, пока не записан флаг завершения `codelab.app.onboarding_done`; правила показа, переходов между шагами, пропуска шага модели и завершения. Требования введены changes `add-app-onboarding` и `add-onboarding-project-step`.
## Requirements
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
Onboarding SHALL состоять из пяти шагов в порядке: «What CodeLab does» (`onboarding-step-welcome`), «Permissions» (`onboarding-step-permissions`), «Choose a model» (`onboarding-step-model`), «Privacy» (`onboarding-step-privacy`), «Open a project» (`onboarding-step-project`). Над шагом SHALL стоять строка шагов со всеми пятью подписями: пройденные (и пропущенный) — с отметкой, текущий — выделен. Кнопки: «Back» (`onboarding-back`; нет на первом шаге), «Next» (`onboarding-next`; на шаге «Open a project» её нет — onboarding завершают действия требования «Шаг «Open a project»»). Кнопки `onboarding-finish` и текста «Start using CodeLab» НЕ SHALL быть (design.md change `add-onboarding-project-step`, D1).

Переходы SHALL следовать таблице design.md change `add-app-onboarding`, D4, с дополнением design.md change `add-onboarding-project-step`, D1: «Next» на шаге «Privacy» SHALL вести на «Open a project», «Back» на шаге «Open a project» — на «Privacy». «Back» на шаге «Privacy» SHALL вести на «Choose a model», если этот шаг не пропущен, иначе на «Permissions». Esc НЕ SHALL закрывать onboarding. Cmd/Ctrl+, и пункт меню macOS «Preferences…» НЕ SHALL открывать настройки, пока показан onboarding. Выход из app до завершения onboarding на шаге «Open a project» НЕ SHALL записывать флаг.

«Next» на шаге «Permissions» SHALL ждать итога чтения фактов (требование «Пропуск шага выбора модели») не дольше его таймаута; повторное нажатие во время ожидания НЕ SHALL давать второго перехода.

#### Scenario: Проход без пропуска
- **WHEN** готовность — `NoProviderConfigured`, и пользователь нажимает «Next», «Next», «Set up later», «Next»
- **THEN** экран последовательно показывает шаги `welcome`, `permissions`, `model`, `privacy`, `project`; на шаге `privacy` есть «Next», на шаге `project` — `Open folder…` и `Skip for now`; кнопки «Start using CodeLab» нет ни на одном шаге

#### Scenario: Back при пропущенном шаге модели
- **WHEN** готовность — `ProviderReady`, пользователь дошёл до шага «Privacy» и нажимает «Back»
- **THEN** показан шаг «Permissions»; строка шагов показывает «Choose a model» с отметкой

#### Scenario: Back с шага проекта
- **WHEN** пользователь сохранил провайдера на шаге «Choose a model», дошёл до шага «Open a project» и нажимает «Back»
- **THEN** показан шаг «Privacy»; после «Back» на нём — шаг «Choose a model» со сводкой сохранённого провайдера; флаг не записан

#### Scenario: Back к сохранённому провайдеру
- **WHEN** пользователь сохранил провайдера `anthropic` на шаге «Choose a model», нажал «Next», затем на шаге «Privacy» — «Back»
- **THEN** показан шаг «Choose a model» со сводкой `anthropic is connected` и активной «Next»; после «Set up again…» и сохранения провайдера `openai` сводка называет `openai`, а `anthropic` остаётся в `config.yaml`

#### Scenario: Esc и настройки на onboarding
- **WHEN** на шаге «Permissions» пользователь нажимает Esc, затем Cmd/Ctrl+,
- **THEN** показан тот же шаг, назначение навигации — `OnboardingDestination`

#### Scenario: Выход до конца
- **WHEN** пользователь закрывает app на шаге «Choose a model» и запускает его снова
- **THEN** ключ `codelab.app.onboarding_done` не записан, onboarding снова начинается с «What CodeLab does»

#### Scenario: Выход на шаге проекта
- **WHEN** пользователь закрывает app на шаге «Open a project», ничего не выбрав, и запускает его снова
- **THEN** ключ `codelab.app.onboarding_done` не записан, onboarding снова начинается с «What CodeLab does»

### Requirement: Шаг «What CodeLab does»
Шаг SHALL показывать заголовок `An AI coding agent that works in your project`, вводный текст и четыре карточки по артборду 07b: «Works in one project folder», «You approve the changes», «Your model, your key», «The agent runs inside the app» (с тегом `Built-in`), и строку `Setup takes five short steps. You can change every choice later in Settings.` (в `ru` — `Настройка занимает пять коротких шагов. Любой выбор можно изменить позже в настройках.`; число шагов совпадает с требованием «Шаги onboarding и переходы», design.md change `add-onboarding-project-step`, D1). Текст карточки «Your model, your key» SHALL быть `Connect a cloud provider or a local model. The key stays on this computer.` и НЕ SHALL называть системную связку ключей (design.md change `add-app-onboarding`, D9).

#### Scenario: Нет обещания связки ключей
- **WHEN** показан шаг «What CodeLab does» при бэкенде секретов `env`
- **THEN** на экране нет текста `keychain`, есть `The key stays on this computer.`

#### Scenario: Сноска называет пять шагов
- **WHEN** показан шаг «What CodeLab does» на языке `en`, затем на языке `ru`
- **THEN** на экране `Setup takes five short steps. You can change every choice later in Settings.`, затем `Настройка занимает пять коротких шагов. Любой выбор можно изменить позже в настройках.`; текстов `four short steps` и `четыре коротких шага` нет

### Requirement: Шаг «Permissions»
Шаг SHALL показывать заголовок `The agent asks before it changes anything`, текст об одобрениях в разговоре и таблицу режима `standard` по артборду 07: «Read files in the project» — `No prompt`; «Edit and create files» — `Asks each time`; «Run commands» — `Asks each time`; «Anything outside the project folder» — `Blocked`. InfoBar под таблицей SHALL зависеть от действующего режима новой сессии (`sessionDefaultsOf` моста, правило страницы «Agents & modes»; design.md change `add-app-onboarding`, D7):
- факты ещё читаются — InfoBar режима НЕ SHALL показываться; на его месте — индикатор и `Reading the agent settings…`;
- факты недоступны (сбой или таймаут чтения) — `Agent settings could not be read. The mode for new sessions is shown in Settings › Agents & modes.`; шаг НЕ SHALL утверждать режим `standard`;
- режим `standard` — `New sessions start in standard mode` и текст `Reads run freely; edits and commands ask.` со ссылкой на «Settings › Agents & modes» (без `web access` артборда: web-инструментов в сборке нет, design.md D9);
- настраиваемый агент с другим режимом — `New sessions start in <mode> mode` с пометкой `Your config sets this; the table above describes standard mode.`;
- профиль по умолчанию — внешний агент — `Your default connection is an external agent. It applies its own rules; approvals still appear in the conversation.`

#### Scenario: Режим по умолчанию
- **WHEN** `CODELAB_HOME` пуст
- **THEN** InfoBar — `New sessions start in standard mode`

#### Scenario: Настройки не прочитаны
- **WHEN** чтение фактов завершилось ошибкой или таймаутом, а `~/.codelab/config.yaml` задаёт `permissions.mode: bypass`
- **THEN** InfoBar шага — `Agent settings could not be read. The mode for new sessions is shown in Settings › Agents & modes.`, текста `New sessions start in standard mode` на шаге нет

#### Scenario: Настройки ещё читаются
- **WHEN** пользователь открыл шаг «Permissions», а чтение фактов ещё идёт
- **THEN** InfoBar режима нет, показан индикатор `Reading the agent settings…`; после чтения он заменяется InfoBar по действующему режиму

#### Scenario: Режим из общего с CLI конфига
- **WHEN** `~/.codelab/config.yaml` задаёт `permissions.mode: bypass`
- **THEN** InfoBar называет `bypass` и содержит `the table above describes standard mode`

### Requirement: Пропуск шага выбора модели
При создании onboarding SHALL один раз читать факты для шагов через порт `OnboardingProbe` с таймаутом 5 с (design.md change `add-app-onboarding`, D6). Доступ к настройкам SHALL определяться по профилю по умолчанию (`DefaultProfileResolver`, `resolveSettingsAccess` моста `codelab_setup`) без папки проекта: снимок конфига SHALL читаться с той же рабочей папкой, что у мастера провайдера (`CODELAB_HOME` доступа), поэтому проектный слой папки процесса в него НЕ SHALL попадать. Для `EditableSettings` готовность SHALL вычислять функция моста `checkProviderReadiness` (spec client-agent-setup «Готовность провайдера»); значения ключей НЕ SHALL читаться.

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

#### Scenario: Конфиг папки процесса не учитывается
- **WHEN** `CODELAB_HOME` пуст, а в папке, из которой запущен app, лежит `.codelab/config.yaml` с готовым провайдером
- **THEN** шаг «Choose a model» показан (`NoProviderConfigured`), а не пропущен

#### Scenario: Медленное хранилище
- **WHEN** чтение фактов не завершается за 5 с, и пользователь на шаге «Permissions» нажимает «Next»
- **THEN** через 5 с от начала чтения показан шаг «Choose a model» с пояснением `Agent settings could not be read.`, журнал содержит `onboarding.facts_unavailable` с `timeout: true`; результат чтения, пришедший позже, шаг не меняет

### Requirement: Шаг «Choose a model» и мастер провайдера
Шаг SHALL показывать заголовок `Choose where the model runs`, карточки пресетов (ключи `onboarding-preset-<id>`) из той же таблицы, что шаг «API type» мастера, с подписями мастера, и кнопку «Set up <preset>…» (`onboarding-model-setup`) для выбранной карточки. Кнопка SHALL открывать `ProviderWizardDialog` (spec app-settings «Мастер провайдера в app») по тому же доступу к настройкам (`EditableSettings`), по которому прочитаны факты шага, с целью `user`, неснимаемым «Make default», без «This project only», с `entry: onboarding` и уже выбранным пресетом: первым показанным шагом диалога SHALL быть «Base URL» (design.md change `add-app-onboarding`, D8, D11).

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

Пока мастер открывается или открыт, «Back», «Next», «Set up later» и повторное «Set up <preset>…» НЕ SHALL действовать. Если к моменту, когда мастер готов к показу, шаг уже не «Choose a model» или onboarding закрыт, диалог НЕ SHALL показываться и ничего НЕ SHALL записываться (design.md change `add-app-onboarding`, D8, ревью п. 6).

#### Scenario: Мастер и конфиг stdio-профиля
- **WHEN** профиль по умолчанию — stdio-профиль `codelab-agent` с `CODELAB_HOME=/tmp/agent-home` в `env`, конфиг там пуст, и пользователь сохраняет провайдера в мастере шага «Choose a model»
- **THEN** провайдер записан в `/tmp/agent-home/config.yaml`, а конфиг встроенного агента app не изменён

#### Scenario: Навигация во время открытия мастера
- **WHEN** пользователь нажал «Set up <preset>…», и пока мастер открывается (хранилище секретов отвечает медленно), нажимает «Set up later»
- **THEN** шаг остаётся «Choose a model»; после открытия показан диалог мастера; «Set up later» снова действует после закрытия диалога

#### Scenario: Мастер не показывается вне шага модели
- **WHEN** открыватель мастера возвращает Cubit мастера после того, как onboarding закрыт
- **THEN** диалога нет, Cubit мастера закрыт, файлы конфига и хранилище секретов не изменены

#### Scenario: Отмена мастера
- **WHEN** пользователь открывает мастер на шаге «Choose a model» и нажимает Cancel на шаге ключа
- **THEN** шаг остаётся на выборе пресета, «Next» нет, «Set up later» доступна, файлы не изменены

#### Scenario: Битый конфиг
- **WHEN** `config.yaml` содержит `budget.max_steps: 0`
- **THEN** шаг показывает InfoBar с подсказкой `codelab config check`, «Set up <preset>…» неактивна, после «Set up later» и завершения onboarding `config.yaml` побайтно не изменился

#### Scenario: Итог мастера при битом конфиге не принимается
- **WHEN** шаг «Choose a model» показан с пояснением о битом конфиге или о непрочитанных настройках, и onboarding всё же получает итог `ConfigSaved` мастера
- **THEN** шаг остаётся в прежнем состоянии с пояснением, сводки `is connected` и «Next» нет, журнал не содержит `onboarding.model_saved`

#### Scenario: Ключ не найден
- **WHEN** `config.yaml` задаёт провайдера `openai` с `api_key_secret: codelab/openai`, а секрета нет
- **THEN** InfoBar называет `openai`, `codelab/openai` и `Settings › Providers › Edit`, карточки доступны

### Requirement: Шаг «Privacy»
Шаг SHALL показывать заголовок `What leaves this computer`, текст `Only what the agent needs for the work you ask for, sent to services you set up or to addresses you choose to open. CodeLab itself collects nothing. The privacy policy lists every request.` (design.md change `add-app-onboarding`, D9) и строки по артборду 07a:
- «Your model provider» — `Every turn`;
- «MCP servers» — `Each session`, текст `Client information, the tool list request and the headers from your configuration, including tokens, each time a session starts or reconnects; the arguments of every tool call`; строк и пометок о web-инструментах НЕ SHALL быть, пока их нет в сборке. Тексты строк сети и вводной SHALL соответствовать `PRIVACY.md` §2 сборки (design.md change `add-app-onboarding`, D9);
- «Telemetry, crash reports, usage analytics» — `Never`;
- «Stays here» — `Local`.

Текст строки «Stays here» SHALL строиться по фактам сборки, а не по артборду (design.md change `add-app-onboarding`, D9): каталог конфига и сессий (`CODELAB_HOME` с `~` вместо домашнего каталога), каталог логов app (известен без чтения фактов и SHALL показываться всегда, в том числе при недоступных фактах) и способ хранения ключей по `id` бэкенда секретов. Шаг НЕ SHALL называть системную связку ключей, если бэкенд — не хранилище ОС.

Шаг НЕ SHALL просить принять условия и НЕ SHALL записывать согласие ни в `shared_preferences`, ни в файлы (D-29, §12.7.7а). InfoBar — `Nothing to agree to` с текстом `These links open the documents inside the app and work offline; Back returns to this step. You can find them later in Settings › Legal.`

Шаг SHALL показывать ссылки «Read the privacy policy» (`onboarding-privacy-policy`) и «Terms of use» (`onboarding-terms-of-use`) (design.md change `add-app-onboarding`, D10). Ссылка SHALL открывать поверх шага, внутри экрана onboarding, просмотр документа: кнопку «Back to setup» (`onboarding-document-back`) и содержимое страницы «Legal» (spec app-settings «Страница «Legal»: видимость и вкладки») на вкладке «Privacy policy» или «Terms of use» соответственно — те же ресурсы `assets/legal/`, язык документа по языку интерфейса, без сети. Навигация app НЕ SHALL уходить с `OnboardingDestination`, настройки НЕ SHALL открываться. «Back to setup», Esc и системный «назад» SHALL закрывать просмотр и возвращать шаг «Privacy» с прежним состоянием onboarding (шаг модели, сводка провайдера, факты); фокус SHALL возвращаться на ссылку, открывшую просмотр, а при открытии — на «Back to setup». Пока просмотр открыт, кнопки шага НЕ SHALL действовать. Журнал SHALL содержать `onboarding.document_opened {tab}` и `onboarding.document_closed {tab}` без путей и текстов.

#### Scenario: Ключи из переменных окружения
- **WHEN** бэкенд секретов — `env`, `CODELAB_HOME` — `~/.codelab`
- **THEN** строка «Stays here» содержит `~/.codelab`, каталог логов app и `API keys are read from environment variables`, и не содержит `keychain`

#### Scenario: Факты недоступны
- **WHEN** чтение фактов завершилось таймаутом
- **THEN** строка «Stays here» содержит подпись каталога логов app и `the agent's config and keys stay on this computer`, но не путь `CODELAB_HOME`

#### Scenario: Ключи в файле
- **WHEN** бэкенд секретов — `file`
- **THEN** строка «Stays here» содержит `secrets.yaml` и `unencrypted`

#### Scenario: Нечего принимать
- **WHEN** пользователь проходит шаг «Privacy», нажимает «Next», затем на шаге «Open a project» — «Skip for now»
- **THEN** на шаге «Privacy» нет флажка или кнопки согласия; после завершения в `shared_preferences` новых ключей, кроме `codelab.app.onboarding_done`, нет

#### Scenario: Политика внутри onboarding и возврат
- **WHEN** пользователь сохранил провайдера на шаге «Choose a model», перешёл на «Privacy» и нажимает «Read the privacy policy», затем «Back to setup»
- **THEN** сначала показан текст `assets/legal/PRIVACY.md` с выбранной вкладкой «Privacy policy», назначение навигации — `OnboardingDestination`; после «Back to setup» показан шаг «Privacy», после «Back» на нём — шаг «Choose a model» со сводкой сохранённого провайдера; фокус после закрытия — на `onboarding-privacy-policy`

#### Scenario: Условия на русском и Esc
- **WHEN** язык интерфейса — `ru`, пользователь нажимает «Terms of use», затем Esc
- **THEN** показан текст `assets/legal/TERMS.ru.md` на вкладке «Terms of use», а Esc вернул шаг «Privacy»; журнал содержит `onboarding.document_opened` с `tab: terms_of_use` и `onboarding.document_closed`, без путей ресурсов

#### Scenario: Кнопки шага под документом
- **WHEN** просмотр документа открыт, и пользователь нажимает Enter или Cmd/Ctrl+,
- **THEN** «Next» не сработала, шаг «Open a project» не показан, флаг не записан, настройки не открыты

#### Scenario: Нет строки о web-инструментах
- **WHEN** показан шаг «Privacy»
- **THEN** строка «MCP servers» не содержит `web`, `URL` и `search query`

#### Scenario: MCP-серверы на каждой сессии
- **WHEN** показан шаг «Privacy»
- **THEN** строка «MCP servers» имеет тег `Each session` и называет `tool list request`, `headers from your configuration` и `including tokens`; тега `When used` на шаге нет

#### Scenario: Вводная не обещает лишнего
- **WHEN** показан шаг «Privacy» на английском, затем на русском
- **THEN** вводный текст содержит `addresses you choose to open` и `The privacy policy lists every request`, текста `and only to services you set up.` нет; русский текст взят из ARB `ru` по глоссарию

### Requirement: Завершение onboarding и старт рабочего места
Пока показан onboarding, app НЕ SHALL строить рабочее место и НЕ SHALL запускать агента окна, в том числе для проекта, восстановленного из снимка прошлого запуска, и для папки, выбранной на шаге «Open a project» (design.md change `add-app-onboarding`, D5; design.md change `add-onboarding-project-step`, D2, D5).

Onboarding SHALL завершаться только на шаге «Open a project» одним из действий: принятой папкой (системный диалог, бросок, недавний проект), `Continue in <folder name>` или `Skip for now`. Завершение SHALL выполняться в порядке:
1. выбор принят: папка уже выбранный проект (для `Continue…` — восстановленный, для `Skip for now` — без выбора);
2. запись `codelab.app.onboarding_done: true`;
3. событие `onboarding.completed` и перевод навигации на рабочее место;
4. триггер старта при запуске (spec agent-workbench-ui «Агент стартует сам», триггер 1) ровно один раз: агент стартует в выбранном проекте, а без проекта не стартует.

Флаг НЕ SHALL записываться, если выбор не принят (отмена или сбой диалога, отказ броска). Повторное действие во время записи НЕ SHALL давать второй записи и второго перехода. Если onboarding закрыт, пока флаг пишется, перехода и событий после закрытия НЕ SHALL быть; папка, выбранная до записи, остаётся выбранным проектом и в снимке. Сбой записи флага SHALL давать событие `onboarding.save_failed` с именем типа ошибки и НЕ SHALL мешать переходу на рабочее место. Сбой старта агента после перехода показывается рабочим местом и onboarding не возвращает.

#### Scenario: Проект восстановлен, агент ждёт конца onboarding
- **WHEN** снимок прошлого запуска содержит проект `/work/app`, флага нет, и пользователь проходит onboarding с сохранением провайдера и нажимает `Continue in app`
- **THEN** до `Continue in app` открыватель встроенного агента не вызывался; после — вызван один раз с папкой `/work/app`, баннера «Add provider» нет

#### Scenario: Папка с шага стартует агента после перехода
- **WHEN** флага нет, пользователь сохранил провайдера и на шаге «Open a project» выбирает `/work/app`
- **THEN** пока показан onboarding, открыватель встроенного агента не вызывается; запись флага начинается после того, как `/work/app` стал выбранным проектом; после перехода на рабочее место открыватель вызван ровно один раз с папкой `/work/app`

#### Scenario: Закрытие во время записи флага
- **WHEN** пользователь выбрал `/work/app` на шаге «Open a project», запись флага ещё идёт, и onboarding закрывается (закрытие root scope)
- **THEN** навигация не меняется и не получает `emit` после закрытия, `onboarding.completed` не записано, исключений нет, агент не запущен

#### Scenario: Двойное нажатие
- **WHEN** пользователь дважды быстро нажимает `Skip for now`
- **THEN** флаг записан один раз, триггер старта вызван один раз, журнал содержит одно `onboarding.completed`

#### Scenario: Флаг не записался
- **WHEN** пользователь выбирает `/work/app` на шаге «Open a project», и запись `shared_preferences` бросает исключение
- **THEN** app показывает рабочее место с проектом `/work/app` и стартует агента в нём, журнал содержит `onboarding.save_failed` и `onboarding.completed`; при следующем запуске onboarding показан снова

#### Scenario: Выбор не принят — флаг не пишется
- **WHEN** на шаге «Open a project» диалог выбора папки бросает исключение платформы
- **THEN** показан тот же шаг, флаг не записан, диагностика содержит `Failed to open the folder picker.`, журнал содержит `project.picker_failed` без текста ошибки

#### Scenario: Значение model_step
- **WHEN** пользователь завершает onboarding трижды на чистых данных: при готовом провайдере; после сохранения провайдера; после «Set up later» при битом конфиге
- **THEN** `onboarding.completed` содержит `model_step` соответственно `skipped`, `saved`, `later`

### Requirement: Локализация и доступность onboarding
Все тексты onboarding SHALL браться из каталогов ARB `en` и `ru` (spec app-settings «Локализация интерфейса app»). Имена пресетов, id провайдеров и моделей, `id` бэкенда, имена переменных и секретов, пути и имена режимов SHALL показываться как есть. Строка шагов SHALL объявлять список шагов и текущий шаг для экранного диктора. При показе шага фокус SHALL переходить на его заголовок. Контент SHALL быть не шире 920 px; при окне уже 900 px он SHALL прокручиваться по вертикали без обрезки кнопок.

#### Scenario: Русский интерфейс
- **WHEN** язык app — `ru`, и показан шаг «Privacy» при бэкенде `file`
- **THEN** заголовок и строки — из ARB `ru`, а `secrets.yaml` и `~/.codelab` показаны без перевода

#### Scenario: Узкое окно
- **WHEN** окно 760 × 600 px на шаге «Choose a model»
- **THEN** кнопки «Back» и «Set up later» достижимы прокруткой, переполнения нет

### Requirement: События журнала onboarding без секретов и путей
Onboarding SHALL писать события логгера `codelab_desktop.onboarding` из таблиц design.md change `add-app-onboarding`, D13, и design.md change `add-onboarding-project-step`, D8. Событие `onboarding.completed` SHALL содержать поле `project` со значением `picker`, `drop`, `recent`, `restored` или `skipped`. События НЕ SHALL содержать пути, имена папок проекта, имена секретов и переменных, адреса, id моделей, значения ключей и тексты исключений (только имя типа). События мастера SHALL писать мост (`provider_wizard.*`); onboarding их НЕ SHALL дублировать. События выбора проекта (`project.drop`, `project.picker_failed`, `project.start_held`) SHALL писать application рабочего места; onboarding их НЕ SHALL дублировать.

#### Scenario: Полный проход без утечек
- **WHEN** пользователь проходит onboarding с мастером, ключом `sk-test-leak-0123456789` и `CODELAB_HOME` `/tmp/codelab-home-marker` и на шаге «Open a project» бросает папку `/tmp/codelab-project-marker`
- **THEN** журнал содержит `onboarding.shown`, `onboarding.model_saved`, `onboarding.completed {model_step: saved, project: drop}`, а `sk-test-leak-0123456789`, `codelab-home-marker` и `codelab-project-marker` в событиях `onboarding.*` и `project.*` нет

### Requirement: Шаг «Open a project»
Пятый шаг onboarding (`onboarding-step-project`) SHALL предлагать выбрать папку проекта до перехода на рабочее место (design.md change `add-onboarding-project-step`, D1–D7). Сверху вниз шаг SHALL показывать:
1. заголовок `Open a project`; при показе шага фокус SHALL переходить на него;
2. пояснение, зависящее от профиля окна, — те же три текста, что на экране без проекта (spec agent-workbench-ui «Экран без выбранного проекта», п. 2): фраза `The agent can't read or write outside it.` SHALL показываться только для встроенного агента;
3. если проект прошлого запуска восстановлен (выбранный проект не пуст) — строку `Last project: <folder name>` с путём папки (ключ `onboarding-project-last`);
4. кнопку `Open folder…` (ключ `start-open-project`) с подсказкой сочетания Cmd/Ctrl+O для платформы; кнопка открывает системный выбор папки;
5. зону перетаскивания (ключ `open-project-drop-zone`) с текстами `Drop a folder here to open it` и `Files are not accepted — only a folder`;
6. карточку агента окна (ключ `open-project-agent`): имя профиля, строку транспорта и пояснение по правилам п. 5 требования «Экран без выбранного проекта» spec agent-workbench-ui, но без ссылки `Change in Settings › Connection`;
7. если есть недавние проекты, кроме восстановленного, — блок `Recent projects` (ключ `onboarding-project-recents`) с не более чем пятью записями в порядке недавних: имя папки и путь; запись SHALL иметь ключ `onboarding-project-recent-<i>`, где `<i>` — позиция записи в блоке, начиная с 0.

InfoBar `New session needs a folder` экрана без проекта на шаге НЕ SHALL показываться. Кнопки шага: «Back» (`onboarding-back`) ведёт на «Privacy»; если проект восстановлен — `Continue in <folder name>` (`onboarding-project-continue`), иначе — `Skip for now` (`onboarding-project-skip`). Кнопки «Next» на шаге нет.

Выбор папки на шаге SHALL проходить те же правила, что выбор на экране без проекта: системный диалог; бросок, принимаемый по требованию «Открытие папки перетаскиванием» spec agent-workbench-ui (ровно один элемент с локальным абсолютным путём к существующей папке; отказы `not_a_folder`, `multiple`, `missing`, `unsupported` с теми же текстами в зоне, той же диагностикой и событием `project.drop`); нажатие записи недавнего проекта — как выбор недавнего проекта в сайдбаре. Бросок SHALL приниматься в любой точке экрана onboarding, пока показан этот шаг; на других шагах onboarding бросок НЕ SHALL ничего делать. Решение о брошенных элементах SHALL принимать application, а не виджет.

Принятая папка SHALL становиться выбранным проектом (недавние проекты, снимок рабочего пространства, диагностика `Selected project: <path>`) и SHALL завершать onboarding по требованию «Завершение onboarding и старт рабочего места». Закрытый без выбора диалог, сбой диалога и отказ броска НЕ SHALL завершать onboarding, НЕ SHALL записывать флаг и SHALL оставлять шаг на месте. Пока выбор выполняется (диалог открыт, вид брошенного пути проверяется, выбирается недавний проект), «Back», `Skip for now`, `Continue in <folder name>`, записи недавних, повторный бросок и Cmd/Ctrl+O НЕ SHALL действовать.

Показ шага НЕ SHALL запускать агента, открывать транспорт и отправлять агенту сообщения. Тексты шага SHALL браться из каталогов ARB `en` и `ru`; имена папок, пути, имя профиля пользователя, команда и адрес показываются как есть.

#### Scenario: Новая установка
- **WHEN** onboarding показан, недавних проектов и проекта из снимка нет, профиль окна — встроенный агент, платформа — Linux, и пользователь доходит до шага «Open a project»
- **THEN** показаны заголовок `Open a project` с фокусом, пояснение с фразой `The agent can't read or write outside it.`, `Open folder…` с подсказкой `Ctrl+O`, зона `Drop a folder here to open it`, карточка `Embedded agent` без ссылки `Change in Settings › Connection`, кнопки «Back» и `Skip for now`; блока `Recent projects`, кнопки `Continue in …` и InfoBar `New session needs a folder` нет; открыватель встроенного агента не вызван

#### Scenario: Выбор папки в диалоге завершает onboarding
- **WHEN** на шаге «Open a project» пользователь нажимает `Open folder…` и выбирает `/work/app`
- **THEN** `/work/app` — выбранный проект и первый в недавних, ключ `codelab.app.onboarding_done` записан, назначение навигации — `WorkbenchDestination`, встроенный агент открыт ровно один раз с папкой `/work/app`, `session/new` не отправлен

#### Scenario: Отмена диалога
- **WHEN** на шаге «Open a project» пользователь нажимает Ctrl+O и закрывает системный диалог без выбора
- **THEN** показан тот же шаг, флаг не записан, проект не выбран, агент не запущен, журнал содержит `onboarding.project_pick_cancelled`

#### Scenario: Брошенная папка завершает onboarding
- **WHEN** на шаге «Open a project» пользователь бросает на экран папку `/work/app`
- **THEN** выбран проект `/work/app`, флаг записан, показано рабочее место, агент открыт ровно один раз с папкой `/work/app`, журнал содержит `project.drop` с `outcome: opened` и `onboarding.completed` с `project: drop`

#### Scenario: Брошенный файл не завершает onboarding
- **WHEN** на шаге «Open a project» пользователь бросает файл `/work/app/README.md`
- **THEN** показан тот же шаг, зона показывает `That's a file. Drop a folder to open it as a project.`, флаг не записан, проект не выбран, агент не запущен

#### Scenario: Несколько элементов
- **WHEN** на шаге «Open a project» пользователь бросает папки `/work/a` и `/work/b`
- **THEN** показан тот же шаг, зона показывает `Drop one folder at a time.`, флаг не записан, ни одна папка не выбрана

#### Scenario: Бросок на другом шаге
- **WHEN** показан шаг «Privacy», и пользователь бросает на окно папку `/work/app`
- **THEN** показан тот же шаг, проект не выбран, флаг не записан

#### Scenario: Недавний проект
- **WHEN** недавние проекты — `/work/a` и `/work/b`, проект из снимка не восстановлен (настройка «Reopen last project» выключена), и пользователь нажимает на шаге запись `b`
- **THEN** выбран проект `/work/b`, флаг записан, показано рабочее место, журнал содержит `onboarding.completed` с `project: recent`

#### Scenario: Не более пяти недавних
- **WHEN** недавних проектов семь, проект из снимка не восстановлен
- **THEN** блок `Recent projects` показывает пять первых записей с ключами `onboarding-project-recent-0` … `onboarding-project-recent-4`, записи `onboarding-project-recent-5` нет

#### Scenario: Проект восстановлен из снимка
- **WHEN** флага нет, снимок прошлого запуска содержит существующую папку `/work/app`, и пользователь доходит до шага «Open a project»
- **THEN** шаг показывает `Last project: app` с путём `/work/app` и кнопку `Continue in app`, кнопки `Skip for now` нет, записи `/work/app` в блоке `Recent projects` нет; агент не запущен

#### Scenario: Продолжить с восстановленным проектом
- **WHEN** на шаге показан `Continue in app` для восстановленного `/work/app`, и пользователь нажимает его
- **THEN** флаг записан, показано рабочее место, агент открыт ровно один раз с папкой `/work/app`, журнал содержит `onboarding.completed` с `project: restored`

#### Scenario: Другая папка при восстановленном проекте
- **WHEN** на шаге показан `Continue in app` для восстановленного `/work/app`, и пользователь выбирает в диалоге `/work/other`
- **THEN** выбран проект `/work/other`, агент открыт ровно один раз с папкой `/work/other` и ни разу с `/work/app`

#### Scenario: Пропуск шага
- **WHEN** проекта нет, и пользователь нажимает `Skip for now`
- **THEN** флаг записан, показано рабочее место с экраном `open-project-screen`, агент не запущен, журнал содержит `onboarding.completed` с `project: skipped`

#### Scenario: Пропуск при незавершённом восстановлении
- **WHEN** чтение снимка с проектом `/work/app` ещё идёт, и пользователь нажимает `Skip for now`
- **THEN** флаг записан, показано рабочее место; когда восстановление завершается не позже 2 с после перехода, агент стартует в `/work/app` ровно один раз, как при обычном запуске

#### Scenario: Навигация во время выбора
- **WHEN** системный диалог, открытый кнопкой `Open folder…`, ещё открыт, и пользователь нажимает «Back», `Skip for now` и Ctrl+O
- **THEN** шаг не меняется, флаг не записан, порт выбора папки вызван один раз

#### Scenario: Сочетание на других шагах
- **WHEN** показан шаг «Permissions», и пользователь нажимает Ctrl+O
- **THEN** выбор папки не открывается, проект не меняется

#### Scenario: Внешний профиль
- **WHEN** профиль окна — stdio-профиль `dev` с командой `/usr/local/bin/codelab-agent` и аргументами `serve --stdio --token abc`, и показан шаг «Open a project»
- **THEN** карточка показывает `dev` и `stdio · /usr/local/bin/codelab-agent · profile of this window`, текста `--token` и `abc` на экране нет, пояснение заканчивается фразой `An external agent applies its own rules to files outside it.`

#### Scenario: Русский интерфейс и низкое окно
- **WHEN** язык app — `ru`, тема — тёмная, окно 800 × 600 px, недавних проектов пять, и показан шаг «Open a project»
- **THEN** тексты шага — из ARB `ru`, пути и имена папок без перевода, переполнения нет, `Open folder…`, все записи недавних, «Back» и `Skip for now` достижимы прокруткой

