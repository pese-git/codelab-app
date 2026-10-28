import 'frame.dart';

/// Данные статус-строки TUI, уже извлечённые из модели экрана.
///
/// Почему: строку собирают из профиля, опций сессии и очереди kit, а
/// usage, стоимости и ветки git в kit пока нет (U-13); отделение данных от
/// раскладки позволяет проверять отбрасывание сегментов отдельно (§12.2.6;
/// design.md change `add-cli-tui`, D11).
///
/// Для чего: [spinner] — кадр компонента `dart_tui`, который адаптер
/// передаёт через `TuiChrome`; [elapsed] — время идущего хода.
final class StatusInfo {
  const StatusInfo({
    required this.profile,
    this.mode,
    this.model,
    this.queued = 0,
    this.spinner,
    this.elapsed,
  });

  final String profile;
  final String? mode;
  final String? model;
  final int queued;
  final String? spinner;
  final Duration? elapsed;
}

const _separator = ' · ';

/// Статус-строка не шире [width] колонок (без SGR: цвет добавляет
/// `render`).
///
/// Порядок: значок и время хода, профиль, режим, модель, `queue: N`. На
/// узком экране сначала отбрасывается профиль, затем модель сокращается до
/// части после последнего `/` и отбрасывается; режим и очередь остаются, а
/// если не помещаются и они — строка обрезается с `…`.
String statusLine(StatusInfo info, int width) {
  final turn = info.spinner == null && info.elapsed == null
      ? null
      : [
          ?info.spinner,
          if (info.elapsed case final elapsed?) '${elapsed.inSeconds}s',
        ].join(' ');
  final model = info.model;
  final short = model == null || !model.contains('/')
      ? model
      : model.substring(model.lastIndexOf('/') + 1);
  final queue = info.queued > 0 ? 'queue: ${info.queued}' : null;

  String join({required bool profile, String? model}) => [
    ?turn,
    if (profile) info.profile,
    ?info.mode,
    ?model,
    ?queue,
  ].join(_separator);

  for (final candidate in [
    join(profile: true, model: model),
    join(profile: false, model: model),
    join(profile: false, model: short),
    join(profile: false),
  ]) {
    if (displayWidth(candidate) <= width) {
      return candidate;
    }
  }
  final cut = fitLine(join(profile: false), width - 1, color: false);
  return '$cut…';
}
