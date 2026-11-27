import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart'
    show describeFailureForDiagnostic;
import 'package:flutter_bloc/flutter_bloc.dart';

/// Синхронный сигнал «часть рабочего места изменилась» и пакетирование
/// таких сигналов.
///
/// Почему: `CodeLabShellCubit` после разделения (change
/// `extract-acp-client-kit`, design D10) собирает прежний
/// `CodeLabShellState` из пяти Cubit-ов. Поток `Cubit.stream` доставляет
/// состояния асинхронно, а виджеты и тесты читают `shellCubit.state` сразу
/// после вызова метода. Кроме того, одно событие — изменение сессии, её
/// создание или выбор, потеря соединения — меняет сразу несколько частей, а
/// фасад до разделения выпускал на такое событие ровно одно состояние
/// (характеризационный тест «one session/update produces one state»).
///
/// Для чего: каждая часть сообщает о новом состоянии синхронно, сразу после
/// `emit`; изменения внутри [batch] склеиваются в один сигнал в конце
/// внешнего пакета.
///
/// Как использовать: один экземпляр на рабочее место, общий для всех частей
/// и фасада. Фасад подписывается через [listen]; часть, меняющая в одном
/// событии и себя, и другую часть, оборачивает это в [batch].
final class ShellChanges {
  void Function()? _listener;
  var _depth = 0;
  var _pending = false;

  /// Устанавливает единственного слушателя; `null` — отписка.
  void listen(void Function()? listener) => _listener = listener;

  /// Выполняет [body], откладывая сигналы до конца самого внешнего пакета.
  void batch(void Function() body) {
    _depth++;
    try {
      body();
    } finally {
      _depth--;
      if (_depth == 0 && _pending) {
        _pending = false;
        _listener?.call();
      }
    }
  }

  void _changed() {
    if (_depth > 0) {
      _pending = true;
      return;
    }
    _listener?.call();
  }
}

/// Cubit части рабочего места: после каждого `emit` уведомляет [ShellChanges].
///
/// Почему и для чего — см. [ShellChanges]: фасад узнаёт о новом состоянии
/// части синхронно, без ожидания асинхронного `stream`.
///
/// Как использовать: наследовать вместо `Cubit` и передать общий
/// [ShellChanges]; `emit` вызывается как обычно.
abstract base class ShellPartCubit<S> extends Cubit<S> {
  ShellPartCubit(super.initialState, {required ShellChanges changes})
    : _changes = changes;

  final ShellChanges _changes;

  /// Пакет изменений нескольких частей — см. [ShellChanges.batch].
  void batch(void Function() body) => _changes.batch(body);

  @override
  void emit(S state) {
    super.emit(state);
    _changes._changed();
  }
}

/// Запись диагностики рабочего места в структурный журнал.
///
/// Почему: до разделения диагностику писал сам `CodeLabShellCubit`; теперь
/// её пишут несколько частей, а запись должна остаться прежней — тот же
/// логгер `codelab_desktop.shell`, маскирование секретов и ключ `source`.
///
/// Для чего: окно журнала (`LogBuffer`) и консоль/файлы — единственные
/// наблюдатели диагностики (`replace-debug-log-panel-with-fluent/design.md`,
/// Decision 5); своего списка диагностики части не держат.
///
/// Как использовать: один экземпляр на рабочее место; [record] с областью
/// [source] (`transport`, `session`, `project`, `prompt`, ...) — для
/// постоянного текста CodeLab. Сбой, чей текст может нести слова агента
/// (`JsonRpcError.message`, `data`), пишется через [recordFailure]: при
/// `metadataOnly` он даёт только метаданные (D3, «Текст ошибки агента», change
/// `redesign-protocol-pane`); текст для пользователя остаётся в состоянии
/// экрана и этим классом не строится.
final class ShellDiagnostics {
  /// [payloads] — базовая политика ядра (`AcpClientApplication.protocolPayloads`):
  /// единственный источник, второго параметра у app нет (D3). По умолчанию
  /// `metadataOnly`: хост, забывший передать политику, не раскрывает текст
  /// агента.
  ShellDiagnostics({
    Logger? logger,
    ProtocolPayloadPolicy payloads = ProtocolPayloadPolicy.metadataOnly,
  }) : _payloads = payloads,
       _logger = (logger ?? StructuredLogLogger('codelab_desktop.shell')).bind({
         logCategoryKey: applicationLogCategory,
         logComponentKey: presentationComponent,
       });

  final ProtocolPayloadPolicy _payloads;
  final Logger _logger;
  final _redactor = const SecretRedactor();

  void record(
    String message, {
    DiagnosticSeverity severity = DiagnosticSeverity.info,
    required String source,
  }) {
    final redactedMessage = _redactor.redactText(message);
    final logContext = {'source': source};
    switch (severity) {
      case DiagnosticSeverity.debug:
        _logger.debug(redactedMessage, context: logContext);
      case DiagnosticSeverity.info:
        _logger.info(redactedMessage, context: logContext);
      case DiagnosticSeverity.warning:
        _logger.warning(redactedMessage, context: logContext);
      case DiagnosticSeverity.error:
        _logger.error(redactedMessage, context: logContext);
    }
  }

  /// Пишет сбой: `'<what>: <описание>'`.
  ///
  /// Почему: `describeFailure` и `'$error'` несут текст ошибки агента (пути,
  /// фрагменты файлов), а журнал при `metadataOnly` не вправе его хранить
  /// (D3). Решение принимает единственное место — здесь, а не каждый Cubit.
  ///
  /// Как использовать: [what] — постоянный текст CodeLab без данных; `full` —
  /// `describeFailure(error)` с маскированием в [record], `metadataOnly` —
  /// `describeFailureMetadata(error)`.
  void recordFailure(
    String what,
    Object error, {
    DiagnosticSeverity severity = DiagnosticSeverity.error,
    required String source,
  }) => record(
    '$what: ${describeFailureForDiagnostic(error, _payloads)}',
    severity: severity,
    source: source,
  );
}
