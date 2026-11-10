## Why

Задача 9.9 этапа 9 ([план](../../../docs/architecture/proposals/dart-agent-and-clients/09-14-stage-9-switch-default.md)) выводит Python-агента и Python TUI из эксплуатации: с переключения по умолчанию — только исправления безопасности, затем удаление после одного релизного цикла без регрессий. По решению пользователя Q3 change [`switch-default-agent-to-dart`](../switch-default-agent-to-dart/design.md) (D1, D11) заморозка, сроки удаления и алиас `codelab serve` относятся к этому change. Сегодня:

- **Политика заморозки не опубликована.** Пользовательская документация ([`migrating-from-python-agent.md`](../../../docs/user/migrating-from-python-agent.md)) одной фразой говорит «получает только исправления безопасности». Не сказано, что считается исправлением безопасности, когда Python-агент удаляется, кто и по какому признаку это решает. Ворота MVP ждут политику: задача 4.4 `switch-default-agent-to-dart` («Python-агент заморожен»).
- **`codelab serve` сломан для старых скриптов.** Команда `codelab` теперь — терминальный клиент. `codelab serve --stdio` даёт `Unknown flag --stdio` и код `64`, а `codelab serve` без флагов открывает REPL с первым сообщением `serve`. Риск «конфликт имени `codelab`» ([`10-risks.md`](../../../docs/architecture/proposals/dart-agent-and-clients/10-risks.md)) и допущение 5 ([`11-assumptions-and-open-questions.md`](../../../docs/architecture/proposals/dart-agent-and-clients/11-assumptions-and-open-questions.md)) обещают алиас `codelab serve` → `codelab-agent serve` на один релиз. Q3: алиас нужен не позже первого выпуска с установщиком, который ставит `codelab` под общим именем (9.4).
- **Условие удаления не проверяемо.** «Одна `stable`-версия после переключения и нет открытой регрессии по строке Must» не связано ни с меткой трекера, ни с записью решения. Код Python-агента и Python TUI живёт вне monorepo (репозиторий `pese-git/codelab-agent`), поэтому здесь можно задать только политику, документацию и поведение `codelab`. Действия в Python-репозитории — внешние шаги ответственного.

## What Changes

- **Политика заморозки Python-агента** (итерация 0; design.md, D1–D4):
  - публикуется разделом «Поддержка Python-агента» в `docs/user/migrating-from-python-agent.md`;
  - что принимается: исправления уязвимостей по перечню D2; что не принимается: функции, обычные дефекты, совместимость с новыми версиями ACP и CodeLab;
  - условие удаления: после переключения опубликована одна версия канала `stable` и в трекере нет открытой регрессии с меткой `parity-regression`;
  - кто решает: владелец продукта и ответственный за релиз; где записывается: таблица в `proposal.md` change удаления (D4);
  - внешний шаг: баннер политики в README Python-репозитория.

  Публикация закрывает задачу 4.4 `switch-default-agent-to-dart` (D5).
- **Алиас `codelab serve …`** (итерация 1; codelab-cli «Алиас codelab serve», ADDED; D6–D12):
  - если первое слово argv — `serve`, `codelab` до разбора своих флагов запускает `codelab-agent serve <остальные аргументы без изменений>`;
  - бинарь ищется рядом с `codelab`, затем в абсолютных каталогах `PATH`;
  - stdin, stdout и stderr — общие с дочерним процессом (`ProcessStartMode.inheritStdio`), байты ACP CLI не трогает;
  - перед запуском — одна строка предупреждения о снятии алиаса в stderr;
  - код выхода — код `codelab-agent`; `SIGTERM` пересылается агенту;
  - `codelab-agent` не найден — код `1` и подсказка, stdout пуст.
