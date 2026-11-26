// Тесты источников витрины (tasks.md redesign-site-showcase, 1.1; D6;
// project-site «Правдивость витрины»: «Строка кнопки из каталога», «Удалённый
// ключ ломает сборку», «Переформулированный документ ломает сборку»,
// «Источник вне списка»). Работают на мини-репозитории из
// `test/fixtures/showcase/`, без сети.
import { fileURLToPath } from 'node:url';

import { describe, expect, it } from 'vitest';

import {
  createShowcaseSources,
  ShowcaseSourceError,
  showcaseSources,
} from '../src/lib/showcase/sources';

const root = fileURLToPath(new URL('./fixtures/showcase/', import.meta.url));
const { ui, quote, snippet } = createShowcaseSources(root);

const catalog = 'packages/flutter/codelab_ui/lib/src/l10n/codelab_ui_ru.arb';
const permissions = 'apps/codelab_agent/doc/user/05-permissions.md';

/** Сообщение ошибки источника; падает, если ошибки нет. */
function failure(run: () => unknown): string {
  try {
    run();
  } catch (error) {
    expect(error).toBeInstanceOf(ShowcaseSourceError);
    return (error as Error).message;
  }
  throw new Error('ожидалась ShowcaseSourceError');
}

describe('showcaseSources', () => {
  it('закрытый список: два каталога локализации и изображения/бренд', () => {
    expect(showcaseSources.catalogs).toEqual([
      'packages/flutter/codelab_ui/lib/src/l10n/codelab_ui_ru.arb',
      'apps/codelab_desktop/lib/l10n/app_ru.arb',
    ]);
    expect(showcaseSources.assets).toEqual(['apps/*/doc/images/**', 'docs/design/brand/**']);
  });
});

describe('ui(каталог, ключ)', () => {
  it('отдаёт значение ключа каталога', () => {
    expect(ui(catalog, 'codeLabApprovalAllow')).toBe('Разрешить');
    expect(ui(catalog, 'codeLabApprovalReject')).toBe('Отклонить');
  });

  it('нет ключа — ошибка с путём каталога и ключом', () => {
    const message = failure(() => ui(catalog, 'codeLabApprovalNope'));
    expect(message).toContain(catalog);
    expect(message).toContain('codeLabApprovalNope');
  });

  it('метаданные `@ключ` не считаются ключами', () => {
    expect(failure(() => ui(catalog, '@codeLabApprovalAllow'))).toContain('@codeLabApprovalAllow');
  });

  it('каталог вне showcaseSources — ошибка с путём', () => {
    const message = failure(() => ui('packages/flutter/codelab_ui/lib/src/l10n/codelab_ui_en.arb', 'x'));
    expect(message).toContain('codelab_ui_en.arb');
    expect(message).toContain('showcaseSources');
  });
});

describe('quote(документ, текст)', () => {
  it('находит цитату и возвращает её как есть', () => {
    expect(quote(permissions, '`standard` | без вопроса | вопрос | вопрос')).toBe(
      '`standard` | без вопроса | вопрос | вопрос',
    );
  });

  it('нормализует пробелы и переводы строк с обеих сторон', () => {
    expect(() => quote(permissions, 'Новая   сессия стартует в `standard`.')).not.toThrow();
    expect(() => quote(permissions, 'Режим задаёт,\nчто агент делает без вопроса.')).not.toThrow();
  });

  it('нет совпадения — ошибка с путём документа и цитатой', () => {
    const message = failure(() => quote(permissions, '`standard` | без вопроса | запрещена'));
    expect(message).toContain(permissions);
    expect(message).toContain('`standard` | без вопроса | запрещена');
  });

  it('документ вне allowlist publish.ts — ошибка', () => {
    const message = failure(() => quote('apps/codelab_cli/lib/src/repl/approval.dart', 'не источник'));
    expect(message).toContain('approval.dart');
    expect(message).toContain('showcaseSources');
  });

  it('несуществующий опубликованный документ — ошибка с путём', () => {
    expect(failure(() => quote('docs/user/missing.md', 'x'))).toContain('docs/user/missing.md');
  });
});

describe('snippet(документ#якорь, n)', () => {
  it('n-й блок кода раздела (нумерация с 1)', () => {
    expect(snippet(`${permissions}#рабочая-папка`, 1)).toBe('первая строка\nвторая строка');
    expect(snippet(`${permissions}#рабочая-папка`, 2)).toBe('другой блок');
  });

  it('подраздел входит в раздел, следующий раздел того же уровня — нет', () => {
    expect(snippet(`${permissions}#рабочая-папка`, 3)).toBe('вложенный блок');
    expect(failure(() => snippet(`${permissions}#рабочая-папка`, 4))).toContain('#рабочая-папка');
  });

  it('раздел подраздела заканчивается заголовком того же или более высокого уровня', () => {
    expect(snippet(`${permissions}#подробности`, 1)).toBe('вложенный блок');
    expect(failure(() => snippet(`${permissions}#подробности`, 2))).toContain('#подробности');
  });

  it('повторный заголовок получает суффикс -1, как якорь GitHub', () => {
    expect(snippet(`${permissions}#режимы-1`, 1)).toBe('блок повторного раздела');
    expect(failure(() => snippet(`${permissions}#режимы`, 1))).toContain('#режимы');
  });

  it('нет раздела — ошибка с путём и якорем', () => {
    const message = failure(() => snippet(`${permissions}#нет-такого`, 1));
    expect(message).toContain(permissions);
    expect(message).toContain('#нет-такого');
  });

  it('нет блока — ошибка с путём, якорем и номером', () => {
    const message = failure(() => snippet(`${permissions}#режимы-1`, 2));
    expect(message).toContain(permissions);
    expect(message).toContain('#режимы-1');
    expect(message).toContain('2');
  });

  it('ссылка без якоря и номер меньше 1 — ошибка', () => {
    expect(failure(() => snippet(permissions, 1))).toContain(permissions);
    expect(failure(() => snippet(`${permissions}#рабочая-папка`, 0))).toContain('#рабочая-папка');
  });

  it('документ вне allowlist — ошибка', () => {
    expect(failure(() => snippet('docs/architecture/x.md#a', 1))).toContain('showcaseSources');
  });
});
