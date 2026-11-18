// Тесты проверки точных версий (tasks.md add-astro-site, 2.3; project-site,
// сценарий «Диапазон версии отклоняется»; D1, D2).
import { describe, expect, it } from 'vitest';

import { findInexactVersions } from '../src/lib/exact-versions';

describe('findInexactVersions', () => {
  it('принимает точные версии во всех секциях', () => {
    expect(
      findInexactVersions({
        dependencies: { astro: '7.4.12', mermaid: '12.3.0' },
        devDependencies: { vitest: '5.1.1', typescript: '6.0.3' },
        optionalDependencies: { pre: '1.0.0-beta.2' },
      }),
    ).toEqual([]);
  });

  it('принимает package.json без зависимостей', () => {
    expect(findInexactVersions({ name: 'codelab-site' })).toEqual([]);
  });

  it.each([
    ['^5.0.0'],
    ['~5.0.0'],
    ['*'],
    ['5.x'],
    ['5.0.x'],
    ['5.X'],
    ['>=5.0.0'],
    ['>5.0.0'],
    ['<=5.0.0'],
    ['5.0.0 - 5.1.0'],
    ['5.0.0 || 6.0.0'],
    ['5'],
    ['5.0'],
    ['latest'],
    ['next'],
    [''],
  ])('отклоняет %j с именем зависимости', (spec) => {
    expect(
      findInexactVersions({ dependencies: { astro: spec } }),
    ).toEqual([{ name: 'astro', section: 'dependencies', spec }]);
  });

  it('проверяет devDependencies, optionalDependencies и peerDependencies', () => {
    expect(
      findInexactVersions({
        devDependencies: { vitest: '^5.1.1' },
        optionalDependencies: { fsevents: '~2.3.3' },
        peerDependencies: { typescript: 'latest' },
      }),
    ).toEqual([
      { name: 'vitest', section: 'devDependencies', spec: '^5.1.1' },
      { name: 'fsevents', section: 'optionalDependencies', spec: '~2.3.3' },
      { name: 'typescript', section: 'peerDependencies', spec: 'latest' },
    ]);
  });

  it('сообщает все нарушения, а не первое', () => {
    expect(
      findInexactVersions({
        dependencies: { astro: '7.4.12', mermaid: '^12.3.0' },
        devDependencies: { vitest: '*' },
      }),
    ).toEqual([
      { name: 'mermaid', section: 'dependencies', spec: '^12.3.0' },
      { name: 'vitest', section: 'devDependencies', spec: '*' },
    ]);
  });

  it('не проверяет engines: это версия Node, а не зависимость', () => {
    expect(
      findInexactVersions({ engines: { node: '>=26' } }),
    ).toEqual([]);
  });
});
