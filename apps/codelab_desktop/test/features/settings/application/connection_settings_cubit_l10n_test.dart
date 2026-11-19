// Красные тесты задачи 4.1 change `add-desktop-localization`:
// `ConnectionSettingsCubit` и язык (spec app-settings «Язык интерфейса app»,
// сценарии «Уже показанные ошибки и InfoBar пересобираются», «Закрытый
// компонент не реагирует на смену языка»; «Локализация интерфейса app»;
// design.md D5 правила 1–3, D6 («Подпись профиля встроенного агента»), D9,
// D12).
//
// Что проверяется. Cubit страницы «Connection» получает порт `AppStrings` и
// строит производный текст состояния — подпись и сводку строки встроенного
// агента, заголовок, кнопку и описание «Restart agent» — как функцию
// «(входы, язык)»: смена языка пересобирает его из последних входов, а подписка
// одна и снимается в `close()`. Разовое сообщение о сбое записи хранится
// типизированным (D5), его текст собирает presentation; здесь проверяется
// только, что смена языка его не стирает (текст на странице — в
// `connection_page_l10n_test.dart`).
//
// Заглушка задачи 4.1: параметр `strings` у `ConnectionSettingsCubit` принят и
// не используется, поэтому проверки подписки и перевода красные на `expect`, а
// проверки «прежние строки на en» зелёные. Русские строки — по глоссарию
// («встроенный агент», «перезапустить агента», «подключение»); остальные —
// вне глоссария и перечислены в отчёте задачи 4.1.

import 'dart:async';

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/app/language/app_language_cubit.dart'
    show AppStrings;
import 'package:codelab_desktop/core/platform/connection_preferences.dart';
import 'package:codelab_desktop/features/settings/application/connection_commands.dart';
import 'package:codelab_desktop/features/settings/application/connection_settings_cubit.dart';
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/app_strings.dart';
import '../../../support/fake_profile_secrets.dart';
import '../../../support/fake_provider_settings.dart' show FakeWorkspace;
import '../../../support/in_memory_profile_store.dart';

const _dev = ConnectionProfile.stdio(
  id: 'dev',
  label: 'Dev',
  command: 'codelab-agent',
);

final _remote = ConnectionProfile.webSocket(
  id: 'devbox',
  label: 'Devbox',
  uri: Uri.parse('wss://devbox:7420/acp'),
);

/// Команды подключения с управляемыми целью, работающим профилем и корнем.
final class _Commands implements ConnectionCommands {
  ConnectionProfile? target;
  ConnectionProfile? running;
  String? restartDir = '/work';
  final _targets = StreamController<ConnectionProfile?>.broadcast();

  @override
  ConnectionProfile? get restartTarget => target;

  @override
  ConnectionProfile? get runningProfile => running;

  @override
  String? get restartDirectory => restartDir;

  @override
  Stream<ConnectionProfile?> get restartTargets => _targets.stream;

  @override
  Future<void> use(ConnectionProfile profile) async {}

  @override
  Future<void> restart() async {}
}

/// Хранилище, у которого удаление можно сломать: сбой записи — разовое
/// сообщение страницы.
final class _BreakableStore implements ProfileStore {
  _BreakableStore(Iterable<ConnectionProfile> profiles)
    : _inner = InMemoryProfileStore(profiles);

  final InMemoryProfileStore _inner;
  bool failWrites = false;

  @override
  Future<List<ConnectionProfile>> load() => _inner.load();

  @override
  Future<void> save(ConnectionProfile profile) => _inner.save(profile);

  @override
  Future<bool> remove(String id) async {
    if (failWrites) {
      throw StateError('disk is read-only');
    }
    return _inner.remove(id);
  }
}

