## MODIFIED Requirements

### Requirement: Состав моста codelab_setup для настройки агента
Мост `packages/dart/codelab_setup` SHALL давать клиентам логику настройки Dart-агента, общую для codelab-app и CLI (`dart-agent-and-clients` §12.4.2; design.md change `add-provider-setup-ui`, D2; design.md change `add-app-skills-page`, D4).

**Основной барель** `codelab_setup.dart` (чистый Dart, web-безопасно):
- `SecretValue`;
- `SettingsAccess` и `resolveSettingsAccess`;
- порт `AgentConfigStore`, `AgentConfigSnapshot`, `ConfigSaveOutcome`;
- модели представления `ProviderEntryView`, `KeyStatusView`, `McpServerEntryView`, `SettingFieldView`;
- `McpServerDraft`;
- `ProviderPreset` и таблица пресетов;
- `ProviderSetupFlow` с состояниями и событиями, `ProviderSetupPlan`, `ProviderSetupCommitter`;
- порт `ProviderCheck`, `HttpProviderCheck`;
- `ProviderReadiness` и `checkProviderReadiness`;
- вид расширений агента `AgentExtensionsView` (`ContextFileView`, `SkillEntryView`, `TemplateEntryView`, кандидаты согласия) с построителем `agentExtensionsOf` и правило записи `skillsListEdit` для `skills.disabled` и `skills.extra_roots`;
- реэкспорт чистых типов ядра `ConfigLayer`, `ConfigTarget`, `ConfigSnapshot`, `ConfigEdit` с подклассами, `ConfigConflictException`, `SettingsRegistry`, `SettingDescriptor`, `SettingScope`, `SettingType`, `SecretNames`, `SecretBackendInfo`, `ExtensionScope`, `ExtensionDiagnostic`, `DiagnosticLevel`.

**`io.dart`:**
- `FileAgentConfigStore`;
- `ClientSecretAccess` (spec agent-secrets «Клиентский доступ к секретам»);
- `ioProviderCheck()`;
- `readAgentExtensions` — чтение файлов проекта и навыков папки для вида расширений.

Клиенты НЕ SHALL реализовывать шаги мастера, проверку `/models`, порядок записи, правила корней, доверия и перекрытия навыков и правила записи списков `skills.*` сами (SETUP-8).

#### Scenario: Один автомат для двух клиентов
- **WHEN** тесты app и CLI проводят мастер одними и теми же событиями над фейковыми `ProviderCheck` и `AgentConfigStore`
- **THEN** последовательности состояний и списки `ConfigEdit` совпадают

#### Scenario: Основной барель собирается для web
- **WHEN** выполняется `melos run web-compile`
- **THEN** основной барель `codelab_setup`, включая `AgentExtensionsView` и `agentExtensionsOf`, компилируется без `dart:io`

## ADDED Requirements

### Requirement: Обзор расширений агента
`readAgentExtensions(snapshot, {codelabHome, environment})` (`io.dart`) SHALL строить `AgentExtensionsView` для папки снимка так, как её увидит сессия агента (design.md change `add-app-skills-page`, D3, D4):
- каноническая папка, доверие (`realpath` против `trusted_projects` конфигурации снимка, fail-closed) и чтение файлов проекта и навыков SHALL выполняться той же функцией `codelab_agent_io`, что у `config check`: один `ProjectFilesLoader`, две фазы параллельно, у каждой таймаут 5 с и своя отмена; фаза навыков — только при `skills.enabled`;
- навыки SHALL строиться `parseSkills` ядра с `skills.*` и правилами разрешений конфигурации снимка; строки выключенных `skills.disabled` навыков SHALL добавляться победителями по имени без учёта `skills.disabled`, с признаком `disabled`;
- перекрытие SHALL определяться по диагностикам `shadowed` ядра без разбора их текста; признак «модели недоступен» — по `SkillCatalog.modelVisible`;
- источник навыка SHALL определяться по номеру корня тем же списком корней, что у загрузчика;
- цепочка контекста SHALL идти в порядке загрузчика; усечение и пропуск по бюджету SHALL считаться `assembleProjectContext` ядра; путь на диске — от `$CODELAB_HOME` или корня обхода;
- шаблоны SHALL строиться `parseCommandTemplates` ядра;
- диагностики уровня `error`/`warning` SHALL относиться к строке навыка по пути его `SKILL.md`, остальные — к разделу; `info` SHALL отбрасываться, кроме признака `untrusted_project`;
- исход фазы (таймаут, исключение — имя типа) SHALL быть значением вида, а не исключением.

Вид НЕ SHALL содержать текстов `AGENTS.md`, тел навыков и шаблонов ни в полях, ни в `toString()` (SETUP-25); исключение — описание шаблона без `description` во frontmatter, которым служит первая строка тела, как в `available_commands_update` агента. Сбой подготовки чтения SHALL давать исход «сбой» с именем типа у обеих фаз. `ConfigCommands.check` SHALL использовать ту же функцию `codelab_agent_io`, вывод `config check` НЕ SHALL меняться.

#### Scenario: Вид совпадает с каталогом сессии
- **WHEN** доверенный проект содержит навыки в `.codelab/skills` и `.agents/skills`, у пользователя есть `~/.agents/skills`, а `skills.disabled: [b]`
- **THEN** включённые строки вида совпадают по именам с `SkillCatalog.skills`, который рантайм построит для сессии этой папки, а `b` присутствует с признаком `disabled`

