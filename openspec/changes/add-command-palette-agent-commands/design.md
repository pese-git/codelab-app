## Context

Палитра app открывается двумя путями: `Ctrl/Cmd+K` (`CodeLabCommandPaletteSurface` поверх workbench) и inline-триггер `/` в композере (`CodeLabPromptComposer`). Оба пути показывают `ShellState.paletteActions`: шесть команд клиента `CodeLabCommandAction.defaults` из `codelab_ui`, а за ними команды агента активной сессии (`SessionView.agentCommands` → `agentCommandsOf` в `ui_mappers.dart`). Отбор по запросу — `CodeLabCommandAction.filter`, подстрока в `slashCommand`, названии или описании; его вызывают оба виджета `codelab_ui`. Выбор команды агента вставляет `/{name} ` в композер (`CodeLabShellCubit.insertAgentCommand`), подсказку `hint` композер показывает в placeholder.

Чего не хватает:
- доказательства R-20 на настоящем процессе агента;
- `CommandCatalog` в kit: change `extract-acp-client-kit` перенёс его сюда (design D9);
- разрешения конфликтов имён: `/plan`, `/permissions` и `/compact` клиента — заглушки `isAvailable: false`, а агент может объявить команду с тем же именем.

ACP (`docs/acp/protocol/14-Slash Commands.md`): агент объявляет команды `available_commands_update`, команда выполняется обычным `session/prompt`, текст которого начинается с `/name`. `input.hint` клиент показывает, пока аргумент не введён. Что клиент делает при выборе команды, ACP не задаёт. Бинарь `codelab-agent` объявляет `availableCommands: []` (agent-acp-server).

## Goals / Non-Goals

**Goals:**
- e2e R-20 на scripted-агенте: команда агента видна в палитре, после выбора и отправки агент получает `session/prompt` с `/compact`, его ответ — в ленте;
- `CommandCatalog` в `codelab_client_core`: слияние команд хоста и агента, конфликты имён, нечёткий поиск;
- логика отбора уходит из `codelab_ui` в kit, виджеты получают функцию поиска от app.

**Non-Goals:**
- немедленная отправка команды агента при выборе: команда по-прежнему вставляется в композер (D1);
- `SessionHandle.runCommand` — нужен CLI на этапе 6;
- собственные команды Dart-агента и реализация `/plan`, `/permissions`, `/compact` как команд клиента.

## Decisions

### D1. Выбор команды агента вставляет её в композер

Решение владельца продукта: поведение спеки agent-workbench-ui сохраняется для всех команд агента, с `input` и без него. Выбор вставляет `/{name} ` и закрывает палитру; `input.hint` показывается placeholder-ом; отправляет пользователь, через обычный путь композера и очередь промптов.

Почему не отправлять команду без `input` сразу: пользователь видит, что уйдёт агенту, и может дописать текст — ACP разрешает сопровождать команду любым содержимым промпта. Формулировку плана `09-10` (задача 5.6) «выбор `/compact` отправляет `session/prompt`» этот change заменяет на «выбор вставляет `/compact `, отправка уходит `session/prompt`». Критерий R-20 матрицы («агент получает `session/prompt` с `/compact`») выполняется связкой «выбор + отправка». Промпт отправляется с текстом `/compact`: композер обрезает пробелы (`ActiveSessionCubit`).

### D2. `CommandCatalog` — значение kit, которое строит хост

```dart
/// Команда хоста: какие команды есть, решает хост (app — `/logs`, CLI — свои).
final class HostCommand {
  const HostCommand({required this.id, required this.name, required this.label,
      required this.description, this.isAvailable = true});
  final String id; final String name; final String label; final String description;
  final bool isAvailable;
}

sealed class CatalogCommand { String get name; }       // name — без `/`
final class HostCatalogCommand extends CatalogCommand { final HostCommand command; }
final class AgentCatalogCommand extends CatalogCommand { final AgentCommandView command; }

final class CommandCatalog {
  factory CommandCatalog({required List<HostCommand> host,
      required List<AgentCommandView> agent});
  List<CatalogCommand> get commands;                   // команды хоста, затем агента; D3
  List<CatalogCommand> search(String query);           // D4
}
```

Где живёт: `packages/dart/codelab_client_core/lib/src/commands/command_catalog.dart`, экспорт из бареля. Каталог чистый и неизменяемый: хост строит его заново, когда меняется `SessionView.agentCommands` активной сессии. Эскиз `09-10` (`ClientWorkspace.commands`) не реализуется: команды хоста знает только хост, а состояние сессии уже есть в `SessionView`.

Иконки в kit не попадают. App строит `HostCommand` из `CodeLabCommandAction.defaults` (`codelab_ui`) по `id` и сопоставляет результат каталога обратно с `CodeLabCommandAction` по `id`; команды агента — через `agentCommandsOf` с id `agent-{name}`.

### D3. Конфликт имён

Сравнение имён — без `/`, с учётом регистра, как их присылает агент.
- Недоступная команда хоста (`isAvailable: false`), имя которой агент объявил, из `commands` исключается: работающая команда агента заменяет заглушку «coming soon» (решение владельца продукта).
- Доступная команда хоста остаётся. Одноимённая команда агента тоже остаётся и показывается в секции агента: выбор вставляет её текст в композер, а команда хоста выполняется в app, так что обе полезны и не путаются — секции палитры разделены.
- Повторяющееся имя внутри списка агента — берётся первая запись, как в `available_commands_update`.

Новый `available_commands_update` без этого имени возвращает заглушку на место: каталог строится из текущего списка.

### D4. Нечёткий поиск

