# Расширения агента

Глава описывает две подсистемы, которые обслуживают страницы приложения «Skills & extensions» и «Agents & modes»:

- **вид расширений** — цепочка инструкций `AGENTS.md`, навыки и шаблоны команд папки (`lib/src/extensions/`, `lib/src/io/agent_extensions_reader.dart`, `lib/src/io/extensions_host_paths.dart`);
- **таблица определений агентов** — встроенные типы субагентов и файлы `agents/*.md` (`lib/src/views/agent_definition_row_view.dart`, `lib/src/io/agent_definition_rows_at.dart`).

Правила самих навыков, шаблонов, корней, доверия и бюджета контекста принадлежат ядру ([файлы проекта и определения агентов](../../codelab_agent_core/doc/09-config-prompts-commands.md), [навыки](../../codelab_agent_core/doc/06-tools.md)). Мост вызывает те же функции ядра, что и сессия агента, и не заводит второй реализации (SETUP-8). Чтение с диска общее с `config check` — оно живёт в `codelab_agent_io` ([README](../../codelab_agent_io/README.md)).

Подсистемы использует только приложение: `skills_settings_cubit.dart`, `agents_modes_cubit.dart`, `agent_definitions_loader.dart`.

## Вид расширений: `AgentExtensionsView`

### Что в нём

Файл `agent_extensions_view.dart`. Вид содержит всё для показа и **не содержит текстов файлов** (SETUP-25): ни `AGENTS.md`, ни тел навыков и шаблонов — ни в полях, ни в `toString()`. `toString()` печатает только имена и числа. Исключение одно: описание шаблона без `description` во frontmatter — ядро берёт первую строку тела, а ту же строку агент и так отдаёт клиенту в `available_commands_update`.

| Раздел | Тип | Что внутри |
|---|---|---|
| `folder`, `trusted` | `String`, `bool` | канонический `cwd`; проект в `trusted_projects` (fail-closed) |
| `context` | `ContextChainView` | файлы цепочки `AGENTS.md` / `CLAUDE.md` в порядке агента (`ContextFileView`: путь для промпта, каталог для «Open», размеры, `truncated`, `omitted`, `isClaudeAlias`), `shownBytes`, число пропущенных и усечённых |
| `skills` | `SkillsSectionView` | строки `SkillEntryView`, предупреждения, кандидаты согласия `SkillConsentView` |
| `templates` | `TemplatesSectionView` | строки `TemplateEntryView` (`/<имя>`, подсказка, описание, путь, область), предупреждения |

Каждый раздел несёт исход чтения `SectionOutcome`. Он нужен, чтобы страница показала причину пустого раздела, а не молча пустой список:

| Исход | Смысл |
|---|---|
| `SectionRead` | прочитано |
| `SectionTimedOut` | фаза не уложилась в предел времени |
| `SectionFailed(errorType)` | исключение порта; только имя типа |
| `SectionOff(source)` | навыки выключены `skills.enabled: false`; `source` — файл, откуда ключ |

Имена, описания и подсказки — недоверенный текст из файлов. Клиент показывает их простым текстом, без markdown и ссылок.

### Строка навыка

`SkillEntryView` несёт: `name`, `description`, `argumentHint`, `invokeAs` (`/skill:<имя>[ <подсказка>]` или `null` у навыка без команды), `availability` (`enabled` или `disabled` через `skills.disabled`), `modelVisible`, `userInvocable`, `root` (`SkillRootView`: область, подпись, путь корня), `directory` (каталог с `SKILL.md`; имя во frontmatter может отличаться от имени каталога), `overrides` (перекрытые корни), `warnings`, `toggle`.

Для перевода подписей на язык клиента вид отдаёт данные, а не только английский текст: `overridesScope` (область перекрытого навыка) и `SkillRootView.extraEntry` (элемент `skills.extra_roots` как записан). `overridesLabel` и `label` остаются прежним английским текстом для терминала.

Поле `toggle` — `SkillToggle`: доступен переключатель или неактивен с причиной. Оно строится правилом `skillsListEdit` ниже, то есть вид и запись опираются на одну реализацию (D5 change `add-app-skills-page`).

### Построитель `agentExtensionsOf`

Файл `agent_extensions_of.dart`. Чистая функция основного барелья:

