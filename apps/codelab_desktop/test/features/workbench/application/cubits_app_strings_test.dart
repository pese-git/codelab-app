// Красные тесты задачи 3.3 change `add-desktop-localization`: Cubit-ы
// рабочего места с текстом в состоянии и порт языка `AppStrings` (spec
// app-settings «Язык интерфейса app», сценарии «Живое рабочее место
// пересобирается», «Закрытый компонент не реагирует на смену языка»;
// design.md D5 правила 1–3, D9, D12; R1–R3).
//
// Cubit-ы со списком текста (`ConnectionCubit`, `ActiveSessionCubit`,
// `SessionsCubit`, `SecretMigrationCubit`) получают `AppStrings`, подписываются
// на `changes` один раз в конструкторе и отменяют подписку в `close()`.
// Управляемый `TestAppStrings` даёт смену языка в нужный момент и счётчик
// подписчиков (`subscriberCount`), по которому видна утёкшая вторая подписка.
//
// Заглушка задачи 3.3: параметр `strings` у `CodeLabShellParts.build` и
// `SecretMigrationCubit` принят и не используется, поэтому проверки подписки
// и перевода красные на `expect`, а проверки «без изменений» зелёные.
//
// Проверяются состояния через уже существующие публичные поля частей:
// подпись типа соединения (`WindowConnectionState.transportLabel`), текст
// текущей сессии (`SessionsState.currentSession*`), строки сайдбара, лента и
// строка статуса показываемой сессии. Русские строки — по глоссарию
// («встроенный агент», «сессия», «расход»); остальные — вне глоссария и
// перечислены в отчёте задачи 3.3.

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/core/platform/project_folder_picker.dart';
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/app_strings.dart';
import '../../../support/fake_usage_csv_saver.dart';

final class _FixedResolver implements TransportResolver {
  _FixedResolver(this.transport);

  final FakeAcpTransport transport;

  @override
  bool supports(ConnectionProfile profile) => true;

  @override
  Future<AcpTransport> open(
    ConnectionProfile profile, {
    required String projectDirectory,
  }) async => transport;
}

final class _NoPicker implements ProjectFolderPicker {
  @override
  Future<String?> pickFolder({String? initialDirectory}) async => null;
}

final class _NoRecentProjects implements RecentProjectsStore {
  @override
  Future<List<RecentProject>> load() async => const [];

  @override
  Future<void> record(String path) async {}
}

/// Части рабочего места на управляемом порте языка и агент-двойник.
final class _Scene {
  _Scene(this.strings) {
    application = AcpClientApplication(transport: FakeAcpTransport());
    workspace = ClientWorkspace(
      backend: AcpClientBackend(application),
      resolvers: [_FixedResolver(agent)],
    );
    parts = CodeLabShellParts.build(
      initialProfile: embeddedConnectionProfile,
      application: application,
      workspace: workspace,
      projectFolderPicker: _NoPicker(),
      usageCsvSaver: FakeUsageCsvSaver(),
      recentProjectsStore: _NoRecentProjects(),
      directoryExists: (_) async => true,
      strings: strings,
    );
    addTearDown(parts.close);
    // Старт агента по выбору проекта отключён: тест сам ведёт подключение.
    parts.settings.bindProjectStart(null);
    unawaited(parts.settings.selectProject('/work/app'));
  }

  final TestAppStrings strings;
  late final AcpClientApplication application;
  final agent = FakeAcpTransport();
  late final ClientWorkspace workspace;
  late final CodeLabShellParts parts;

  Future<JsonRpcRequest> _request(String method) async =>
      await agent.sent.firstWhere(
            (m) => m is JsonRpcRequest && m.method == method,
          )
          as JsonRpcRequest;

  /// Создаёт сессию [id]: агент отвечает на `session/new`.
  Future<void> createSession(String id) async {
    agent.drainSentMessages();
    final sent = _request(sessionNewMethod);
    final creating = parts.sessions.createSession();
    final request = await sent;
    agent.emitInbound(
      JsonRpcMessage.response(id: request.id, result: {'sessionId': id}),
    );
    await creating;
    await pumpEventQueue();
  }