`search(query)`: запрос обрезается, ведущий `/` снимается, сравнение без учёта регистра. Пустой запрос (или только `/`) — все `commands` в исходном порядке. Иначе команда подходит, если запрос:
1. префикс имени;
2. подстрока имени;
3. подпоследовательность имени (`cpt` → `compact`);
4. подстрока названия (`label` хоста, имени агента) или описания.

Результат упорядочен по номеру правила, внутри правила — исходный порядок `commands`. Подпоследовательность только по имени: по описанию она давала бы шум. Источник ранжирования — своё решение, без внешнего алгоритма (`AGENTS.md` §5).

### D5. Виджеты получают поиск от app

`codelab_ui` вводит `typedef CodeLabCommandSearch = List<CodeLabCommandAction> Function(String query)`. `CodeLabCommandPaletteSurface` и `CodeLabPromptComposer` получают необязательный параметр `search`. App передаёт поиск по `CommandCatalog`, а без параметра виджеты отбирают по-прежнему через `CodeLabCommandAction.filter`: этим пользуются превью и тесты `codelab_ui`. Порядок результата виджет сохраняет и только раскладывает его по секциям клиента и агента.

`ShellState.paletteActions` строится из `CommandCatalog.commands`; поиск — метод `ShellState`, который сопоставляет `CommandCatalog.search` с действиями. Логики выбора в виджетах нет (`AGENTS.md` §5, `codelab_ui`).

### D6. Тестовый агент и e2e

Режим `CodelabCompatibleStdioAgentMode.withAvailableCommands('with_available_commands')`:
- после ответа на `session/new` — `available_commands_update` с `compact` («Compact the conversation», без `input`) и `plan` («Create a plan», `input.hint` `what to plan`);
- промпт, начинающийся с `/compact`, — `agent_message_chunk` `Compacted the conversation.`, затем `end_turn`; другие промпты — `echo: <text>`.

E2E `command_palette_flow_test.dart` (только scripted-агент: Dart-агент команд не объявляет; в режиме `dart` — `skip`, а не тег `scripted-only`, иначе прогон `test:e2e:app:dart-agent` падает на файле без тестов — уточнение при реализации):
1. подключение, новая сессия; `Ctrl/Cmd+K` открывает палитру: в секции агента `compact` и `plan`, заглушки клиента `/compact` и `/plan` нет, `/permissions` остаётся недоступной;
2. выбор `compact` закрывает палитру и вставляет `/compact ` в композер, `session/prompt` не уходит;
3. отправка: агент получает `session/prompt` с текстом `/compact`, в ленте реплика `/compact` и ответ `Compacted the conversation.`;
4. inline `/pl` в композере показывает `plan` первым, выбор вставляет `/plan ` с placeholder `what to plan`;
5. выбор `/new` в палитре создаёт сессию без `session/prompt`.

Шаг 5 проверяет, что команда хоста по-прежнему выполняется в app. Как в остальных e2e, тест запускает отдельный скрипт melos `test:e2e:app:command-palette`, а `Ctrl/Cmd+K` выбирается по платформе (`meta` на macOS).

### D7. Обновления сразу за ответом на `session/new` не теряются

Найдено e2e R-20 на macOS (уточнение при реализации). Агент вправе прислать `session/update` сразу после создания сессии — ACP так описывает `available_commands_update` (`14-Slash Commands.md`), и Dart-агент шлёт его следом за ответом (agent-acp-server). Транспорт доставляет оба кадра раньше, чем `createSession` вернётся из `await` и заведёт сессию, а обновление неизвестной сессии клиент отбрасывал. Палитра оставалась без команд агента.

Решение в `AcpClientApplication`: пока хотя бы один `session/new` в полёте, обновления сессий, которых ещё нет, складываются в буфер по `sessionId`. После ответа `createSession` применяет обновления своей сессии в порядке прихода, до публикации сессии. Когда запросов в полёте не остаётся, буфер очищается, и обновления так и не созданных сессий отбрасываются, как прежде. Так же устроен буфер реплея `session/load` (`_sessionReplays`).

Почему не регистрировать сессию в обработчике ответа: id сессии появляется только в ответе, а сессию строит вызывающий `createSession` с `cwd` команды; буфер не меняет порядок и не раскрывает частично собранную сессию.

### D8. Повторная вставка того же черновика

Найдено e2e R-20 на macOS (уточнение при реализации). Композер подставлял черновик `initialPrompt` только при смене его текста. Пользователь вставил `/compact `, стёр или отправил его и выбрал `/compact` снова — черновик тот же, поле оставалось пустым. Решение: у черновика есть номер (`CodeLabPromptComposer.draftRevision`); `ActiveSessionCubit` увеличивает его при каждой подстановке — выбор команды агента и возврат промпта из очереди, — и композер подставляет черновик при смене номера, даже если текст тот же.

## Risks / Trade-offs

- **[Поиск в двух местах]** `CodeLabCommandAction.filter` остаётся для превью → app не должен его вызывать; тест `ShellState` проверяет, что подпоследовательность (`cpt`) находит `compact`, чего подстрока не умеет.
- **[Скрытая заглушка]** пользователь не видит, что у app нет своего `/compact`, когда агент его объявил → это и есть цель: работающая команда важнее заглушки; при пустом списке агента заглушка возвращается.
- **[Имя с другим регистром]** агент объявил `Compact` → заглушка `/compact` не скрывается; ACP не нормализует имена, поэтому и клиент их не нормализует.
- **[Нет доказательства на Dart-агенте]** R-20 закрывается scripted-агентом → R-20 — возможность клиента; команды агента в Dart-агенте — отдельная работа этапов 6 и 8.
