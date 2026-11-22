// Область и фильтры вида Log (задача 4.1 change `redesign-protocol-pane`;
// spec agent-workbench-ui «Вид Log панели Protocol» — «Область в Log»;
// design.md D6, D8).
//
// Красный до задачи 4.2: файла
// `lib/features/protocol/application/log_record_filter.dart` нет. Ожидаемый
// API (D8 называет «чистую функцию» без сигнатур):
//
// * `recordsInScope(Iterable<Map<String, Object?>>, {String? focusedSessionId})`
//   — записи сессии в фокусе (`session_id`) и записи без сессии (элементы
//   соединения);
// * `LogRecordFilter({query = '', category, minLevel})` — значение с `==`,
//   `minLevel` — `LogLevel` пакета `structured_log`;
// * `applyRecordFilter(List<Map<String, Object?>>, LogRecordFilter)`.
//
// Главная проверка D8: результат совпадает с `LogViewerController` пакета
// на одних и тех же примерах (поиск по всем полям, кроме уровня и времени;
// минимальный уровень; точная категория), поэтому полноэкранный просмотр и
// вид Log не расходятся.

import 'package:codelab_desktop/features/protocol/application/log_record_filter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart' show LogLevel;
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer, LogViewerController;

import '../../../support/protocol_fixtures.dart';

void main() {
  final records = <Map<String, Object?>>[
    logRecord(
      'connection_state_changed',
      category: 'connection',
      component: 'client',
      generation: 1,
    ),
    logRecord(
      'prompt_sent',
      level: 'debug',
      category: 'session',
      sessionId: 's_7f3a',
    ),
    logRecord(
      'protocol_message',
      level: 'trace',
      category: 'protocol',
      sessionId: 's_91c0',
      requestId: 5,
      extra: {'direction': 'outbound', 'method': 'session/prompt'},
    ),
    logRecord(
      'tool_failed',
      level: 'error',
      category: 'session',
      sessionId: 's_91c0',
      extra: {'detail': 'Overflow in Parser'},
    ),
    logRecord('transport_closed', level: 'warning', category: 'connection'),
  ];

  group('область', () {
    test('записи сессии в фокусе и записи без сессии', () {
      final scoped = recordsInScope(records, focusedSessionId: 's_91c0');

      expect(scoped.map((r) => r['event']), [
        'connection_state_changed',
        'protocol_message',
        'tool_failed',
        'transport_closed',
      ]);
    });

    test('записей чужой сессии в области нет', () {
      final scoped = recordsInScope(records, focusedSessionId: 's_91c0');

      expect(scoped.any((r) => r['session_id'] == 's_7f3a'), isFalse);
    });

    test('без фокуса — только записи без сессии', () {
      expect(recordsInScope(records).map((r) => r['event']), [
        'connection_state_changed',
        'transport_closed',
      ]);
    });
  });

  group('фильтры', () {
    test('по умолчанию ничего не отбрасывают', () {
      expect(applyRecordFilter(records, const LogRecordFilter()), records);
    });

    test('поиск без учёта регистра по любому полю, кроме уровня и времени', () {
      expect(
        applyRecordFilter(
          records,
          const LogRecordFilter(query: 'OVERFLOW'),
        ).map((r) => r['event']),
        ['tool_failed'],
      );
      // Уровень и время в поиске не участвуют.
      expect(
        applyRecordFilter(records, const LogRecordFilter(query: 'error')),
        isEmpty,
      );
      expect(
        applyRecordFilter(records, const LogRecordFilter(query: '2026')),
        isEmpty,
      );
    });

    test('поиск по числовому полю', () {
      expect(
        applyRecordFilter(
          records,
          const LogRecordFilter(query: '5'),
        ).map((r) => r['event']),
        ['protocol_message'],
      );
    });

    test('минимальный уровень отсекает ниже', () {
      expect(
        applyRecordFilter(
          records,
          const LogRecordFilter(minLevel: LogLevel.warning),
        ).map((r) => r['event']),
        ['tool_failed', 'transport_closed'],
      );
    });

    test('категория — точное совпадение', () {
      expect(
        applyRecordFilter(
          records,
          const LogRecordFilter(category: 'session'),
        ).map((r) => r['event']),
        ['prompt_sent', 'tool_failed'],
      );
      expect(
        applyRecordFilter(records, const LogRecordFilter(category: 'sess')),
        isEmpty,
      );
    });

    test('фильтры действуют вместе', () {
      expect(
        applyRecordFilter(
          records,
          const LogRecordFilter(
            category: 'session',
            minLevel: LogLevel.error,
            query: 'parser',
          ),
        ).map((r) => r['event']),
        ['tool_failed'],
      );
    });
  });

  group('совпадение с LogViewerController (D8)', () {
    final cases = <String, ({String query, String? category, LogLevel? level})>{
      'поиск по тексту': (query: 'session/prompt', category: null, level: null),
      'поиск по id': (query: '5', category: null, level: null),
      'поиск по уровню не находит': (
        query: 'warning',
        category: null,
        level: null,
      ),
      'категория': (query: '', category: 'connection', level: null),
      'минимальный уровень': (query: '', category: null, level: LogLevel.info),
      'всё вместе': (query: 'tool', category: 'session', level: LogLevel.debug),
    };

    for (final entry in cases.entries) {
      test(entry.key, () {
        final buffer = LogBuffer();
        for (final record in records) {
          buffer.capture(
            Map<String, dynamic>.of(record),
            LogLevel.values.firstWhere((l) => l.name == record['level']),
          );
        }
        final controller = LogViewerController(buffer)
          ..searchQuery = entry.value.query
          ..categoryFilter = entry.value.category
          ..levelFilter = entry.value.level;
        addTearDown(controller.dispose);
        // `visibleEntries` читает снимок буфера сразу, ждать микрозадачу
        // уведомления не нужно.
        final expected = controller.visibleEntries;

        final actual = applyRecordFilter(
          records,
          LogRecordFilter(
            query: entry.value.query,
            category: entry.value.category,
            minLevel: entry.value.level,
          ),
        );

        expect(actual.map((r) => r['event']).toList(), [
          for (final r in expected) r['event'],
        ]);
      });
    }
  });

  test('LogRecordFilter — значение с равенством', () {
    expect(
      const LogRecordFilter(query: 'a', category: 'x'),
      const LogRecordFilter(query: 'a', category: 'x'),
    );
    expect(
      const LogRecordFilter(minLevel: LogLevel.info),
      isNot(const LogRecordFilter(minLevel: LogLevel.error)),
    );
  });
}
