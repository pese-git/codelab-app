/**
 * Заголовок и описание страницы документа из его Markdown.
 *
 * Почему: документы читаются и на GitHub, где frontmatter показывается
 * таблицей, поэтому frontmatter в них нет; заголовок страницы — первый `#`,
 * описание — первый абзац (design.md add-astro-site, D3; project-site
 * «Публикуемые источники документации», сценарий «Документ без заголовка»).
 *
 * Для чего: одна функция для `<title>`, `<meta name="description">`, навигации
 * и оглавления `/docs/`; разбор — тем же `remark-parse`, что у Astro, поэтому
 * `#` внутри блока кода заголовком не считается.
 *
 * Как использовать: `docMeta(entry.body, entry.id)` — `id` записи коллекции
 * `docs` равен пути от корня репозитория. Нет заголовка первого уровня —
 * `DocTitleError` с путём файла: сборка падает, автор правит документ.
 */
import type { Heading, Nodes, Paragraph, Root } from 'mdast';
import remarkParse from 'remark-parse';
import { unified } from 'unified';

/** Ошибка сборки: у опубликованного документа нет заголовка `#` (D3). */
export class DocTitleError extends Error {
  constructor(repoPath: string) {
    super(`${repoPath}: a published document needs a level-1 heading ("# Title") (D3)`);
    this.name = 'DocTitleError';
  }
}

/** Заголовок и описание страницы. */
export interface DocMeta {
  readonly title: string;
  readonly description: string;
}

/** Предел описания: столько показывают сниппеты поисковиков. */
const descriptionLimit = 160;

const parser = unified().use(remarkParse);

/** Текст узла без разметки: код, ссылки и выделение дают только свой текст. */
function plainText(node: Nodes): string {
  if ('value' in node && typeof node.value === 'string') {
    return node.type === 'html' ? '' : node.value;
  }
  if ('children' in node) return node.children.map((child) => plainText(child)).join('');
  return '';
}

/** Обрезает [text] по границе слова до [descriptionLimit] символов с «…». */
function truncate(text: string): string {
  if (text.length <= descriptionLimit) return text;
  const cut = text.slice(0, descriptionLimit);
  const space = cut.lastIndexOf(' ');
  return `${(space > 0 ? cut.slice(0, space) : cut).trimEnd()}…`;
}

/** Заголовок (первый `#`) и описание (первый абзац после него) документа. */
export function docMeta(markdown: string, repoPath: string): DocMeta {
  const tree = parser.parse(markdown) as Root;
  const index = tree.children.findIndex(
    (node): node is Heading => node.type === 'heading' && node.depth === 1,
  );
  if (index === -1) throw new DocTitleError(repoPath);
  const title = plainText(tree.children[index]!).trim();
  if (title === '') throw new DocTitleError(repoPath);

  // Первый абзац с текстом: абзац из одного изображения описанием не служит.
  const paragraph = tree.children
    .slice(index + 1)
    .find(
      (node): node is Paragraph => node.type === 'paragraph' && plainText(node).trim() !== '',
    );
  const description = paragraph ? plainText(paragraph).replace(/\s+/g, ' ').trim() : '';
  return { title, description: truncate(description) };
}
