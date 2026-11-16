import 'fixture.dart';
import 'matcher.dart';

/// Провал склейки `$text` обязательного повтора: драйвер превращает его в
/// свой тип ошибки (`AgentFixtureFailure`, `ClientFixtureFailure`).
typedef RepeatTextFailure =
    Never Function(
      FixtureFrame frame,
      List<FrameMismatch> mismatches,
      List<Object?> repeats,
    );

/// Шаблоны прогона фикстуры, которые ещё могут поглотить пришедший кадр.
///
/// Почему: граница необязательного кадра (`optional`) и хвоста `repeat` по
/// окну тишины зависит от скорости машины. Строки прогресса субагента
/// троттлятся по реальным часам, запись журнала на медленном диске CI
/// задерживает название сессии; кадр, пришедший позже окна, доставался
/// следующему обязательному кадру, и прогон изредка падал при верном
/// порядке кадров (§14.9, шаг 7).
///
/// Для чего: граница по содержимому. Необязательный кадр и хвост
/// обязательного повтора остаются открытыми и поглощают совпавшие с ними
/// кадры, пока не придёт кадр, не подходящий ни одному открытому шаблону.
///
/// Как использовать: драйвер добавляет шаблон через [add], каждый
/// полученный кадр сначала предлагает [absorb] и, если тот вернул `false`,
/// вызывает [closeAll] и сверяет кадр со своим ожидаемым шаблоном. Перед
/// проверкой тишины в конце прогона кадры тоже идут через [absorb], затем —
/// [closeAll].
final class OpenFrames {
  OpenFrames(this._matcher, this._onTextMismatch);

  final FrameMatcher _matcher;
  final RepeatTextFailure _onTextMismatch;
  final _open = <_OpenFrame>[];

  /// Есть ли шаблоны, ждущие кадров.
  bool get isNotEmpty => _open.isNotEmpty;

  /// Открывает [template] кадра [frame]; [repeats] — уже потреблённые
  /// кадры обязательного повтора (для `$text`). [single] — шаблон закрывается
  /// после первого кадра даже при `repeat`: клиентский прогон потребляет у
  /// `optional` не больше одного кадра (§14.4, §14.10).
  void add(
    FixtureFrame frame,
    Map<String, Object?> template, {
    List<Object?> repeats = const [],
    bool single = false,
  }) => _open.add(
    _OpenFrame(frame, template, repeated: frame.repeated && !single)
      ..repeats.addAll(repeats),
  );

  /// Поглощает [actual] первым совпавшим шаблоном в порядке фикстуры;
  /// шаблоны до него закрываются, неповторяемый — вместе с ним.
  /// `false` — ни один открытый шаблон не совпал.
  bool absorb(Object? actual) {
    final index = _open.indexWhere(
      (open) => _matcher.match(open.template, actual).isEmpty,
    );
    if (index < 0) {
      return false;
    }
    _close(index);
    final open = _open.first;
    open.repeats.add(actual);
    if (!open.repeated) {
      _close(1);
    }
    return true;
  }

  /// Закрывает все открытые шаблоны.
  void closeAll() => _close(_open.length);

  /// Закрывает первые [count] шаблонов; у обязательного повтора сверяет
  /// склейку `$text` всех его кадров (§14.4, `match`). У необязательного
  /// кадра `match` не проверяется (§14.4).
  void _close(int count) {
    final closed = _open.take(count).toList();
    _open.removeRange(0, count);
    for (final open in closed) {
      if (open.frame.optional) {
        continue;
      }
      if (open.frame.matchText case final text?) {
        final mismatches = _matcher.matchText(text, open.repeats);
        if (mismatches.isNotEmpty) {
          _onTextMismatch(open.frame, mismatches, open.repeats);
        }
      }
    }
  }
}

final class _OpenFrame {
  _OpenFrame(this.frame, this.template, {required this.repeated});

  final FixtureFrame frame;
  final Map<String, Object?> template;

  /// Поглощает ли шаблон больше одного кадра.
  final bool repeated;

  /// Поглощённые кадры — для сверки `$text` обязательного повтора.
  final repeats = <Object?>[];
}
