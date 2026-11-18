/// Операции отчёта журнала usage одной сессии: свежесть файла, пересчёт,
/// запись, одиночная операция (design.md change `add-usage-ledger`, D3, D12).
///
/// Почему отдельный класс, а не код в `AgentSession`: правило «одна операция
/// с записью на сессию» и разбор свежести файла не зависят от цикла и
/// инструментов, и их проще проверять отдельно от рантайма.
///
/// Как использовать: сессия создаёт одного хранителя при открытии, передаёт
/// снимок журнала и каталог функциями (значения читаются в момент вызова) и
/// вызывает [report] / [inMemory]; `close()` сессии ждёт [settle], чтобы
/// начатая запись файла не пережила закрытие (D3).
library;

import 'dart:convert';

import '../llm/model_catalog.dart';
import '../loop/agent_events.dart' show SessionId;
import '../session/session_store.dart';
import '../util/clock.dart';
import '../util/logger.dart';
import 'usage_ledger.dart';
import 'usage_ledger_report.dart';
import 'usage_ledger_store.dart';

/// Хранитель отчёта журнала usage сессии.
final class UsageLedgerKeeper {
  UsageLedgerKeeper({
    required this.sessionId,
    required this.store,
    required this.logger,
    required this.clock,
    required this.snapshot,
    required this.catalog,
    required this.isClosed,
  });

  final SessionId sessionId;

  /// Порт файла; `null` — отчёт только в памяти (`inMemory`).
  final UsageLedgerStore? store;
  final Logger logger;
  final Clock clock;

  /// Снимок журнала на момент вызова.
  final SessionSnapshot Function() snapshot;

  /// Каталог моделей сессии на момент вызова (цена по Q4).
  final ModelCatalog Function() catalog;

  /// Сессия закрыта. Закрытие ждёт начатую запись и закрывает журнал (D3);
  /// запись, начатая после него, пережила бы закрытие. Поэтому после
  /// закрытия отчёт строится только в памяти (`inMemory`), а не бросает
  /// исключение: чтение истории закрытой сессии остаётся возможным.
  final bool Function() isClosed;

  /// Идущая операция и следующая за ней принудительная (`rebuild` во время
  /// обычной, D3): не больше двух в очереди, повторные вызовы делят их.
  Future<UsageLedgerReport>? _running;
  Future<UsageLedgerReport>? _next;

  /// Отчёт: свежий файл не переписывается; [rebuild] пересчитывает всегда.
  ///
  /// Не больше одной операции с записью на сессию одновременно: вызов во
  /// время операции ждёт её же результат, а `rebuild` — одну новую операцию
  /// после неё (D3).
  Future<UsageLedgerReport> report({bool rebuild = false}) {
    if (isClosed()) {
      return inMemory();
    }
    final running = _running ?? _next;
    if (running == null) {
      return _start(rebuild);
    }
    if (!rebuild) {
      return _next ?? running;
    }
    return _next ??= running.then<void>((_) {}, onError: (Object _) {}).then((
      _,
    ) {
      _next = null;
      return _start(true);
    });
  }

  /// Свёртка в памяти без файла: засев адаптера (D8). Файл не читается и не
  /// пишется.
  Future<UsageLedgerReport> inMemory() async {
    final ledger = buildUsageLedger(snapshot());
    return UsageLedgerReport(
      ledger: ledger,
      state: UsageLedgerFileState.inMemory,
      noPriceModels: modelsWithoutPrice(ledger, catalog()),
    );
  }

  /// Ждёт идущие операции: `close()` сессии не закрывает журнал под записью.
  Future<void> settle() async {
    while (_running != null || _next != null) {
      try {
        await (_next ?? _running);
      } on Object {
        // Сбой операции уже отдан её вызывающему; закрытию он не мешает.
      }
    }
  }

  Future<UsageLedgerReport> _start(bool rebuild) {
    late final Future<UsageLedgerReport> operation;
    operation = _run(rebuild).whenComplete(() {
      if (identical(_running, operation)) {
        _running = null;
      }
    });
    return _running = operation;
  }

  Future<UsageLedgerReport> _run(bool rebuild) async {
    final started = clock.now();
    final ledger = buildUsageLedger(snapshot());
    final noPrice = modelsWithoutPrice(ledger, catalog());
    final port = store;
    if (port == null) {
      return UsageLedgerReport(
        ledger: ledger,
        state: UsageLedgerFileState.inMemory,
        noPriceModels: noPrice,
      );
    }
    String? text;
    try {
      text = await port.read(sessionId);
    } on UsageLedgerStoreException {
      // Файл, который не прочитался, — как битый: пересчёт и запись.
      text = '';
    }
    final UsageLedgerRebuildReason reason;
    if (rebuild) {
      reason = UsageLedgerRebuildReason.explicit;
    } else if (text == null) {
      reason = UsageLedgerRebuildReason.missing;
    } else {
      switch (_freshness(text, ledger)) {
        case _Freshness.fresh:
          return UsageLedgerReport(
            ledger: ledger,
            state: UsageLedgerFileState.upToDate,
            noPriceModels: noPrice,
          );
        case _Freshness.invalid:
          reason = UsageLedgerRebuildReason.invalid;
        case _Freshness.stale:
          reason = UsageLedgerRebuildReason.stale;
      }
    }
    // В лог идут только счётчики и причина, без текстов журнала (§16).
    logger.log(
      LogLevel.info,
      'usage.ledger.rebuild',
      fields: {
        'session_id': sessionId.value,
        'reason': reason.name,
        'records': ledger.records,
        'duration_ms': clock.now().difference(started).inMilliseconds,
      },
    );
    try {
      await port.write(sessionId, ledger.serialize());
    } on Object catch (error) {
      // Сбой записи не ошибка отчёта: журнал показывается без файла (D3).
      final why = error is UsageLedgerStoreException
          ? error.message
          : error.runtimeType.toString();
      logger.log(
        LogLevel.warning,
        'usage.ledger.write_failed',
        fields: {'session_id': sessionId.value, 'reason': why},
      );
      return UsageLedgerReport(
        ledger: ledger,
        state: UsageLedgerFileState.notSaved,
        reason: reason,
        saveError: why,
        noPriceModels: noPrice,
      );
    }
    return UsageLedgerReport(
      ledger: ledger,
      state: UsageLedgerFileState.rebuilt,
      reason: reason,
      noPriceModels: noPrice,
    );
  }

  /// Файл свеж, если разбирается, `version == 1`, а `source` совпадает со
  /// снимком (D3).
  _Freshness _freshness(String text, UsageLedger ledger) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return _Freshness.invalid;
    }
    if (json is! Map<String, Object?> || json['version'] != 1) {
      return _Freshness.invalid;
    }
    final source = json['source'];
    if (source is! Map<String, Object?> || source['records'] is! int) {
      return _Freshness.invalid;
    }
    return source['records'] == ledger.records &&
            source['lastRecordId'] == ledger.lastRecordId
        ? _Freshness.fresh
        : _Freshness.stale;
  }
}

enum _Freshness { fresh, stale, invalid }
