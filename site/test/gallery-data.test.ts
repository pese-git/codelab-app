// Тесты данных галереи (tasks.md redesign-site-showcase, 4.6; D9, D6):
// текстовые снимки терминала берутся из документов CLI через `snippet`.
import { describe, expect, it } from 'vitest';

import { isPublished } from '../src/lib/publish';
import { createTerminalShots, terminalShotRefs } from '../src/lib/showcase/gallery';
import { appShotByKey, appShotRefs, appShots, createAppShots } from '../src/lib/showcase/shots';

describe('снимки терминала галереи', () => {
  it('каждый снимок — блок кода раздела опубликованного документа', () => {
    const asked: [string, number][] = [];
    const shots = createTerminalShots({
      snippet(reference, n) {
        asked.push([reference, n]);
        return `text of ${reference}`;
      },
    });
    expect(shots).toHaveLength(terminalShotRefs.length);
    for (const [shot, ref] of shots.map((s, i) => [s, terminalShotRefs[i]!] as const)) {
      expect(isPublished(shot.docRef.split('#')[0]!), shot.docRef).toBe(true);
      expect(shot.docRef).toBe(ref.docRef);
      expect(shot.text).toBe(`text of ${ref.docRef}`);
      expect(shot.caption).not.toBe('');
    }
    expect(asked.map(([ref]) => ref)).toEqual(terminalShotRefs.map((r) => r.docRef));
  });

  it('удалённый раздел или блок ломает сборку: ошибка источника не гасится', () => {
    expect(() =>
      createTerminalShots({
        snippet() {
          throw new Error('section is missing');
        },
      }),
    ).toThrow('section is missing');
  });
});

describe('снимки app: одна запись на снимок, alt — из документа (D6, D9)', () => {
  it('alt каждого снимка берётся через quote из опубликованного документа', () => {
    const asked: [string, string][] = [];
    const shots = createAppShots({
      quote(document, text) {
        asked.push([document, text]);
        return text;
      },
    });
    expect(shots).toHaveLength(appShotRefs.length);
    for (const [shot, ref] of shots.map((s, i) => [s, appShotRefs[i]!] as const)) {
      expect(isPublished(ref.document), ref.document).toBe(true);
      expect(shot.alt).toBe(ref.alt);
      expect(asked).toContainEqual([ref.document, ref.alt]);
    }
  });

  it('ключи уникальны, подписи и alt непусты', () => {
    expect(new Set(appShotRefs.map((r) => r.key)).size).toBe(appShotRefs.length);
    for (const shot of appShots) {
      expect(shot.caption, shot.key).not.toBe('');
      expect(shot.alt, shot.key).not.toBe('');
    }
  });

  it('расхождение alt с документом ломает сборку', () => {
    expect(() =>
      createAppShots({
        quote() {
          throw new Error('quote not found');
        },
      }),
    ).toThrow('quote not found');
  });

  it('снимок «проекты» один: в галерее и в шагах — одна запись и один alt', () => {
    expect(appShotByKey.projects.alt).toMatch(/demo-app/);
    expect(appShotByKey.session.alt).toMatch(/demo/);
  });
});