  /// Ход, оборвавшийся по лимиту токенов: в ленте заметка `turnStopped`.
  Future<void> stoppedTurn() async {
    agent.drainSentMessages();
    final sent = _request(sessionPromptMethod);
    unawaited(
      parts.activeSession
          .submitPrompt('explain')
          .then<void>((_) {}, onError: (_) {}),
    );
    final request = await sent;
    agent.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const {'stopReason': 'max_tokens'},
      ),
    );
    await pumpEventQueue();
  }

  String? noticeBody() {
    for (final row in parts.activeSession.state.transcriptRows) {
      if (row is CodeLabNoticeRow) return row.body;
    }
    return null;
  }
}

void main() {
  late TestAppStrings strings;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    strings = TestAppStrings(AppLocalizationsEn());
    addTearDown(strings.close);
  });

  group('подписка на AppStrings.changes (D5 п. 3, R3)', () {
    test('части рабочего места подписаны по одной подписке на Cubit: '
        'подключение, показываемая сессия, список сессий', () {
      _Scene(strings);

      expect(strings.hasListener, isTrue);
      expect(strings.subscriberCount, 3);
    });

    test('после подключения, переподключения и смены сессии число подписчиков '
        'не выросло', () async {
      final scene = _Scene(strings);
      await scene.createSession('s1');
      await scene.createSession('s2');
      await scene.parts.connection.restart();
      scene.parts.sessions.selectSession('s1');
      await pumpEventQueue();

      expect(strings.subscriberCount, 3);
    });

    test('после close() подписок нет, а событие языка не меняет состояние и '
        'не бросает', () async {
      final scene = _Scene(strings);
      await pumpEventQueue();
      final connection = scene.parts.connection.state;
      final sessions = scene.parts.sessions.state;
      final active = scene.parts.activeSession.state;

      await scene.parts.close();
      expect(strings.hasListener, isFalse);
      expect(strings.subscriberCount, 0);

      strings.emit(AppLocalizationsRu());
      await pumpEventQueue();

      expect(scene.parts.connection.state, same(connection));
      expect(scene.parts.sessions.state, same(sessions));
      expect(scene.parts.activeSession.state, same(active));
    });
  });

  group('фасад CodeLabShellCubit', () {
    test(
      'палитра берёт каталог текущего языка при пересчёте за частями '
      '(D4, R1): подписи команд хоста и поиск по английской подписи',
      () async {
        final scene = _Scene(strings);
        final facade = CodeLabShellCubit(
          application: scene.application,
          workspace: scene.workspace,
          parts: scene.parts,
          projectFolderPicker: _NoPicker(),
          recentProjectsStore: _NoRecentProjects(),
        );
        addTearDown(facade.close);
        String labelOf() => facade.state.paletteActions
            .firstWhere((action) => action.id == 'new')
            .label;
        expect(labelOf(), 'New session');

        strings.emit(AppLocalizationsRu());
        await pumpEventQueue();

        expect(labelOf(), 'Новая сессия');
        // Английская подпись по-прежнему находит команду (searchAliases).
        expect(
          facade.state.searchPalette('session').map((action) => action.id),
          contains('new'),
        );

        strings.emit(AppLocalizationsEn());
        await pumpEventQueue();
        expect(labelOf(), 'New session');
      },
    );
  });

  group('ConnectionCubit', () {
    test('подпись типа соединения пересобирается при смене языка', () async {
      final scene = _Scene(strings);
      expect(scene.parts.connection.state.transportLabel, 'Embedded agent');

      strings.emit(AppLocalizationsRu());
      await pumpEventQueue();
      expect(scene.parts.connection.state.transportLabel, 'Встроенный агент');

      strings.emit(AppLocalizationsEn());
      await pumpEventQueue();
      expect(scene.parts.connection.state.transportLabel, 'Embedded agent');
    });

    test('смена языка не трогает профиль и статус соединения: меняется '
        'только текст', () async {
      final scene = _Scene(strings);
      await scene.parts.connection.startAgent('/work/app');
      final profile = scene.parts.connection.state.profile;
      final status = scene.parts.connection.state.connectionStatus;
      expect(status, CodeLabConnectionStatus.connected);

      strings.emit(AppLocalizationsRu());
      await pumpEventQueue();

      expect(scene.parts.connection.state.profile, profile);
      expect(scene.parts.connection.state.connectionStatus, status);
      expect(scene.parts.connection.state.transportLabel, 'Встроенный агент');
    });
  });

  group('SessionsCubit', () {
    test(
      'текст «нет активной сессии» пересобирается при смене языка',
      () async {
        final scene = _Scene(strings);
        expect(
          scene.parts.sessions.state.currentSessionLabel,
          'No active session',
        );
        // Подписи «Open a project…» под названием сессии нет (change
        // `add-empty-project-screen`, задача 4.7, D11): пока сессии в фокусе
        // нет, деталь — пустая строка на любом языке.
        expect(scene.parts.sessions.state.currentSessionDetail, '');

        strings.emit(AppLocalizationsRu());
        await pumpEventQueue();

        final state = scene.parts.sessions.state;
        // Название — вне глоссария.
        expect(state.currentSessionLabel, 'Нет активной сессии');
        expect(state.currentSessionDetail, '');
      },
    );

    test(
      'строка сайдбара пересобирается, кэш не возвращает старый язык',
      () async {
        final scene = _Scene(strings);
        await scene.createSession('s1');
        expect(scene.parts.sessions.state.sessions.single.title, 'New session');

        strings.emit(AppLocalizationsRu());
        await pumpEventQueue();
        final ru = scene.parts.sessions.state.sessions.single;
        expect(ru.title, 'Новая сессия');
        expect(ru.updatedLabel, 'Активна');

        // Новая сессия после смены языка тоже на ru: язык в ключе кэша.
        await scene.createSession('s2');
        expect(
          scene.parts.sessions.state.sessions.map((s) => s.title),
          everyElement('Новая сессия'),
        );

        strings.emit(AppLocalizationsEn());
        await pumpEventQueue();
        expect(
          scene.parts.sessions.state.sessions.map((s) => s.title),
          everyElement('New session'),
        );
      },
    );
  });

  group('ActiveSessionCubit', () {
    test('заметка исхода хода и строка статуса пересобираются из последнего '
        'вида сессии', () async {
      final scene = _Scene(strings);
      await scene.createSession('s1');
      await scene.stoppedTurn();
      expect(
        scene.noticeBody(),
        'The model reached its token limit, so the turn ended.',
      );

      strings.emit(AppLocalizationsRu());
      await pumpEventQueue();

      expect(
        scene.noticeBody(),
        'Модель достигла лимита токенов, поэтому ход завершён.',
      );
      expect(
        scene.parts.activeSession.state.statusBar?.usage?.label,
        'расход: —',
      );
    });

    test('кэш ленты не возвращает старый язык: ход после смены языка и '
        'возврат к en', () async {
      final scene = _Scene(strings);
      await scene.createSession('s1');
      strings.emit(AppLocalizationsRu());
      await pumpEventQueue();

      await scene.stoppedTurn();
      expect(
        scene.noticeBody(),
        'Модель достигла лимита токенов, поэтому ход завершён.',
      );

      strings.emit(AppLocalizationsEn());
      await pumpEventQueue();
      expect(
        scene.noticeBody(),
        'The model reached its token limit, so the turn ended.',
      );
    });

    test('ответ агента и данные не меняются при смене языка', () async {
      final scene = _Scene(strings);
      await scene.createSession('s1');
      await scene.stoppedTurn();
      final prompts = [
        for (final row in scene.parts.activeSession.state.transcriptRows)
          if (row is CodeLabUserRow) row.text,
      ];

      strings.emit(AppLocalizationsRu());
      await pumpEventQueue();

      expect(prompts, ['explain']);
      expect([
        for (final row in scene.parts.activeSession.state.transcriptRows)
          if (row is CodeLabUserRow) row.text,
      ], prompts);
    });
  });
}
