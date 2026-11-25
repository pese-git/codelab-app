## MODIFIED Requirements

### Requirement: Шаг «Privacy»
Шаг SHALL показывать заголовок `What leaves this computer`, текст `Only what the agent needs for the work you ask for, sent to services you set up or to addresses you choose to open. CodeLab itself collects nothing. The privacy policy lists every request.` (design.md change `add-app-onboarding`, D9) и строки по артборду 07a:
- «Your model provider» — `Every turn`;
- «MCP servers» — `Each session`, текст `Client information, the tool list request and the headers from your configuration, including tokens, each time a session starts or reconnects; the arguments of every tool call`; строк и пометок о web-инструментах НЕ SHALL быть, пока их нет в сборке. Тексты строк сети и вводной SHALL соответствовать `PRIVACY.md` §2 сборки (design.md change `add-app-onboarding`, D9);
- «Telemetry, crash reports, usage analytics» — `Never`;
- «Stays here» — `Local`.

Текст строки «Stays here» SHALL строиться по фактам сборки, а не по артборду (design.md change `add-app-onboarding`, D9): каталог конфига и сессий (`CODELAB_HOME` с `~` вместо домашнего каталога), каталог логов app (известен без чтения фактов и SHALL показываться всегда, в том числе при недоступных фактах) и способ хранения ключей по `id` бэкенда секретов. Шаг НЕ SHALL называть системную связку ключей, если бэкенд — не хранилище ОС.

Шаг НЕ SHALL просить принять условия и НЕ SHALL записывать принятие условий или политики ни в `shared_preferences`, ни в файлы (D-29, §12.7.7а). Разрешение на передачу данных получателю (требование «Разрешение на передачу данных на шаге «Privacy»»; spec app-data-sharing) — не принятие документов. InfoBar — `Nothing to accept in these documents` с текстом `These links open the documents inside the app and work offline; Back returns to this step. You can find them later in Settings › Legal.`

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
- **WHEN** готовность — `NoProviderConfigured`, пользователь нажимает «Set up later», проходит шаг «Privacy» кнопкой «Next», затем на шаге «Open a project» — «Skip for now»
- **THEN** на шаге «Privacy» нет флажка или кнопки принятия условий и нет `onboarding-privacy-allow`; InfoBar называется `Nothing to accept in these documents`; после завершения в `shared_preferences` новых ключей, кроме `codelab.app.onboarding_done`, нет

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

### Requirement: События журнала onboarding без секретов и путей
Onboarding SHALL писать события логгера `codelab_desktop.onboarding` из таблиц design.md change `add-app-onboarding`, D13, и design.md change `add-onboarding-project-step`, D8. Событие `onboarding.completed` SHALL содержать поле `project` со значением `picker`, `drop`, `recent`, `restored` или `skipped` и поле `sharing` со значением `allowed`, `not_now`, `already_allowed`, `local` или `not_asked` (design.md change `add-ai-data-sharing-consent`, D13). Событие выдачи разрешения (`data_sharing.allowed {from: onboarding}`) SHALL писать `DataSharingCubit`; onboarding его НЕ SHALL дублировать. События НЕ SHALL содержать пути, имена папок проекта, имена секретов и переменных, адреса, id моделей, значения ключей и тексты исключений (только имя типа). События мастера SHALL писать мост (`provider_wizard.*`); onboarding их НЕ SHALL дублировать. События выбора проекта (`project.drop`, `project.picker_failed`, `project.start_held`) SHALL писать application рабочего места; onboarding их НЕ SHALL дублировать.

#### Scenario: Полный проход без утечек
- **WHEN** пользователь проходит onboarding с мастером, ключом `sk-test-leak-0123456789` и `CODELAB_HOME` `/tmp/codelab-home-marker`, на шаге «Privacy» нажимает `Not now` и на шаге «Open a project» бросает папку `/tmp/codelab-project-marker`
- **THEN** журнал содержит `onboarding.shown`, `onboarding.model_saved`, `onboarding.completed {model_step: saved, project: drop, sharing: not_now}`, а `sk-test-leak-0123456789`, `codelab-home-marker` и `codelab-project-marker` в событиях `onboarding.*` и `project.*` нет

## ADDED Requirements

