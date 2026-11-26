/**
 * Признак «посетитель взаимодействует с демо»: наведение или фокус внутри.
 *
 * Почему: автопроигрывание останавливается при наведении и фокусе внутри демо
 * (design.md redesign-site-showcase, D2 п. 6; WCAG 2.2.2). Но «Ещё раз» —
 * явная просьба повторить: курсор остаётся над кнопкой, и без исключения
 * повтор бы не стартовал, а посетитель решил бы, что кнопка сломана. Признак —
 * автомат без `document`, чтобы тест проверял эти гонки (R4).
 *
 * Для чего: `src/scripts/showcase/autoplay.ts` пересылает события DOM сюда, а
 * итог — в `setEngaged` автомата демо.
 *
 * Как использовать: `createEngagement(onChange)`; `pointer(true|false)` и
 * `focus(true|false)` — вход и выход курсора и фокуса; `suppress()` — после
 * явного действия посетителя («Ещё раз»): признак снят, пока курсор не уйдёт или
 * фокус не придёт заново (клавиатурой). `onChange` вызывается только при
 * смене итога.
 */
export interface Engagement {
  readonly engaged: boolean;
  pointer(inside: boolean): void;
  focus(inside: boolean): void;
  suppress(): void;
}

export function createEngagement(onChange: (engaged: boolean) => void): Engagement {
  let pointerInside = false;
  let focusInside = false;
  let suppressed = false;
  let current = false;

  const update = (): void => {
    const next = !suppressed && (pointerInside || focusInside);
    if (next === current) return;
    current = next;
    onChange(next);
  };

  return {
    get engaged() {
      return current;
    },
    pointer(inside) {
      pointerInside = inside;
      if (!inside) suppressed = false;
      update();
    },
    focus(inside) {
      focusInside = inside;
      if (inside) suppressed = false;
      update();
    },
    suppress() {
      suppressed = true;
      update();
    },
  };
}