```dart
AgentExtensionsView agentExtensionsOf(
  AgentConfigSnapshot snapshot,
  ProjectExtensions extensions,   // прочитанные файлы, тип ядра
  {required String? userHome, List<SkillConsentView> consents = const []}
);
```

Что она делает:

1. Берёт `snapshot.loaded.config`; без него бросает `StateError('The config snapshot has no loaded configuration')`. Читаемый конфиг — предусловие.
2. Для файлов проекта вызывает `parseCommandTemplates` и `assembleProjectContext` ядра. Бюджет и усечение считает ядро, мост лишь сопоставляет результат с файлами по пути.
3. Для навыков вызывает `parseSkills` дважды: с `skills.disabled` и без него (`_withoutDisabled`). Второй вызов нужен, чтобы показать выключенные навыки с возможностью включить. Выключатель действует на все файлы с этим именем.
4. Раскладывает диагностики ядра: `error` и `warning` показанного навыка идут в его строку, остальные — в раздел; `info` не показываются (как в `config check`). Диагностики файла `AGENTS.md`, `CLAUDE.md` относятся к цепочке, каталога `prompts` — к шаблонам; каталог `agents` на странице не показывается.

Функция принимает `ProjectExtensions` с телами файлов, поэтому её вызывают внутри `readAgentExtensions`, а наружу отдают только вид.

> Копия `SkillsConfig` без `skills.disabled` собирается вручную (`_withoutDisabled`): у класса ядра нет `copyWith`. Новое поле `SkillsConfig` нужно добавить и сюда, иначе второй вызов `parseSkills` молча получит значение по умолчанию.

### Чтение с диска: `readAgentExtensions`

Файл `lib/src/io/agent_extensions_reader.dart`, экспорт — `lib/io.dart`.

```dart
final view = await readAgentExtensions(
  snapshot,                        // свежий снимок папки с читаемым конфигом
  codelabHome: access.paths.codelabHome,
  environment: agentEnvironment,
);
```

Функция вызывает `loadProjectExtensions` из `codelab_agent_io` — ту же, что `config check`. Доверие, корни и таймауты (по 5 секунд на фазу) определяет она, поэтому вид совпадает с тем, что прочитает сессия агента. Дальше `readAgentExtensions`:

1. Собирает **кандидатов согласия** на каталоги других агентов: `.claude/skills` в папке и `~/.claude/skills` (только существующие). Каталог сканируется параллельно, не больше `consentEntryLimit` записей (по умолчанию 1000) и за общий `consentTimeout` (по умолчанию 5 секунд). Каталог, не ответивший в срок, остаётся кандидатом без числа (`skillDirs == null`); сканер, бросивший исключение, выпадает из списка. Подкаталоги-ссылки не считаются (`followLinks: false`).
2. Строит вид `agentExtensionsOf`.
3. Одним проходом переводит пути вида в форму хоста (`extensionsInHostForm`).

Параметр `scanConsentDir` (`@visibleForTesting`) — шов теста: настоящий сканер ходит по диску, а зависший том в тесте не воспроизвести.

Исход фаз — значение вида (`SectionTimedOut`, `SectionFailed`), а не исключение. Исключение построителя (разбор навыков и шаблонов ядром) не перехватывается: вызывающий логирует только `runtimeType` и показывает «не прочитано», потому что текст исключения может содержать фрагменты файлов.

Проверенный запуск на временном проекте с `AGENTS.md`, навыком `review` в `.codelab/skills` и навыком в `.claude/skills/other` (проект в `trusted_projects`):

```text
context: [AGENTS.md 18b] outcome=SectionRead
skills: [review enabled invoke=/skill:review root=.codelab/skills toggle=SkillToggle(available)]
consents: [.claude/skills dirs=1 granted=false toggle=SkillToggle(available)]
```

Навык `other` в списке навыков нет — каталог `.claude/skills` попал в кандидаты согласия: пока пользователь не согласится, агент его не читает.

### Перевод путей: `extensionsInHostForm`

