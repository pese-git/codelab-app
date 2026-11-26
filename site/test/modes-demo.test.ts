// Тесты данных демо режимов разрешений (tasks.md redesign-site-showcase, 3.5;
// D5, D6; project-site «Правдивость витрины», сценарий «Переформулированный
// документ ломает сборку»). Ячейки берутся из строк таблицы документа, а не
// набираются руками: строка, которой в документе нет, ломает сборку.
import { fileURLToPath } from 'node:url';

import { describe, expect, it } from 'vitest';

import { modeRows, permissionModes } from '../src/lib/showcase/modes-demo';
import { createShowcaseSources, ShowcaseSourceError } from '../src/lib/showcase/sources';

const root = fileURLToPath(new URL('./fixtures/showcase/', import.meta.url));
const { quote } = createShowcaseSources(root);

describe('modeRows', () => {
  it('пять режимов в порядке таблицы документа', () => {
    expect(permissionModes).toEqual(['plan', 'ask', 'standard', 'accept-edits', 'bypass']);
    expect(modeRows(quote).map((r) => r.mode)).toEqual(permissionModes);
  });

  it('ячейки режима standard: чтение без вопроса, правка и команды — вопрос', () => {
    const standard = modeRows(quote).find((r) => r.mode === 'standard')!;
    expect(standard.cells).toEqual({
      read: { kind: 'allow', label: 'без вопроса' },
      edit: { kind: 'ask', label: 'вопрос' },
      run: { kind: 'ask', label: 'вопрос' },
    });
  });

  it('plan: запрещённые действия получают kind deny и слова документа', () => {
    const plan = modeRows(quote).find((r) => r.mode === 'plan')!;
    expect(plan.cells.edit).toEqual({ kind: 'deny', label: 'запрещена без вопроса' });
    expect(plan.cells.run).toEqual({ kind: 'deny', label: 'запрещены без вопроса' });
  });

  it('bypass: всё без вопроса', () => {
    const bypass = modeRows(quote).find((r) => r.mode === 'bypass')!;
    expect(Object.values(bypass.cells).map((c) => c.kind)).toEqual(['allow', 'allow', 'allow']);
  });

  it('режима нет в документе — ошибка quote с путём и цитатой', () => {
    expect(() => modeRows(quote, [...permissionModes, 'autopilot'] as never)).toThrow(ShowcaseSourceError);
    expect(() => modeRows(quote, ['autopilot'] as never)).toThrow(/05-permissions\.md.*autopilot/);
  });

  it('строка таблицы переформулирована — ошибка quote с путём документа', () => {
    const document = 'apps/codelab_agent/doc/user/05-permissions-reworded.md';
    expect(() => modeRows(quote, permissionModes, `${document}#режимы`)).toThrow(
      new RegExp(`${document}.*standard`),
    );
  });
});
