---
description: Прогон проверок monorepo через check-runner (полный melos check или указанные скрипты)
argument-hint: [melos-скрипты через пробел, например guard conformance:agent]
---
Запусти субагента **check-runner**. Скрипты: $ARGUMENTS (если не указаны — полный `fvm dart run melos run check`).

Покажи пользователю таблицу шаг → OK / FAIL / НЕ ЗАПУСКАЛСЯ и ключевые ошибки. Ничего не исправляй без просьбы.
