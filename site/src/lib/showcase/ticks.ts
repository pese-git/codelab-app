/**
 * Разбор обратных кавычек в строках витрины на обычный текст и код.
 *
 * Почему: цитаты документов и факты содержат `код` в Markdown-кавычках
 * (design.md redesign-site-showcase, D6, D8), а страница не должна показывать
 * их сырыми. Собирать HTML строкой и вставлять через `innerHTML` нельзя
 * (D2 п. 3), поэтому разбор отдаёт фрагменты, а `<code>` создаёт Astro.
 *
 * Для чего: `Trust.astro`, `ClientSwitcher.astro`, `ModesDemo.astro`.
 *
 * Как использовать: `splitTicks(text).map(f => f.code ? <code>{f.text}</code> : f.text)`.
 * Непарная кавычка остаётся текстом.
 */
export interface TickPart {
  readonly code: boolean;
  readonly text: string;
}

export function splitTicks(text: string): TickPart[] {
  const parts: TickPart[] = [];
  let rest = text;
  while (rest !== '') {
    const open = rest.indexOf('`');
    const close = open === -1 ? -1 : rest.indexOf('`', open + 1);
    if (open === -1 || close === -1) {
      parts.push({ code: false, text: rest });
      break;
    }
    if (open > 0) parts.push({ code: false, text: rest.slice(0, open) });
    parts.push({ code: true, text: rest.slice(open + 1, close) });
    rest = rest.slice(close + 1);
  }
  return parts;
}
