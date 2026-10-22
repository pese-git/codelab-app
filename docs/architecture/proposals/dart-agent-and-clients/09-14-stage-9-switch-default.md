# 9.14. Этап 9 — Цели Must и переключение по умолчанию

> Часть предложения [«Dart-агент и клиенты CodeLab»](../dart-agent-and-clients.md). Status: Proposed. Исходные решения, связанные документы и порядок чтения — в оглавлении.

← [9.13. Этап 8 — MCP, конфигурация, AGENTS.md](09-13-stage-8-mcp-config.md) · [Оглавление](../dart-agent-and-clients.md) · [9.15. Этап 10 — Мобильные и web](09-15-stage-10-mobile-web.md) →

**Цель.** Dart-агент становится агентом по умолчанию в обоих клиентах; Python-агент и Python TUI
выводятся из эксплуатации.

**Задачи.**

1. **9.1. Автоматическая проверка доказательств:**
   `packages/dart/codelab_architecture_tests/test/parity_evidence_test.dart` разбирает таблицы
   матрицы целей и для каждой строки Must проверяет, что доказательство существует: `acp/<id>` —
   файл фикстуры; `cli/<id>` — тест с таким именем в `apps/codelab_cli/test/e2e`;
   `app:<файл>` — файл в `apps/codelab_app/integration_test`; `core/<id>` — тест в агентских
   пакетах. Падает со списком строк без доказательств.
2. **9.2.** Закрыть оставшиеся строки Must (по отчёту 9.1).
3. **9.3. Профили по умолчанию:** в app — «Встроенный агент» (не нужен отдельный бинарь) и
   встроенный профиль «codelab-agent (stdio)» с командой `codelab-agent serve --stdio` вместо
   `codelab serve --stdio` в `codelabAgentStdioProfile`; в CLI — `embedded`.
4. **9.4. Поставка** по §12.7: `release.yml`, артефакты `codelab` и `codelab-agent` для пяти
   целей, подписанный `SHA256SUMS`, скрипты `install.sh` / `install.ps1` и каналы (U-29),
   происхождение сборки; инструкция установки. Переключение по умолчанию МОЖЕТ выйти
   `beta`-релизом; первый публичный `stable`-релиз выпускается только вместе с подписанными
   дистрибутивами app (D-16, REL-4) и опубликованной политикой конфиденциальности (D-18,
   REL-9, §12.7.7). До первого релиза заменить `com.example.codelabApp` и
   `PRODUCT_COPYRIGHT` в `AppInfo.xcconfig`, создать платформы `windows` и `linux` app.
5. **9.5. Предупреждение о Python-сессиях** в пользовательской документации: сохранённые сессии
   Python-агента не переносятся, мигратора нет (agent-core-architecture §16.1, задача 3.7).
6. **9.6. Онбординг:** нет ключа провайдера → мастер в CLI и экран настройки в app вместо голой
   ошибки (U-17, D-05; §12.4.3–§12.4.5).
7. **9.7. Документация** по чек-листу `docs/architecture/adr/README.md`: `AGENTS.md` §5
   (структура монорепозитория), `layers-and-dependencies.md`, `acp-boundary.md` (агентская
   сторона), `permissions.md`, `testing.md`, `platform-integration.md`, `technology-stack.md`
   (`args`, `yaml`, `yaml_edit`, `toml` только для чтения `codelab.toml`); пользовательская
   документация: установка (скрипты §12.7.5, проверка подписи вручную — `docs/release/verify.md`),
   README репозитория со ссылками на установку и `PRIVACY.md` (D-18), конфигурация (`config.yaml`), LiteLLM Proxy как `baseUrl`, миграция с
   `codelab.toml` командой `codelab config migrate`.
8. **9.8. Ручная проверка совместимости:** Zed — подключение, промпт, инструменты, одобрение,
   отмена, `session/load`; сравнение с Claude Code ACP-агентом на тех же сценариях (порядок
   `session/update` до ответа, отказ не завершает ход, лишние поля терпимы).
9. **9.9. Заморозка и удаление:** Python-агент получает только исправления безопасности; после
   одного релизного цикла без регрессий — удаляется вместе с Python TUI; команда `codelab`
   принадлежит CLI, `codelab serve` — алиас на `codelab-agent serve` на один релиз.
10. **9.10. Чтение `codelab.toml`:** после переключения по умолчанию чтение устаревшего файла
    объявляется устаревшим — подсказка при старте (agent-core-architecture §15.7) называет срок
    удаления. Само удаление читателя, `package:toml` и команды `config migrate` — отдельный
    OpenSpec change `remove-legacy-codelab-toml` после вывода Python-агента (9.9); до него
    `core/config-reads-legacy-codelab-toml` остаётся обязательным тестом.
11. **9.11. Решение о песочнице ОС (P-13):** пересмотреть Won't «сейчас» по модели угроз после
    переключения по умолчанию: оставить границу папки и одобрения, песочница только на macOS или
    полноценная песочница на трёх ОС (agent-core-architecture §16.3). Итог — ADR; при решении
    «делать» — строка P-13 в матрице получает приоритет и этап, при «не делать» — снимается
    пометка «сейчас».

**OpenSpec change.** `switch-default-agent-to-dart` (scope: профили по умолчанию, онбординг,
предупреждение о непереносимых Python-сессиях), `add-release-pipeline-and-installer` (scope:
поставка 9.4, U-29, §12.7.2–§12.7.6, §12.7.8), `add-signed-app-distributions` (D-16) и
`add-privacy-policy` (D-18, §12.7.7) и `retire-python-agent` (scope: заморозка, сроки удаления,
алиасы команд). Смена значения по умолчанию `ui.mode` в CLI с `line` на `tui` после приёмки
U-12 — отдельный OpenSpec change, не входящий в эти два (§12.2.1).

**Что прочитать.** Матрица целей целиком, особенно блок «не регрессировать» и критерий вывода
Python-агента; `docs/architecture/adr/README.md`.

**Definition of Done.**

* `fvm dart test packages/dart/codelab_architecture_tests/test/parity_evidence_test.dart` зелёный.
* Все условия критерия вывода Python-агента из матрицы целей выполнены и отмечены в `proposal.md`
  change.
* Все `test:e2e:app:*`, `test:e2e:app:dart-agent`, `test:e2e:app:embedded`, `test:e2e:cli`
  зелёные в ночном прогоне три ночи подряд.
* Чек-лист Zed заполнен.

**Зависимости.** Этапы 7 и 8.

**Риски.** Функция текущего CodeLab не попала в цели и теряется — блок «не регрессировать» в
матрице, составленный по OpenSpec specs Python-агента. Пользователи с `codelab serve` в скриптах
— алиас на один релиз и предупреждение.

---

← [9.13. Этап 8 — MCP, конфигурация, AGENTS.md](09-13-stage-8-mcp-config.md) · [Оглавление](../dart-agent-and-clients.md) · [9.15. Этап 10 — Мобильные и web](09-15-stage-10-mobile-web.md) →