Ядро работает с путями через `/` (`C:\p` → `/c/p`), а клиент открывает каталог платформой. Без перевода «Open» на Windows получил бы несуществующий путь (`AGENTS.md` §11). Построитель web-безопасен и перевода не знает, поэтому его делает `io.dart` **одним проходом** `extensionsInHostForm(view, windows: Platform.isWindows)`, чтобы ни одно поле не забыть. Переводятся только абсолютные пути (начинаются с `/`); `ContextFileView.path` — путь для промпта, а не путь диска, и остаётся как есть.

> **Правило для разработчика.** Любое новое поле вида, хранящее путь на диске, ДОЛЖНО переводиться в `extensions_host_paths.dart`. Полноту перевода проверяет `test/io/extensions_host_paths_test.dart`: добавляя поле-путь, добавьте в этот тест его проверку.

## Правило записи списков навыков: `skillsListEdit`

Файл `skills_list_edit.dart`. Страница включает и выключает навыки и даёт согласие на каталоги чужих агентов, то есть правит списки `skills.disabled` и `skills.extra_roots`.

```dart
SkillsListEditResult skillsListEdit(
  AgentConfigSnapshot snapshot,
  String key,       // 'skills.disabled' или 'skills.extra_roots'
  String element,
  {required bool present}   // true: элемент должен оказаться в списке
);
```

Результат — запечатанный `SkillsListEditResult`:

- `SkillsListPlan(layer, base, edits)` — запись возможна. Передайте `plan.base` и `plan.edits` в `AgentConfigStore.apply`. Пустой `edits` значит «список уже такой»: писать не нужно.
- `SkillsListRefused(refusal)` — запись невозможна по причине `refusal`. Отказ — обычный исход, не исключение; он же делает переключатель неактивным.

Почему такое правило: списки при слиянии слоёв **заменяются целиком**, поэтому правка меняет список того слоя, чьё значение сейчас действует (`snapshot.origins`), а не дописывает слой ниже, где она молча не подействовала бы. Нет источника — слой `user`.

| Отказ `SkillsListRefusal` | Когда | Подсказка для неактивного переключателя |
|---|---|---|
| `SkillsListNotEditable(source)` | список действует из слоя `project`, файла `--config` или переменной окружения | `Set in <source>; edit that file.` |
| `SkillsListDisabledByProject(source)` | имя выключено недоверенным проектом, включить его нельзя (Q43) | `Disabled by the project config (<source>).` |
| `SkillsListUntrustedProject` | согласие на относительный каталог в недоверенном проекте: загрузчик его не прочтёт | `Trust this project to read <entry>.` |
| `SkillsListLayerUnreadable(layer)` | файл слоя не читается и вне снимка | исправить файл; причину называет загрузчик |

Подсказки — строки из комментариев кода для клиентов; точные тексты строит клиент.

Особенности:

- `skills.extra_roots` никогда не пишется в `project` (SKL-2), а в `projectLocal` — только у доверенного проекта. Отозвать согласие можно всегда: это сужает доступ (приоритет безопасности).
- У недоверенного проекта `skills.disabled` объединяется с нижними слоями (Q43): выключить можно всегда, а имя, выключенное проектным слоем, включить нельзя. Поэтому источник такого ключа определяет снимок по значениям без проектных слоёв ([глава 02](02-config-store.md)).
- Доверие — `projectTrustedIn(snapshot.loaded.config)`; без `loaded.config` проект считается недоверенным.
- Ключ вне двух поддерживаемых — `ArgumentError.value(key, 'key', 'is not a skills list key')`: ошибка программиста.

Проверка запуском: для навыка `review` вызов `skillsListEdit(snap, 'skills.disabled', 'review', present: true)` даёт `SkillsListPlan(user, [SetValue(skills.disabled)])`, а `present: false` для навыка, которого нет в списке, — `SkillsListPlan(user, [])`.

## Определения агентов

Таблица определений агентов отвечает на вопрос страницы «Agents & modes»: какие типы субагентов доступны, откуда они и что с файлами, которые ядро отвергло.

### Построение строк: `agentDefinitionRowsOf`

Чистая функция (`lib/src/views/agent_definition_row_view.dart`):

```dart
List<AgentDefinitionRowView> agentDefinitionRowsOf({
  required List<AgentDefinition> definitions,
  required List<ExtensionDiagnostic> diagnostics,
  required List<AgentDefinition> builtins,
  required bool subagentsEnabled,
});
```