- **Документы:**
  - план 9.9 — распределение задач (D13);
  - `delivery-roadmap.md` §4.4, §4.5;
  - `10-risks.md`, допущение 5 в `11-assumptions-and-open-questions.md`;
  - `12-7-release-and-distribution.md` §12.7.8 — переходный алиас вне контракта semver (D11, решение Q3);
  - `docs/user/migrating-from-python-agent.md` — алиас вместо `Unknown flag --stdio`;
  - `apps/codelab_cli/AGENTS.md` — алиас в списке мест с `dart:io`.
- **Внешние шаги** (tasks.md, раздел E; выполняет пользователь — владелец Python-репозитория, Q8): README и описание Python-репозитория, метка трекера, при удалении — завершающий тег и архивирование репозитория.

**BREAKING:** `codelab serve` без флагов больше не открывает REPL с первым сообщением `serve`: его обрабатывает алиас (решение Q2). Сообщение `serve` передаётся REPL как `codelab -- serve`. Остальные команды `codelab` не меняются.

## Не входит

- **Удаление в этом репозитории** — отдельный change `remove-python-agent` (D13, решение Q6). Он создаётся, когда выполнено условие удаления, и делает следующее:
  - снимает алиас (REMOVED в `codelab-cli`);
  - удаляет режим `python` e2e-помощника, тег `python-agent` и скрипт `test:e2e:cli:python-agent` (MODIFIED в `testing-quality`);
  - убирает упоминания Python-агента в документах.

  В этот же change входит запись решения об удалении. Здесь только критерий и порядок решения.
- **Код Python-агента и Python TUI** — вне monorepo; их изменения и удаление — внешние шаги.
- **Алиас `codelab connect`** (Python TUI): терминальный клиент сам заменяет его, а план 9.9 называет только `codelab serve` (решение Q7).
- **Встроенный запуск агента внутри `codelab` для алиаса** — альтернатива D6, отклонена (решение Q1).
- **Режим `python` e2e** остаётся до change удаления (решение Q5). Дельты `testing-quality` нет: правило обнаружения (`codelab serve --help` отвечает как Python-агент) с алиасом по-прежнему верно (D12).
- **Изменения ACP, `codelab-agent`, app, профилей.** `codelab-agent` не меняется, кроме одного: имя маркера рекурсии алиаса записано в известные переменные `ConfigLoader`, чтобы агент не писал ложное `config.env.unknown` (D7, задача 1.14); сам маркер агент не читает и не очищает. Сохранённые профили с `codelab serve` не переписываются (D11 change `switch-default-agent-to-dart`). С алиасом они снова запускаются, а предупреждение видно в stderr агента.
- **Поставка 9.4** — change `add-release-pipeline-and-installer`. Этот change не зависит от него (решение Q4).

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `codelab-cli` — ADDED: «Алиас codelab serve».

## Impact

- **Код:**
  - `apps/codelab_cli/lib/src/cli_args.dart` — `CliCommand.serveAlias`, распознавание до `ArgParser`;
  - новый `apps/codelab_cli/lib/src/serve_alias.dart` — поиск бинаря, запуск, сигналы, код выхода;
  - `apps/codelab_cli/lib/src/run.dart` — ветка режима;
  - тесты `apps/codelab_cli/test/` и `test/e2e/` — `cli/serve-alias-*`, обнаружение Python-агента рядом с алиасом.
- **Зависимости:** новых нет. Граф `README.md` не меняется. Нового правила сторожа нет: `dart:io` в `apps/codelab_cli` сторож уже разрешает, а список мест — правило ревью в `apps/codelab_cli/AGENTS.md` (D10).
- **Данные пользователя:** не меняются.
- **Безопасность:**
  - бинарь ищется только рядом с `codelab` и в абсолютных каталогах `PATH`; относительные записи `PATH` (`.`, пустая) пропускаются;
  - алиас, нашедший сам `codelab`, — ошибка, а не рекурсия (D7);
  - аргументы в сообщениях не печатаются (D9).
- **Документы:** перечислены в What Changes; `openspec validate retire-python-agent --strict`.
- **Ворота MVP:** задача 4.4 `switch-default-agent-to-dart` закрывается итерацией 0 и внешним шагом E.1 (D5).