#### Scenario: Недоверенный проект
- **WHEN** папка не в `trusted_projects`
- **THEN** вид имеет `trusted: false`, навыков и шаблонов проекта нет, цепочка `AGENTS.md` проекта есть

#### Scenario: Таймаут фазы навыков
- **WHEN** порт навыков не отвечает 5 с
- **THEN** вид содержит исход «не прочитано за 5 с» для навыков и полную цепочку контекста и шаблоны

#### Scenario: config check не меняется
- **WHEN** `codelab-agent config check` запускается на наборе папок тестов `config_check_skills_test.dart` и тестов файлов проекта до и после правки
- **THEN** вывод совпадает построчно

#### Scenario: Тела не попадают в вид
- **WHEN** тела `SKILL.md`, шаблона и `AGENTS.md` содержат маркер `sk-test-leak-0123456789`
- **THEN** `toString()` вида и всех строк не содержит маркера

### Requirement: Правила записи skills.disabled и skills.extra_roots
`skillsListEdit(snapshot, key, element, {required bool present})` SHALL давать план записи `SkillsListPlan(layer, base, edits)` или отказ `SkillsListRefused(refusal)` для ключей `skills.disabled` и `skills.extra_roots`; `present: true` — элемент должен оказаться в списке, `false` — выйти из него (design.md change `add-app-skills-page`, D5). Другой ключ SHALL давать `ArgumentError`. `base` SHALL быть снимком целевого слоя из `snapshot.layers`, вызывающий записывает `apply(base, edits)`. Правила:
1. цель — самый верхний слой, чьё значение ключа действует (`origins` итога загрузки: значение, отброшенное правилами доверия, источником не считается; список `skills.disabled` недоверенного проекта объединяется с нижними слоями и их не заменяет, поэтому такой слой при выборе цели не учитывается), если он `user` или `projectLocal`; если ключ не задан нигде — `user` (решения Q2 (а), Q3 (а) design.md);
2. если верхний слой — `project`, файл `--config` или окружение, результат SHALL быть отказом `SkillsListNotEditable(<источник>)`;
3. новое значение — сырой список целевого слоя плюс или минус элемент, порядок сохраняется, дублей нет; одна правка `SetValue`, пустой список — `UnsetValue`; если элемент уже в нужном состоянии, план SHALL иметь пустой `edits`;
4. включить имя, выключенное `skills.disabled` недоверенного проекта (по сырому значению его слоёв), SHALL нельзя: отказ `SkillsListDisabledByProject(<источник>)`;
5. `skills.extra_roots` НЕ SHALL писаться в слой `project`, а в `projectLocal` — только для доверенного проекта; выдача согласия (`present: true`) на относительный элемент недоверенного проекта SHALL давать отказ `SkillsListUntrustedProject`, а отзыв (`present: false`) SHALL быть разрешён.

Состояние выключателей вида (`SkillToggle` у `SkillEntryView` и `SkillConsentView`) SHALL вычисляться этой же функцией.

Цели записи SHALL быть только `ConfigTarget.user()` и `ConfigTarget.projectLocal(cwd)` (SETUP-3).

#### Scenario: Ключ не задан
- **WHEN** `skills.disabled` нет ни в одном слое, и выключается `x`
- **THEN** результат — `SetValue('skills.disabled', ['x'])` с целью `user`

#### Scenario: Список в projectLocal
- **WHEN** `skills.disabled: [a]` в `projectLocal`, `[c]` в `user`, и выключается `b`
- **THEN** результат — `SetValue('skills.disabled', ['a', 'b'])` с целью `projectLocal`

#### Scenario: Последний элемент
- **WHEN** `skills.disabled: [a]` в `user`, и включается `a`
- **THEN** результат — `UnsetValue('skills.disabled')` с целью `user`

#### Scenario: Ключ из --config
- **WHEN** `skills.extra_roots` задан в файле `--config`
- **THEN** результат — `SkillsListRefused(SkillsListNotEditable(<путь файла>))`, правок нет

#### Scenario: extra_roots не уходит в проектный слой
- **WHEN** `skills.extra_roots` задан только в `.codelab/config.yaml` проекта (агент его отбрасывает), и даётся согласие на `.claude/skills`
- **THEN** правка идёт в `user`, слой `project` не меняется

#### Scenario: Повторное выключение
- **WHEN** `skills.disabled: [a]` в `user`, и снова выключается `a`
- **THEN** результат — `SkillsListPlan` с целью `user` и пустым `edits`

#### Scenario: Отзыв согласия в недоверенном проекте
- **WHEN** проект недоверенный; для снимка с `skills.extra_roots: [.claude/skills]` в `user` вызывается `present: false`, а для снимка без `skills.extra_roots` — `present: true` с элементом `.claude/skills`
- **THEN** первый вызов — `SkillsListPlan` с целью `user` и `UnsetValue('skills.extra_roots')`; второй — `SkillsListRefused(SkillsListUntrustedProject())`

#### Scenario: Неизвестный ключ
- **WHEN** `skillsListEdit` вызывается с ключом `skills.max_skills`
- **THEN** вызов бросает `ArgumentError`