Порядок строк: `default`, затем встроенные типы в порядке `builtins`, затем файлы по имени. Встроенный тип заменён, если есть определение того же имени с областью `subagent` или `both`. При `subagents.enabled: false` встроенные типы остаются со статусом `subagentsOff`. Строки отвергнутых файлов строятся по диагностике: одна строка на путь, приоритет `duplicate`, затем `modelNotConfigured`, затем `error`; `shadowed` относится к файлу, заменённому проектным. Диагностика без файла (`untrusted_project` и прочие `info`) строк не даёт.

| `AgentRowStatus` | Смысл |
|---|---|
| `available` | доступно |
| `overridden` | встроенный тип заменён определением; путь — в `overriddenBy` |
| `modelNotConfigured` | модель определения вне каталога (диагностика `invalid_value` с фиксированным текстом `agentDefinitionModelNotInCatalogMessage`) |
| `error` | другая диагностика `error`; `errorLine` и `errorMessage` (фиксированный текст без ключей и фрагментов файла) |
| `duplicate` | не загружен: дубликат имени |
| `shadowed` | пользовательский файл заменён проектным |
| `subagentsOff` | встроенный тип при выключенных субагентах |

`AgentRowScope`: `session`, `subagent`, `both`. Подписи для пользователя строит клиент. Модель вне каталога распознаётся по тексту диагностики, потому что у ядра нет отдельного кода — это зафиксированное решение D18 change `add-settings-agents-modes`.

### Чтение: `agentDefinitionRowsAt`

Файл `lib/src/io/agent_definition_rows_at.dart`:

```dart
final rows = await agentDefinitionRowsAt(
  snapshot: snapshot,
  access: editableSettings,
  env: agentEnvironment,
  timeout: const Duration(seconds: 5),   // значение по умолчанию
  cancel: cancelToken,
);
```

Функция определяет дом (`access.paths.codelabHome` важнее окружения клиента, как у `FileAgentConfigStore`), доверие папки (`projectTrustAt`: канонический путь входит в `trusted_projects`; не разрешившийся путь — недоверенный), читает определения `loadAgentDefinitions` из `codelab_agent_io` (общей с `config check`) и строит строки. Без `loaded.config` в снимке читать нечего: возвращаются только встроенные строки.

Результат — `AgentDefinitionRows`: `rows`, `diagnostics`, `timedOut`, `projectTrusted` (клиент смотрит на него, а не на диагностику `untrusted_project`), `userDirectory` и `userDirectoryExists`, `projectDirectory` и `projectDirectoryExists`. Каталоги функция не создаёт. Наличие проверяется по раскрытой ссылке: каталог-ссылка существует, битая ссылка — нет. Исключение источника не скрывается: клиент переводит его в состояние.

Проверенный запуск на временном проекте с файлом `.codelab/agents/scout.md` дал строки `default, general, explore, review, plan, scout` (все `available`), `projectTrusted=true`, `userDirectoryExists=false`, `projectDirectoryExists=true`.

## Умолчания новой сессии: `sessionDefaultsOf`

Эта функция лежит в `lib/src/views/session_defaults_view.dart` и описана вместе с остальными видами в [главе 06](06-views.md#умолчания-новой-сессии).

## Тесты подсистемы

| Файл | Что проверяет |
|---|---|
| `test/extensions/agent_extensions_view_test.dart` (730 строк) | цепочка, навыки, шаблоны, диагностики, перекрытия |
| `test/extensions/skill_view_types_test.dart` | типизированные поля подписей (`overridesScope`, `extraEntry`) |
| `test/extensions/skills_list_edit_*_test.dart` | правило записи списков: основные случаи, защиты, нечитаемый слой, недоверенный проект |
| `test/io/read_agent_extensions_test.dart`, `read_agent_extensions_consents_test.dart` | чтение с диска, кандидаты согласия, пределы времени и записей |
| `test/io/extensions_host_paths_test.dart` | полнота перевода путей |
| `test/io/agent_definition_rows_at_test.dart`, `test/views/agent_definition_rows_test.dart` | строки определений и их чтение |

## Смотрите также

- [Алгоритм настроек: слои, перезагрузка, подключение](../../codelab_agent_core/doc/algorithms/settings.md) и [настройки на клиенте](../../codelab_client_core/doc/settings-on-client.md).
