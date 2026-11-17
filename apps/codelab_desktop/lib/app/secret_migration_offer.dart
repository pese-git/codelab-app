import 'dart:async';

/// Источник состояния уровня app: «встроенный агент открыт с секретами в
/// файле конфига» и папка, с которой он открыт.
///
/// Почему: признак принадлежит встроенному агенту app, а не клиентскому ядру
/// (`codelab_client_core` и ACP не меняются), и его вычисляет мост при
/// открытии (design.md change `add-config-literal-secrets-and-migrate`, D8,
/// пп. 1–2). Резолвер знает агента, Cubit — UI; связывает их этот объект,
/// созданный composition root. Вместе с признаком хранится `cwd` агента:
/// перенос обязан идти по тем файлам, которые агент прочитал при открытии, а
/// не по проекту, выбранному в UI позже.
///
/// Для чего: хранит текущее значение и сообщает о его *смене*. Каждое
/// открытие агента даёт цикл `null → cwd`, поэтому закрытое крестиком
/// предупреждение возвращается при следующем подключении.
///
/// Как использовать: `EmbeddedTransportResolver` вызывает [set] (`cwd` после
/// открытия агента с `secretsInConfig`, `null` при закрытии агента);
/// `SecretMigrationCubit` читает [cwd] и [changes]. Источник закрывается
/// [close] при закрытии корневого scope, после резолвера.
final class SecretMigrationOffer {
  final _controller = StreamController<String?>.broadcast(sync: true);
  String? _cwd;

  /// `cwd` агента с секретами в файле; `null` — предложения нет.
  String? get cwd => _cwd;

  /// Есть ли предложение.
  bool get value => _cwd != null;

  /// Смены значения; повторное присваивание того же значения не публикуется.
  Stream<String?> get changes => _controller.stream;

  /// Текущее значение первым событием и затем его смены.
  ///
  /// Почему не `async*` с `yield _cwd; yield* changes`: между первым
  /// событием и подпиской на [changes] sync-broadcast источник никого не
  /// слушает, и смена в это окно (агент закрылся сразу после снимка) была бы
  /// потеряна. Здесь подписка на [changes] идёт *до* выдачи снимка, а порядок
  /// событий сохраняет один контроллер.
  Stream<String?> watch() {
    late final StreamController<String?> controller;
    StreamSubscription<String?>? subscription;
    controller = StreamController<String?>(
      sync: true,
      onListen: () {
        subscription = changes.listen(controller.add);
        controller.add(_cwd);
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  /// Задаёт текущее предложение переноса.
  ///
  /// Почему: признак «секреты в файле» вычисляет мост при открытии агента, а
  /// не UI; закрытие агента обязано снять предложение (design.md change
  /// `add-config-literal-secrets-and-migrate`, D8, пп. 1–2).
  ///
  /// Для чего: [cwd] — папка, с которой открыт агент с `secretsInConfig`, или
  /// `null` (агент закрыт, секретов нет). Меняет [cwd] и [value] и публикует
  /// смену в [changes]; то же значение повторно игнорируется.
  ///
  /// Как использовать: вызывает только `EmbeddedTransportResolver`. После
  /// [close] значение запоминается, но подписчикам не доставляется.
  void set(String? cwd) {
    if (_cwd == cwd) return;
    _cwd = cwd;
    if (!_controller.isClosed) _controller.add(cwd);
  }

  /// Закрывает поток; дальнейшие [set] только запоминают значение.
  Future<void> close() => _controller.close();
}
