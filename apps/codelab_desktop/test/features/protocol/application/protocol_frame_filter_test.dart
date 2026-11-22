// Область и фильтры вида Frames (задача 4.1 change `redesign-protocol-pane`;
// spec agent-workbench-ui «Панель Protocol: виды Frames и Log» — «Область —
// сессия в фокусе и соединение», «Нет сессии в фокусе»; «Таблица кадров» —
// «Errors only», «Поиск по id»; design.md D6).
//
// Красный до задачи 4.2: файла
// `lib/features/protocol/application/protocol_frame_filter.dart` нет.
// Ожидаемый API фиксируют эти тесты (design.md D7 называет файл и «чистые
// функции области и фильтров», но не сигнатуры):
//
// * `framesInScope(Iterable<ProtocolFrame>, {String? focusedSessionId})` —
//   кадры сессии в фокусе и элементы соединения (`sessionId == null`), порядок
//   записи сохраняется; без фокуса — только элементы соединения;
// * `ProtocolFrameFilter({query = '', showRequests = true,
//   showNotifications = true, errorsOnly = false})` — значение с `==`;
// * `applyFrameFilter(List<ProtocolFrame>, ProtocolFrameFilter)`.
//
// Подпись метода для поиска строит `protocolMethodLabel` (тест 4.3).

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_desktop/features/protocol/application/protocol_frame_filter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/protocol_fixtures.dart';

const _in = ProtocolFrameDirection.inbound;

void main() {
  // Рукопожатие, две сессии, `session/new` с уже привязанной сессией.
  final initialize = protocolFrame(seq: 1, method: 'initialize', id: 0);
  final initializeResult = protocolFrame(
    seq: 2,
    direction: _in,
    kind: ProtocolFrameKind.result,
    method: 'initialize',
    id: 0,
  );
  final prompt1 = protocolFrame(
    seq: 3,
    method: 'session/prompt',
    id: 'a9',
    sessionId: 's1',
    payload: {'prompt': 'Fix the Build'},
  );
  final promptResult1 = protocolFrame(
    seq: 4,
    direction: _in,
    kind: ProtocolFrameKind.result,
    method: 'session/prompt',
    id: 'a9',
    sessionId: 's1',
  );
  final update1 = protocolFrame(
    seq: 5,
    direction: _in,
    kind: ProtocolFrameKind.notification,
    method: 'session/update',
    sessionId: 's1',
    detail: 'tool_call',
  );
  final prompt2 = protocolFrame(
    seq: 6,
    method: 'session/prompt',
    id: 7,
    sessionId: 's2',
  );
  final error1 = protocolFrame(
    seq: 7,
    direction: _in,
    kind: ProtocolFrameKind.error,
    method: 'session/prompt',
    id: 5,
    sessionId: 's1',
    errorCode: -32603,
    detail: 'Internal error',
  );
  final all = [
    initialize,
    initializeResult,
    prompt1,
    promptResult1,
    update1,
    prompt2,
    error1,
  ];

  group('область', () {
    test('сессия в фокусе и элементы соединения, чужих сессий нет', () {
      final scoped = framesInScope(all, focusedSessionId: 's1');

      expect(scoped, [
        initialize,
        initializeResult,
        prompt1,
        promptResult1,
        update1,
        error1,
      ]);
      expect(scoped, isNot(contains(prompt2)));
    });

    test('смена фокуса меняет область, порядок записи сохраняется', () {
      expect(framesInScope(all, focusedSessionId: 's2'), [
        initialize,
        initializeResult,
        prompt2,
      ]);
    });

    test('без фокуса — только элементы соединения', () {
      expect(framesInScope(all), [initialize, initializeResult]);
    });

    test('сессия, которой нет среди кадров, даёт только соединение', () {
      expect(framesInScope(all, focusedSessionId: 'unknown'), [
        initialize,
        initializeResult,
      ]);
    });

    test('пустой буфер — пустая область', () {
      expect(framesInScope(const [], focusedSessionId: 's1'), isEmpty);
    });

    test('запрос session/new с привязанной сессией не элемент соединения', () {
      final bound = protocolFrame(
        seq: 8,
        method: 'session/new',
        id: 1,
        sessionId: 's2',
      );
      final unbound = protocolFrame(seq: 9, method: 'session/new', id: 2);

      expect(framesInScope([bound, unbound], focusedSessionId: 's1'), [
        unbound,
      ]);
      expect(framesInScope([bound, unbound], focusedSessionId: 's2'), [
        bound,
        unbound,
      ]);
    });
  });

  group('переключатели', () {
    test('по умолчанию — всё, ошибки тоже', () {
      expect(applyFrameFilter(all, const ProtocolFrameFilter()), all);
    });

    test('Errors only оставляет только ошибки', () {
      expect(
        applyFrameFilter(all, const ProtocolFrameFilter(errorsOnly: true)),
        [error1],
      );
    });

    test('Errors only действует независимо от Requests и Notifications', () {
      expect(
        applyFrameFilter(
          all,
          const ProtocolFrameFilter(
            errorsOnly: true,
            showRequests: false,
            showNotifications: false,
          ),
        ),
        [error1],
      );
    });

    test('Requests выключен — остаются уведомления', () {
      expect(
        applyFrameFilter(all, const ProtocolFrameFilter(showRequests: false)),
        [update1],
      );
    });

    test('Notifications выключен — остаются запросы, ответы и ошибки', () {
      expect(
        applyFrameFilter(
          all,
          const ProtocolFrameFilter(showNotifications: false),
        ),
        [initialize, initializeResult, prompt1, promptResult1, prompt2, error1],
      );
    });

    test('оба переключателя выключены — пусто', () {
      expect(
        applyFrameFilter(
          all,
          const ProtocolFrameFilter(
            showRequests: false,
            showNotifications: false,
          ),
        ),
        isEmpty,
      );
    });
  });

  group('поиск', () {
    test('по подписи метода без учёта регистра', () {
      expect(
        applyFrameFilter(all, const ProtocolFrameFilter(query: 'SESSION/UPD')),
        [update1],
      );
    });

    test('по подробности подписи', () {
      expect(
        applyFrameFilter(all, const ProtocolFrameFilter(query: 'tool_call')),
        [update1],
      );
    });

    test('по id: запрос и ответ на него', () {
      expect(applyFrameFilter(all, const ProtocolFrameFilter(query: 'a9')), [
        prompt1,
        promptResult1,
      ]);
    });

    test('по тексту замаскированного payload', () {
      expect(
        applyFrameFilter(all, const ProtocolFrameFilter(query: 'fix the')),
        [prompt1],
      );
    });

    test('кадр без payload по тексту payload не находится', () {
      expect(
        applyFrameFilter(all, const ProtocolFrameFilter(query: 'nothing')),
        isEmpty,
      );
    });

    test('пустой запрос ничего не отбрасывает', () {
      expect(applyFrameFilter(all, const ProtocolFrameFilter(query: '')), all);
    });

    test('поиск и переключатели действуют вместе', () {
      expect(
        applyFrameFilter(
          all,
          const ProtocolFrameFilter(query: 'prompt', showRequests: false),
        ),
        isEmpty,
      );
    });
  });

  test('ProtocolFrameFilter — значение с равенством', () {
    expect(
      const ProtocolFrameFilter(query: 'a', errorsOnly: true),
      const ProtocolFrameFilter(query: 'a', errorsOnly: true),
    );
    expect(
      const ProtocolFrameFilter(query: 'a'),
      isNot(const ProtocolFrameFilter(query: 'b')),
    );
  });
}
