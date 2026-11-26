/**
 * Данные демо «Режимы разрешений»: что агент делает без вопроса в каждом режиме.
 *
 * Почему: режимы и их правила — предмет документации агента, и витрина не
 * должна расходиться с ней (design.md redesign-site-showcase, D5, D6).
 * Каждая строка таблицы режимов здесь подтверждается цитатой из документа
 * (`quote`): переформулировка строки или новый режим ломают сборку с путём
 * документа, и автор витрины правит данные в том же pull request (R2).
 *
 * Для чего: страницы `features/agent.astro` и главная получают из
 * `modeRows(quote)` строки для вкладок режимов и для таблицы без JavaScript.
 * `autopilot` в селектор не входит: документ говорит, что включить его из
 * клиента нельзя, и витрина показывает его сноской словами документа.
 *
 * Как использовать: `modeRows(quote)` из frontmatter с `quote` из `sources.ts`.
 * Модуль не читает файлы сам: `quote` передаётся параметром, поэтому тест
 * работает на фикстурах, а клиентский бандл не получает `node:fs`.
 */

/** Документ и раздел, из которого взяты режимы. */
export const modesDocRef = 'apps/codelab_agent/doc/user/05-permissions.md#режимы';

/** Режимы селектора в порядке таблицы документа. */
export const permissionModes = ['plan', 'ask', 'standard', 'accept-edits', 'bypass'] as const;
export type PermissionMode = (typeof permissionModes)[number];

/** Вид ответа агента на действие: без вопроса, вопрос или отказ без вопроса. */
export type CellKind = 'allow' | 'ask' | 'deny';

/** Ячейка таблицы: вид для оформления и слова документа для чтения. */
export interface ModeCell {
  readonly kind: CellKind;
  readonly label: string;
}

export interface ModeRow {
  readonly mode: PermissionMode;
  readonly cells: { readonly read: ModeCell; readonly edit: ModeCell; readonly run: ModeCell };
}

/**
 * Ожидаемые ячейки режимов (чтение, правка файлов, команды и MCP-инструменты)
 * — то, что витрина утверждает; `quote` сверяет их с документом.
 */
const expectedCells: Record<PermissionMode, readonly [string, string, string]> = {
  plan: ['без вопроса', 'запрещена без вопроса', 'запрещены без вопроса'],
  ask: ['вопрос', 'вопрос', 'вопрос'],
  standard: ['без вопроса', 'вопрос', 'вопрос'],
  'accept-edits': ['без вопроса', 'без вопроса', 'вопрос'],
  bypass: ['без вопроса', 'без вопроса', 'без вопроса'],
};

function cellOf(label: string): ModeCell {
  if (label === 'без вопроса') return { kind: 'allow', label };
  if (label === 'вопрос') return { kind: 'ask', label };
  return { kind: 'deny', label };
}

/**
 * Строки таблицы режимов, подтверждённые документом.
 *
 * [quote] — `quote` из `sources.ts`: бросает ошибку с путём и цитатой, если
 * строки в документе нет. [modes] — какие режимы показать (по умолчанию все);
 * [docRef] — документ с разделом, по умолчанию [modesDocRef].
 */
export function modeRows(
  quote: (document: string, text: string) => string,
  modes: readonly PermissionMode[] = permissionModes,
  docRef: string = modesDocRef,
): ModeRow[] {
  const document = docRef.split('#')[0]!;
  return modes.map((mode) => {
    const [read, edit, run] = expectedCells[mode] ?? ['', '', ''];
    // Цитата — строка таблицы без внешних вертикальных черт: пробелы вокруг
    // `|` документ может выровнять иначе, а quote их нормализует (D6).
    quote(document, `\`${mode}\` | ${read} | ${edit} | ${run} |`);
    return { mode, cells: { read: cellOf(read), edit: cellOf(edit), run: cellOf(run) } };
  });
}
