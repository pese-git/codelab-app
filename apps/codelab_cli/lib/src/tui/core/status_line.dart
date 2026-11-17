import 'package:codelab_client_core/codelab_client_core.dart';

import '../../render/usage_segments.dart';
import 'frame.dart';

/// Данные статус-строки TUI, уже извлечённые из модели экрана.
///
/// Почему: строку собирают из профиля, опций сессии, очереди и usage kit
/// (D12 change `add-usage-extension`); ветки git в kit пока нет (U-13).
/// Отделение данных от раскладки позволяет проверять отбрасывание сегментов
/// отдельно (§12.2.6; design.md change `add-cli-tui`, D11).
///
/// Для чего: [spinner] — кадр компонента `dart_tui`, который адаптер
/// передаёт через `TuiChrome`; [elapsed] — время идущего хода.
final class StatusInfo {
  const StatusInfo({
    required this.profile,
    this.mode,
    this.model,
    this.queued = 0,
    this.approvalPending = false,
    this.spinner,
    this.elapsed,
    this.usage,
  });

  final String profile;
  final String? mode;
  final String? model;
  final int queued;

  /// Запрос разрешения ждёт ответа, но под модальным экраном его зона
  /// скрыта: об этом говорит статус-строка (design.md change
  /// `add-provider-setup-ui`, D17).
  final bool approvalPending;
  final String? spinner;
  final Duration? elapsed;

  /// Расход сессии (`SessionView.usage`): сегменты контекста, токенов и
  /// стоимости (D12); `null` и «агент не объявил usage» — без сегментов.
  final UsageView? usage;
}

/// Раскладка статус-строки: текст и место сегмента контекста.
///
/// Почему: цвет порога (80/95 %) вставляет `render`, а ему нужны границы
/// сегмента в уже выбранном по ширине кандидате (D23 Т4); `statusLine`
/// остаётся чистой строкой без SGR.
final class StatusLayout {
  const StatusLayout(
    this.text, {
    this.contextStart,
    this.contextEnd,
    this.contextLevel,
  });

  /// Строка не шире запрошенной ширины, без SGR.
  final String text;

  /// Границы сегмента контекста в [text] (индексы кодовых единиц);
  /// `null`, если сегмента нет или строка обрезана.
  final int? contextStart;
  final int? contextEnd;
  final UsageLevel? contextLevel;
}

const _separator = ' · ';

/// Статус-строка не шире [width] колонок (без SGR: цвет добавляет
/// `render`).
String statusLine(StatusInfo info, int width) => statusLayout(info, width).text;

/// Раскладка статус-строки с границами сегмента контекста.
///
/// Порядок сегментов: значок и время хода, профиль, режим, модель, контекст,
/// токены, стоимость, `queue: N`, `approval pending`. Порядок отбрасывания
/// на узком экране (D12): профиль, стоимость, токены, контекст, затем модель
/// (сначала сокращается до части после последнего `/`, потом отбрасывается);
/// режим, очередь и `approval pending` остаются, а если не помещаются и они —
/// строка обрезается с `…`. Без данных usage сегментов нет (VIEW-6), поэтому
/// прежние шаги раскладки не меняются.
StatusLayout statusLayout(StatusInfo info, int width) {
  final turn = info.spinner == null && info.elapsed == null
      ? null
      : [
          ?info.spinner,
          if (info.elapsed case final elapsed?) '${elapsed.inSeconds}s',
        ].join(' ');
  // Профиль, режим и модель — тексты профиля и агента: сегменты строки
  // очищаются от управляющих символов (TUI-11).
  final profileText = sanitizeStatusText(info.profile);
  final modeText = info.mode == null ? null : sanitizeStatusText(info.mode!);
  final model = info.model == null ? null : sanitizeStatusText(info.model!);
  final short = model == null || !model.contains('/')
      ? model
      : model.substring(model.lastIndexOf('/') + 1);
  final queue = info.queued > 0 ? 'queue: ${info.queued}' : null;
  final usage = usageSegmentsOf(info.usage);

  StatusLayout join({
    required bool profile,
    required bool cost,
    required bool tokens,
    required bool context,
    String? model,
  }) {
    final parts = <String>[];
    int? start;
    int? end;
    var offset = 0;
    void add(String text, {bool isContext = false}) {
      if (parts.isNotEmpty) offset += _separator.length;
      if (isContext) {
        start = offset;
        end = offset + text.length;
      }
      parts.add(text);
      offset += text.length;
    }

    if (turn != null) add(turn);
    if (profile) add(profileText);
    if (modeText != null) add(modeText);
    if (model != null) add(model);
    if (context && usage.context != null) {
      add(usage.context!, isContext: true);
    }
    if (tokens && usage.tokens != null) add(usage.tokens!);
    if (cost && usage.cost != null) add(usage.cost!);
    if (queue != null) add(queue);
    if (info.approvalPending) add('approval pending · esc to answer');
    return StatusLayout(
      parts.join(_separator),
      contextStart: start,
      contextEnd: end,
      contextLevel: start == null ? null : usage.contextLevel,
    );
  }

  for (final candidate in [
    join(profile: true, cost: true, tokens: true, context: true, model: model),
    join(profile: false, cost: true, tokens: true, context: true, model: model),
    join(
      profile: false,
      cost: false,
      tokens: true,
      context: true,
      model: model,
    ),
    join(
      profile: false,
      cost: false,
      tokens: false,
      context: true,
      model: model,
    ),
    join(
      profile: false,
      cost: false,
      tokens: false,
      context: false,
      model: model,
    ),
    join(
      profile: false,
      cost: false,
      tokens: false,
      context: false,
      model: short,
    ),
    join(profile: false, cost: false, tokens: false, context: false),
  ]) {
    if (displayWidth(candidate.text) <= width) {
      return candidate;
    }
  }
  final bare = join(
    profile: false,
    cost: false,
    tokens: false,
    context: false,
  ).text;
  final cut = fitLine(bare, width - 1, color: false);
  return StatusLayout('$cut…');
}