### Requirement: Разрешение на передачу данных на шаге «Privacy»
Под строками шага «Privacy» SHALL стоять карточка `onboarding-privacy-sharing` с заголовком `Permission to send data` (design.md change `add-ai-data-sharing-consent`, D10, D12). При каждом показе шага onboarding SHALL заново читать кандидата через `OnboardingProbe.sharingCandidate()` с таймаутом 5 с; доступ к конфигу — тот же, что у требования «Пропуск шага выбора модели» (`CODELAB_HOME` без папки проекта); адрес провайдера даёт `defaultProviderEndpoint` моста `codelab_setup`. Результат чтения после ухода с шага или закрытия onboarding НЕ SHALL менять состояние.

Карточка по кандидату:
- чтение идёт — текст `Checking your model provider…`, кнопки `onboarding-privacy-allow` нет, `onboarding-next` подписана `Next`;
- удалённый провайдер модели по умолчанию или внешний профиль по умолчанию без действующего разрешения — текст `onboardingSharingProvider` (id провайдера и хост) или `onboardingSharingAgent` (метка профиля и цель), кнопки `Allow and continue` (`onboarding-privacy-allow`) и `Not now` (`onboarding-next`);
- действующее разрешение на этого получателя — `Allowed: {recipient}.` (`onboarding-privacy-allowed`) и `onboarding-next` с подписью `Next`;
- локальный провайдер (spec app-data-sharing «Модель на этом компьютере без вопроса») — текст `onboarding-privacy-local` с хостом, кнопки разрешения нет;
- провайдера нет, конфиг битый, чтение не удалось или не успело — текст `onboarding-privacy-ask-later`, кнопки разрешения нет.

`Allow and continue` SHALL выдавать разрешение через `DataSharingCubit` (запись `from: onboarding`) и переходить на шаг «Open a project»; сбой записи разрешения переход НЕ SHALL отменять (spec app-data-sharing «Хранение разрешений и версия раскрытия»). Повторное нажатие во время записи НЕ SHALL давать второй записи и второго перехода. `Not now` SHALL переходить без разрешения. Пока открыт просмотр документа (требование «Шаг «Privacy»»), `onboarding-privacy-allow` НЕ SHALL действовать, в том числе по Enter. Onboarding SHALL завершаться при любом выборе; агент во время onboarding по-прежнему не стартует.

#### Scenario: Разрешение на onboarding
- **WHEN** готовность — `ProviderReady(anthropic/claude)`, провайдер `anthropic` без `base_url`, и пользователь на шаге «Privacy» нажимает `Allow and continue`, затем на шаге «Open a project» — `Skip for now`
- **THEN** показан шаг «Open a project»; `codelab.app.data_sharing` содержит запись `anthropicMessages` / `api.anthropic.com` с `disclosure: 1`; журнал содержит `data_sharing.allowed {recipient: provider, from: onboarding}` и `onboarding.completed` с `sharing: allowed`; первый промпт после запуска агента уходит без диалога

#### Scenario: Не сейчас
- **WHEN** в той же ситуации пользователь нажимает `Not now`
- **THEN** показан шаг «Open a project», ключа `codelab.app.data_sharing` нет, `onboarding.completed` содержит `sharing: not_now`; первый промпт после старта агента показывает `data-sharing-dialog`

#### Scenario: Возврат после разрешения
- **WHEN** пользователь нажал `Allow and continue`, затем на шаге «Open a project» — «Back»
- **THEN** шаг «Privacy» показывает `onboarding-privacy-allowed` с `anthropic · api.anthropic.com` и кнопку `onboarding-next` с подписью `Next`, кнопки `onboarding-privacy-allow` нет

#### Scenario: Локальная модель на onboarding
- **WHEN** провайдер модели по умолчанию задаёт `base_url: http://localhost:11434/v1`
- **THEN** карточка показывает `onboarding-privacy-local` с `localhost:11434`, кнопки `onboarding-privacy-allow` нет, `onboarding.completed` содержит `sharing: local`

#### Scenario: Внешний агент по умолчанию
- **WHEN** профиль по умолчанию — `wss://agent.example.com/acp` с меткой `Remote`
- **THEN** карточка показывает `onboardingSharingAgent` с `Remote` и `agent.example.com`, конфиг агента не читается; `Allow and continue` записывает разрешение `agent` / `ws` / `agent.example.com`

#### Scenario: Медленное чтение кандидата
- **WHEN** чтение кандидата не завершается за 5 с
- **THEN** карточка показывает `onboarding-privacy-ask-later`, результат, пришедший позже, карточку не меняет

#### Scenario: Двойное нажатие разрешения
- **WHEN** пользователь дважды быстро нажимает `Allow and continue`
- **THEN** разрешение записано один раз, шаг «Open a project» показан один раз
