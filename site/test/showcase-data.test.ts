// Тесты данных витрины (tasks.md redesign-site-showcase, 3.7; D6, D7;
// project-site «Правдивость витрины»: «Шаг без ссылки на документ», «Пример
// помечен»). Данные собираются из настоящих источников репозитория: тест
// заодно сверяет их при каждом прогоне (сборка на настоящих источниках, D13).
import { describe, expect, it } from 'vitest';

import { isPublished } from '../src/lib/publish';
import { badges, trustItems } from '../src/lib/showcase/facts';
import { modeRows, modesDocRef } from '../src/lib/showcase/modes-demo';
import { exampleCaption, linesOf, scenario } from '../src/lib/showcase/scenarios';
import { quote } from '../src/lib/showcase/sources';
import { stepsData } from '../src/lib/showcase/steps';

/** Запретные слова витрины: skill §2, оценочные слова и обещания. */
const forbidden =
  /мощн|удобн|революцион|лучш|молниеносн|умн(ый|ая|ое|ые)|бесшовн|скоро|будет|будут|в планах|появится/i;

/** Документ без якоря. */
const documentOf = (docRef: string): string => docRef.split('#')[0]!;

describe('ссылки на документы (D6): шаг, факт, пункт доверия, демо', () => {
  const refs: [string, string][] = [
    ...stepsData.map((s): [string, string] => [s.title, s.docRef]),
    ...badges.map((b): [string, string] => [b.text, b.docRef]),
    ...trustItems.flatMap((t): [string, string][] => [
      [t.text, t.docRef],
      ...t.limits.map((limit): [string, string] => [limit.text, limit.docRef]),
    ]),
    ['макет рабочего места', scenario.docRef],
    ['клиент codelab', scenario.clients.cli.docRef],
    ['клиент Zed', scenario.clients.zed.docRef],
    ['режимы разрешений', modesDocRef],
  ];

  it.each(refs)('«%s» ссылается на раздел опубликованного документа', (_label, docRef) => {
    expect(docRef).toMatch(/^[^#]+\.md#[^#\s]+$/);
    expect(isPublished(documentOf(docRef)), docRef).toBe(true);
  });

  it('четыре шага, как в D5', () => {
    expect(stepsData).toHaveLength(4);
  });

  it('пустая ссылка у шага или факта недопустима — тест назвал бы текст', () => {
    for (const item of [...stepsData, ...badges]) {
      expect(item.docRef, JSON.stringify(item)).not.toBe('');
    }
  });
});

describe('пример помечен (D6)', () => {
  it('сценарий с example имеет подпись примера', () => {
    const lines = linesOf(scenario);
    expect(lines.some((l) => l.kind === 'example')).toBe(true);
    expect(scenario.caption).toBe(exampleCaption);
    expect(exampleCaption).toMatch(/пример/);
  });

  it('строки, которые не примеры, взяты из источников', () => {
    const kinds = new Set(linesOf(scenario).map((l) => l.kind));
    expect(kinds.has('ui')).toBe(true);
    expect(kinds.has('quote')).toBe(true);
    expect(kinds.has('snippet')).toBe(true);
  });

  it('кнопки макета app — строки каталога', () => {
    expect(scenario.approval.allow.text).toBe('Разрешить');
    expect(scenario.approval.reject.text).toBe('Отклонить');
    expect(scenario.approval.scopeOnce.text).toBe('Только сейчас');
    expect(scenario.approval.scopeAlways.text).toBe('Всегда');
  });
});

describe('тон витрины (skill §2)', () => {
  const texts: string[] = [
    ...stepsData.flatMap((s) => [s.title, s.text]),
    ...badges.map((b) => b.text),
    ...trustItems.flatMap((t) => [t.text, ...t.limits.map((l) => l.text)]),
    ...linesOf(scenario).map((l) => l.text),
  ];

  it('нет оценочных слов и обещаний', () => {
    for (const text of texts) expect(text, text).not.toMatch(forbidden);
  });

  it('нет ложных «не спрашивает вовсе» про `autopilot` и безусловного «`bypass` не спрашивает»', () => {
    for (const text of texts) {
      expect(text, text).not.toMatch(/не спрашивает (вовсе|совсем)/);
      expect(text, text).not.toMatch(/`bypass`[^.]{0,40}не спрашивает(?![^.]*кроме)/);
    }
  });

  it('нет внутренних имён пакетов и классов', () => {
    for (const text of texts) expect(text, text).not.toMatch(/codelab_(embedded|agent_|client_|acp_|setup|ui)/);
  });
});

describe('клавиши ответа codelab (D5, D6)', () => {
  it('оговорка о клавише `a` — цитата документа, а не слова автора', () => {
    const { noAlways } = scenario.clients.cli;
    expect(noAlways.kind).toBe('quote');
    expect(noAlways.text).toBe('Если агент не предложил «разрешать всегда», клавиша `a` ничего не отправит.');
  });
});

describe('блок «Ваш код и ключи» (D8)', () => {
  it('четыре пункта с ограничениями там, где их называет документ', () => {
    expect(trustItems).toHaveLength(4);
    expect(trustItems.filter((t) => t.limits.length > 0)).toHaveLength(3);
    expect(trustItems[0]!.limits).toHaveLength(0);
  });

  it('ключ API: рядом названо, что файловое хранилище секретов открытым текстом', () => {
    const limits = trustItems[1]!.limits.map((l) => l.text).join(' ');
    expect(limits).toMatch(/открытым текстом/);
    expect(limits).toMatch(/хранилища ОС в этой версии нет/);
  });

  it('файловые инструменты: нет ОС-песочницы, ссылки и stdio-сервер MCP названы', () => {
    const item = trustItems[2]!;
    const limits = item.limits.map((l) => l.text).join(' ');
    expect(item.text).toMatch(/встроенного агента и `codelab-agent`/);
    expect(limits).toMatch(/ОС-песочницы у агента нет/);
    expect(limits).toMatch(/читать и писать файлы вне рабочей папки и обращаться к сети/);
    expect(limits).toMatch(/Исключение только для чтения — каталоги загруженных навыков/);
    expect(limits).toMatch(/`ls` и `search`/);
    expect(limits).toMatch(/MCP получает ваши права/);
  });

  it('разрешения: «спрашивает перед правкой и командой», а не «только с разрешения»', () => {
    const item = trustItems[3]!;
    expect(item.text).toMatch(/спрашивает разрешение перед правкой файла и запуском команды/);
    expect(item.text).not.toMatch(/только с вашего разрешения/);
    expect(item.limits.map((l) => l.text).join(' ')).toMatch(/разрешать всегда/);
  });

  it('бейджей не больше пяти; лицензия MIT — один из них', () => {
    expect(badges.length).toBeLessThanOrEqual(5);
    expect(badges.map((b) => b.docRef)).toContain('docs/user/README.md#лицензия');
  });

  it('бейдж о ключе не утверждает, что значение не пишется в config.yaml вообще', () => {
    expect(badges[1]!.text).toBe('Ключ API задают именем переменной или секрета, а не значением в config.yaml');
  });

  it('бейдж о файловых инструментах назван субъектом и ведёт к блоку доверия с ограничениями', () => {
    const badge = badges.find((b) => b.docRef.endsWith('05-permissions.md#рабочая-папка'))!;
    expect(badge.text).toBe('Файловые инструменты агента CodeLab — в папке проекта');
    expect(badge.homeAnchor).toBe('trust');
  });

  it('ссылки блока ведут на разделы из спецификации', () => {
    expect(trustItems[0]!.docRef).toBe('apps/codelab_desktop/doc/user/09-settings.md#конфиденциальность');
    expect(trustItems[2]!.limits[0]!.docRef).toBe('apps/codelab_agent/doc/user/05-permissions.md#рабочая-папка');
  });
});

describe('настоящие источники (сборка на живых документах, D13)', () => {
  it('таблица режимов совпадает с документом агента', () => {
    expect(modeRows(quote)).toHaveLength(5);
  });

  it('блок одобрения `codelab` — первый блок раздела «Разрешения» руководства', () => {
    expect(scenario.clients.cli.block.text).toContain('Permission: Edit README.md');
    expect(scenario.clients.cli.keys.map((k) => k.key.text)).toEqual(['y', 'a', 'n', 'N', '?']);
  });
});
