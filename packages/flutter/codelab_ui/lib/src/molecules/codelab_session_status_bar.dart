import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';

/// Один сегмент строки статуса сессии: готовая подпись, подсказка и тон.
///
/// Почему: виджет не форматирует числа и не решает, насколько заполнен
/// контекст, — это политика клиентского слоя (change `add-usage-extension`,
/// D11, D24). Сюда приходит только готовое отображение.
///
/// Для чего: единый вид для «токены», «стоимость» и «контекст».
///
/// Как использовать: маппер приложения собирает сегмент из `SessionView.usage`;
/// [tone] отличный от [CodeLabTone.neutral] рисуется плашкой
/// ([CodeLabBadge]), нейтральный — обычным текстом; [tooltip] показывается
/// при наведении (пять счётчиков токенов, «price unknown» и т. п.).
class CodeLabStatusSegment {
  const CodeLabStatusSegment({
    required this.label,
    this.tooltip,
    this.tone = CodeLabTone.neutral,
  });

  /// Готовая подпись сегмента (например, `12.3k → 1.2k`).
  ///
  /// Почему готовая: форматирование чисел — политика клиентского слоя
  /// (D24), виджет её не повторяет. Для чего: единственный видимый текст
  /// сегмента. Как использовать: маппер приложения передаёт строку целиком.
  final String label;

  /// Подсказка при наведении: точные числа и причины неполноты.
  ///
  /// Почему отдельно: подпись сокращена («12.3k»), а точные значения нужны
  /// для сверки. Для чего: расшифровка сегмента. Как использовать: `null` —
  /// подсказки нет и [Tooltip] не создаётся.
  final String? tooltip;

  /// Тон сегмента: заполнение контекста (`warning`/`danger`) и т. п.
  ///
  /// Почему: близость к пределу должна быть заметна без чтения числа
  /// (D11, D24). Для чего: выбор между текстом и плашкой. Как использовать:
  /// [CodeLabTone.neutral] — обычный текст, иной тон — [CodeLabBadge].
  final CodeLabTone tone;

  @override
  bool operator ==(Object other) =>
      other is CodeLabStatusSegment &&
      other.label == label &&
      other.tooltip == tooltip &&
      other.tone == tone;

  @override
  int get hashCode => Object.hash(label, tooltip, tone);
}

/// Данные строки статуса сессии под композером (D11, D23 Т1).
///
/// Отсутствующий сегмент (`null`) не рисуется: на месте неизвестного не
/// бывает нулей (DSK-11). [busy] — ход идёт: вместо токенов и стоимости
/// хода показывается индикатор.
class CodeLabSessionStatusData {
  const CodeLabSessionStatusData({
    this.modelLabel,
    this.modeLabel,
    this.usage,
    this.cost,
    this.context,
    this.busy = false,
  });

  /// Подпись текущей модели сессии; `null` — опции `model` у агента нет.
  ///
  /// Почему: строка показывает, на какой модели идёт расход. Для чего:
  /// первый сегмент строки. Как использовать: маппер берёт имя выбранного
  /// значения опции категории `model` (иначе её `currentValue`).
  final String? modelLabel;

  /// Подпись текущего режима сессии; `null` — опции `mode` нет.
  ///
  /// Почему: режим влияет на то, что агент может делать, и должен быть виден
  /// рядом с расходом. Для чего: второй сегмент строки. Как использовать:
  /// как [modelLabel], по категории `mode`.
  final String? modeLabel;

  /// Токены последнего хода (`<вход> → <выход>`) или «usage: —».
  ///
  /// Почему `null`-able: неизвестное не заменяется нулём (DSK-11). Для чего:
  /// расход хода. Как использовать: `null` — сегмента нет (usage ещё не
  /// пришёл, ход без токенов или идёт — см. [busy]).
  final CodeLabStatusSegment? usage;

  /// Стоимость хода и сессии (`$0.0041 · session $1.20`).
  ///
  /// Почему: цена может быть неизвестна, тогда «—», а не `$0`. Для чего:
  /// денежный расход. Как использовать: `null` — сегмента нет.
  final CodeLabStatusSegment? cost;

  /// Заполнение контекстного окна (`85% context`) с тоном уровня.
  ///
  /// Почему: близость к сжатию важна, пока пользователь пишет следующий
  /// запрос. Для чего: предупреждение о пределе. Как использовать: `null` —
  /// размер окна неизвестен или контекст пуст.
  final CodeLabStatusSegment? context;

  /// Ход идёт, а usage ещё не получен: вместо токенов и стоимости —
  /// индикатор.
  ///
  /// Почему: пустое место выглядело бы как «расхода нет». Для чего:
  /// отличить «ждём снимок» от «агент не сообщает». Как использовать:
  /// маппер ставит `true` только для состояния `awaiting` при статусе сессии
  /// `running`/`cancelling`.
  final bool busy;

  @override
  bool operator ==(Object other) =>
      other is CodeLabSessionStatusData &&
      other.modelLabel == modelLabel &&
      other.modeLabel == modeLabel &&
      other.usage == usage &&
      other.cost == cost &&
      other.context == context &&
      other.busy == busy;

  @override
  int get hashCode =>
      Object.hash(modelLabel, modeLabel, usage, cost, context, busy);
}

/// Строка статуса сессии под композером: модель, режим, токены, стоимость и
/// контекст (agent-workbench-ui «Строка статуса сессии под композером»).
///
/// Почему: пользователю нужно видеть расход и заполнение контекста, не
/// открывая инспектор (D11). Для чего: только отображение готовых данных, без
/// бизнес-логики (`codelab_ui/AGENTS.md`). Как использовать: поставить под
/// композером, передав [data] из маппера приложения. Ключи сегментов:
/// `status-bar-usage`, `status-bar-cost`, `status-bar-context`.
class CodeLabSessionStatusBar extends StatelessWidget {
  const CodeLabSessionStatusBar({required this.data, super.key});

  final CodeLabSessionStatusData data;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      if (data.modelLabel != null)
        CodeLabText(
          data.modelLabel!,
          role: CodeLabTextRole.caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      if (data.modeLabel != null)
        CodeLabText(
          data.modeLabel!,
          role: CodeLabTextRole.caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      if (data.busy)
        const CodeLabProgressIndicator(
          size: 14,
          semanticLabel: 'Turn in progress',
        )
      else ...[
        if (data.usage != null)
          _Segment(
            key: const ValueKey('status-bar-usage'),
            segment: data.usage!,
          ),
        if (data.cost != null)
          _Segment(key: const ValueKey('status-bar-cost'), segment: data.cost!),
      ],
      if (data.context != null)
        _Segment(
          key: const ValueKey('status-bar-context'),
          segment: data.context!,
        ),
    ];
    // Wrap, а не Row: в узком окне сегменты переносятся, не переполняя строку.
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: items,
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.segment, super.key});

  final CodeLabStatusSegment segment;

  @override
  Widget build(BuildContext context) {
    final Widget content = segment.tone == CodeLabTone.neutral
        ? CodeLabText(
            segment.label,
            role: CodeLabTextRole.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        : CodeLabBadge(label: segment.label, tone: segment.tone);
    final tooltip = segment.tooltip;
    return tooltip == null
        ? content
        : Tooltip(message: tooltip, child: content);
  }
}
