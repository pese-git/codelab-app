// Синхронность источников витрины с охватом джоба `site` (tasks.md
// redesign-site-showcase, 1.6; D6 «Охват CI»). Правка источника, который не
// запускает джоб, пропустила бы рассинхрон витрины через pull request.
//
// `scopePatterns` повторяет файлы, на которые реагирует `_affectsSite` в
// `tool/ci/ci_scope.dart`, и их Dart-тест `site (add-astro-site, D13)` в
// `packages/dart/codelab_architecture_tests/test/ci_scope_test.dart`; тот же
// комментарий стоит там. Меняя охват, правьте оба списка.
import { describe, expect, it } from 'vitest';

import { showcaseSources } from '../src/lib/showcase/sources';

/** Шаблоны путей, которые запускают джоб `site` в суженном прогоне. */
const scopePatterns: readonly string[] = [
  'site/**',
  'docs/**',
  'openspec/**',
  'apps/*/README.md',
  'apps/*/doc/**',
  'packages/**/README.md',
  'packages/**/doc/**',
  'packages/flutter/codelab_ui/**/*.arb',
  'apps/codelab_desktop/**/*.arb',
];

/** glob → RegExp: `**` — любая глубина (в том числе ноль каталогов), `*` — внутри сегмента. */
function globToRegExp(pattern: string): RegExp {
  let source = '';
  for (let i = 0; i < pattern.length; i++) {
    if (pattern.startsWith('**/', i)) {
      source += '(?:[^/]+/)*';
      i += 2;
    } else if (pattern.startsWith('**', i)) {
      source += '.*';
      i += 1;
    } else if (pattern[i] === '*') {
      source += '[^/]*';
    } else {
      source += pattern[i]!.replace(/[\\^$.+?()[\]{}|]/g, '\\$&');
    }
  }
  return new RegExp(`^${source}$`);
}

const matchers = scopePatterns.map(globToRegExp);

/** Конкретный путь из шаблона источника: `*` и `**` заменяются именем `x`. */
function sample(pattern: string): string {
  return pattern.replace(/\*\*/g, 'x/x').replace(/\*/g, 'x');
}

const covered = (path: string): boolean => matchers.some((re) => re.test(path));

describe('охват CI и showcaseSources', () => {
  const nonDocuments = [...showcaseSources.catalogs, ...showcaseSources.assets];

  it.each(nonDocuments)('источник %s запускает джоб site', (pattern) => {
    expect(covered(sample(pattern)), pattern).toBe(true);
  });

  it('сопоставление не пропускает всё подряд: код приложения и виджеты вне охвата', () => {
    expect(covered('apps/codelab_cli/lib/src/repl/approval.dart')).toBe(false);
    expect(covered('packages/flutter/codelab_ui/lib/src/widgets/x.dart')).toBe(false);
  });
});