void main() {
  late _BreakableStore store;
  late _Commands commands;
  late FakeWorkspace workspace;
  late FakeProfileSecrets secrets;
  late TestAppStrings strings;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = _BreakableStore([_dev, _remote]);
    commands = _Commands();
    workspace = FakeWorkspace();
    secrets = FakeProfileSecrets();
    strings = TestAppStrings(AppLocalizationsEn());
    addTearDown(strings.close);
  });

  ConnectionSettingsCubit build(AppStrings port) {
    final cubit = ConnectionSettingsCubit(
      store: store,
      openSecrets: () async => secrets,
      preferences: const SharedPreferencesConnectionPreferences(),
      workspace: workspace,
      commands: commands,
      environment: const {},
      profilesPath: '/home/u/.codelab/profiles.json',
      strings: port,
    );
    addTearDown(cubit.close);
    return cubit;
  }

  /// Окно подключено к [running]; цель следующего старта — [target].
  void connected({
    required ConnectionProfile running,
    ConnectionProfile? target,
  }) {
    commands
      ..target = target ?? running
      ..running = running;
    workspace.emit(
      WorkspaceState(connection: const Connected(), profile: running),
    );
  }

  Future<ConnectionSettingsLoaded> loaded(ConnectionSettingsCubit cubit) async {
    await cubit.reload();
    return cubit.state as ConnectionSettingsLoaded;
  }

  ConnectionSettingsLoaded now(ConnectionSettingsCubit cubit) =>
      cubit.state as ConnectionSettingsLoaded;

  group('FixedAppStrings(en): прежние строки', () {
    final fixedEn = FixedAppStrings(AppLocalizationsEn());

    test('строка встроенного агента и блок «Behavior» как раньше', () async {
      final state = await loaded(build(fixedEn));

      expect(state.rows.first.title, 'Embedded agent');
      expect(
        state.rows.first.summary,
        'Runs inside CodeLab; no separate '
        'process.',
      );
      expect(state.restartTitle, 'Restart agent');
      expect(state.restartButtonLabel, 'Restart');
      expect(
        state.restartDescription,
        'Reconnects the profile of this window and reloads open sessions. A '
        'running turn is interrupted; queued prompts stay.',
      );
    });

    test('цель — удалённый агент: «Reconnect» и описание по подписи '
        'профиля', () async {
      connected(running: _remote);

      final state = await loaded(build(fixedEn));

      expect(state.restartTitle, 'Reconnect');
      expect(state.restartButtonLabel, 'Reconnect');
      expect(
        state.restartDescription,
        'Reconnects Devbox and reloads open sessions. A running turn is '
        'interrupted; queued prompts stay.',
      );
    });

    test('выбранный профиль не равен работающему: «Restart … to use it.» и '
        'подсказка без проекта', () async {
      connected(running: embeddedConnectionProfile, target: _dev);
      commands.restartDir = null;

      final state = await loaded(build(fixedEn));

      expect(state.restartDescription, 'Restart Dev to use it.');
      expect(state.restartHint, 'Starts when you open a project.');
    });
  });

  group('TestAppStrings: производный текст пересобирается при смене языка', () {
    test('подпись и сводка строки встроенного агента: ru → en → ru', () async {
      final cubit = build(strings);
      await cubit.reload();
      expect(now(cubit).rows.first.title, 'Embedded agent');

      strings.emit(AppLocalizationsRu());
      await pumpEventQueue();
      final ru = now(cubit);
      // D6: подпись профиля встроенного агента переводится в итерации 4.
      expect(ru.rows.first.title, 'Встроенный агент');
      expect(
        ru.rows.first.summary,
        'Работает внутри CodeLab, отдельного процесса нет.',
      );
      // Остальные строки — профили пользователя, их подписи не переводятся.
      expect(ru.rows.map((r) => r.title), [
        'Встроенный агент',
        'Dev',
        'Devbox',
      ]);

      strings.emit(AppLocalizationsEn());
      await pumpEventQueue();
      expect(now(cubit).rows.first.title, 'Embedded agent');
    });

    test(
      '«Restart agent»: заголовок, кнопка и описание на ru и обратно',
      () async {
        commands
          ..target = _dev
          ..running = _dev;
        final cubit = build(strings);
        await cubit.reload();

        strings.emit(AppLocalizationsRu());
        await pumpEventQueue();

        final ru = now(cubit);
        expect(ru.restartTitle, 'Перезапустить агента');
        expect(ru.restartButtonLabel, 'Перезапустить');
        expect(
          ru.restartDescription,
          'Переподключает Dev и перезагружает открытые сессии. Выполняющийся '
          'ход прерывается; промпты в очереди сохраняются.',
        );

        strings.emit(AppLocalizationsEn());
        await pumpEventQueue();
        expect(now(cubit).restartTitle, 'Restart agent');
        expect(now(cubit).restartButtonLabel, 'Restart');
      },
    );

    test('цель — WebSocket: «Reconnect» на ru', () async {
      connected(running: _remote);
      strings = TestAppStrings(AppLocalizationsRu());
      final cubit = build(strings);

      final state = await loaded(cubit);

      expect(state.restartTitle, 'Переподключиться');
      expect(state.restartButtonLabel, 'Переподключиться');
    });

    test('цель не совпадает с работающим профилем и нет проекта: '
        'описание и подсказка на ru', () async {
      connected(running: embeddedConnectionProfile, target: _dev);
      commands.restartDir = null;
      strings = TestAppStrings(AppLocalizationsRu());
      final cubit = build(strings);

      final state = await loaded(cubit);

      expect(
        state.restartDescription,
        'Перезапустите агента, чтобы использовать Dev.',
      );
      expect(state.restartHint, 'Запустится, когда вы откроете проект.');
    });

    test('цели ещё нет: описание называет профиль этого окна', () async {
      strings = TestAppStrings(AppLocalizationsRu());
      final cubit = build(strings);

      final state = await loaded(cubit);

      expect(
        state.restartDescription,
        'Переподключает профиль этого окна и перезагружает открытые сессии. '
        'Выполняющийся ход прерывается; промпты в очереди сохраняются.',
      );
    });

    test('язык берётся из входов: смена языка не меняет профили, '
        'выбор по умолчанию и доступность действий', () async {
      connected(running: _dev);
      final cubit = build(strings);
      final before = await loaded(cubit);
      final ids = [for (final row in before.rows) row.id];
      final canRestart = before.canRestart;

      strings.emit(AppLocalizationsRu());
      await pumpEventQueue();

      final after = now(cubit) as ConnectionSettingsReady;
      expect([for (final row in after.rows) row.id], ids);
      expect(after.canRestart, canRestart);
      expect(after.defaultProfileId, 'embedded');
      expect(after.currentProfileId, 'dev');
    });
  });

  group('разовое сообщение о сбое записи (D5: типизированное)', () {
    test('смена языка не стирает сбой и не меняет его вид', () async {
      final cubit = build(strings);
      await cubit.reload();
      store.failWrites = true;
      expect(await cubit.removeProfile('dev'), isFalse);
      expect(now(cubit).failure, isNotNull);

      strings.emit(AppLocalizationsRu());
      await pumpEventQueue();

      expect(now(cubit).failure, isNotNull);
    });
  });

  group('подписка на AppStrings (D5 правила 1–3; R3)', () {
    test('одна подписка с момента создания, снимается в close()', () async {
      final cubit = build(strings);
      expect(strings.subscriberCount, 1);

      await cubit.close();

      expect(strings.hasListener, isFalse);
    });

    test('перечитывание файла, смена профиля и события workspace не '
        'добавляют подписок', () async {
      final cubit = build(strings);
      await cubit.reload();
      await cubit.reload();
      workspace.emit(const WorkspaceState(connection: Connected()));
      commands._targets.add(_dev);
      await pumpEventQueue();

      expect(strings.subscriberCount, 1);
      expect(cubit.state, isA<ConnectionSettingsLoaded>());
    });

    test('после close событие языка не меняет состояние', () async {
      final cubit = build(strings);
      await cubit.reload();
      final before = now(cubit);
      await cubit.close();

      strings.emit(AppLocalizationsRu());
      await pumpEventQueue();

      expect(identical(cubit.state, before), isTrue);
      expect(now(cubit).rows.first.title, 'Embedded agent');
    });

    test('язык, сменённый до первого чтения файла, учитывается при '
        'первой публикации', () async {
      final cubit = build(strings);
      strings.emit(AppLocalizationsRu());
      await pumpEventQueue();

      final state = await loaded(cubit);

      expect(state.rows.first.title, 'Встроенный агент');
    });
  });
}
