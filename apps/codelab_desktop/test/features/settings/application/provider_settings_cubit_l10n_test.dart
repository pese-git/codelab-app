// Красные тесты задачи 4.1 change `add-desktop-localization`:
// `ProviderSettingsCubit` и язык (spec app-settings «Страница «Providers»»,
// «Локализация интерфейса app», сценарии «Уже показанные ошибки и InfoBar
// пересобираются», «Команда в переведённой фразе», «Закрытый компонент не
// реагирует на смену языка»; design.md D5, D6, D7, D9, D12).
//
// Что проверяется. Строки провайдеров (подпись, источник ключа, подсказки
// кнопок), итоги проверок, InfoBar «Read-only» и проблемы нечитаемого конфига —
// производный текст: функция «(входы, язык)», он пересобирается при смене
// языка из последнего снимка, а итог проверки хранится данными (вид, число
// моделей, статус, время), а не готовой строкой: поздний итог, пришедший после
// смены языка, показывается на новом языке. Источник ключа — одно сообщение с
// плейсхолдерами, без склейки «In $backendId as ». Разовые сообщения (баннеры
// исходов записи и удаления) хранятся типизированно (D5), их текст собирает
// presentation; он проверяется в `providers_page_l10n_test.dart`, а здесь —
// что смена языка не стирает баннер.
//
// Заглушка задачи 4.1: параметр `strings` у `ProviderSettingsCubit` принят и
// не используется, поэтому проверки перевода и подписки красные на `expect`, а
// проверки «прежние строки на en» и «состояние сохраняется» зелёные. Русские
// строки — по глоссарию («провайдер», «ключ», «модель», «хранилище секретов»,
// «только чтение», «проверить»); остальные — вне глоссария (отчёт задачи 4.1).
// Команды (`codelab secret migrate`), имена секретов и переменных, пути и
// имена провайдеров не переводятся (D7).

import 'dart:async';

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/app/language/app_language_cubit.dart'
    show AppStrings;
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:codelab_desktop/features/settings/application/provider_settings_cubit.dart';
import 'package:codelab_desktop/l10n/app_localizations.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_strings.dart';
import '../../../support/fake_provider_settings.dart';

const _home = '/home/u/.codelab';

final _remote = ConnectionProfile.webSocket(
  id: 'devbox',
  label: 'Devbox',
  uri: Uri.parse('wss://devbox:7420/acp?t=$leakMarker'),
);

const _foreign = ConnectionProfile.stdio(
  id: 'other',
  label: 'Other',
  command: 'python',
  args: ['-m', 'other_agent'],
);

Map<String, Object?> _two() => {
  'agent': {'default_model': 'anthropic/m'},
  'providers': {
    'anthropic': providerMap(
      kind: 'anthropic',
      baseUrl: null,
      secret: 'codelab/anthropic',
    ),
    'local': providerMap(
      baseUrl: 'http://localhost:11434/v1',
      models: ['qwen'],
    ),
  },
};

/// Текст «Key» раскрытой карточки: часть без шрифта и моноширинная часть
/// вместе, как их показывает страница (один случай — одно сообщение).
String _keyShown(ProviderRow row) => '${row.keyText}${row.keyMono ?? ''}';

void main() {
  late FakeAgentConfigStore store;
  late FakeProviderSettingsSession session;
  late FakeWorkspace workspace;
  late ConnectionProfile defaultProfile;
  late TestAppStrings strings;

  setUp(() {
    store = FakeAgentConfigStore(user: _two());
    session = FakeProviderSettingsSession(
      store,
      secrets: {'codelab/anthropic': leakMarker},
    );
    workspace = FakeWorkspace();
    defaultProfile = embeddedConnectionProfile;
    strings = TestAppStrings(AppLocalizationsEn());
    addTearDown(strings.close);
  });

  ProviderSettingsCubit make(
    AppStrings? port, {
    Map<String, String> environment = const {'HOME': '/home/u'},
    String? home = _home,
    Future<ProviderSettingsSession> Function()? open,
  }) {
    final cubit = ProviderSettingsCubit(
      workspace: workspace,
      defaultProfile: () async => defaultProfile,
      open: (access, env) async => (open ?? () async => session)(),
      environment: environment,
      codelabHome: home,
      projectDirectory: () => '/work/app',
      now: () => DateTime(2026, 11, 6, 14, 1),
      strings: port,
    );
    addTearDown(cubit.close);
    return cubit;
  }

  ProviderSettingsReady now(ProviderSettingsCubit cubit) =>
      cubit.state as ProviderSettingsReady;

  ProviderRow row(ProviderSettingsCubit cubit, String id) =>
      now(cubit).rows.firstWhere((r) => r.id == id);

  Future<void> switchTo(AppLocalizations next) async {
    strings.emit(next);
    await pumpEventQueue();
  }

  group('FixedAppStrings(en): прежние строки', () {
    final fixedEn = FixedAppStrings(AppLocalizationsEn());

    test('подписи строк, статус ключа и подсказки', () async {
      store.user = {
        'providers': {
          'anthropic': providerMap(secret: 'codelab/anthropic'),
          'openai': providerMap(env: 'OPENAI_API_KEY'),
          'lit': {...providerMap(), 'api_key': leakMarker},
          'g': providerMap(kind: 'gemini', baseUrl: null, env: 'G'),
        },
      };
      final cubit = make(fixedEn, environment: {'OPENAI_API_KEY': leakMarker});
      await cubit.reload();

      expect(
        row(cubit, 'anthropic').subtitle,
        'anthropic · OpenAI-compatible · https://h.example/v1 · Key: in file · '
        '1 model',
      );
      expect(row(cubit, 'openai').keyLabel, 'Key: env OPENAI_API_KEY (set)');
      expect(
        _keyShown(row(cubit, 'anthropic')),
        'In file as codelab/anthropic',
      );
      expect(
        _keyShown(row(cubit, 'openai')),
        'Environment variable OPENAI_API_KEY (set)',
      );
      expect(_keyShown(row(cubit, 'lit')), 'In the config file (plain text)');
      expect(
        row(cubit, 'lit').keyHint,
        'The key is written in config.yaml. Move it to the secret store: '
        'codelab secret migrate.',
      );
      expect(
        row(cubit, 'g').checkHint,
        'Check is not available for gemini providers yet.',
      );
      expect(row(cubit, 'g').subtitle, contains('· Gemini ·'));
    });

    test('«Read-only» и нечитаемый конфиг', () async {
      defaultProfile = _remote;
      final remote = make(fixedEn);
      await remote.reload();
      final notice = remote.state as ProviderSettingsReadOnly;
      expect(notice.notice, 'Read-only: this agent runs on wss://devbox:7420.');
      expect(
        notice.hint,
        'Change providers and MCP on that host: codelab provider add, codelab '
        'mcp add, codelab config set.',
      );

      defaultProfile = embeddedConnectionProfile;
      final noHome = make(fixedEn, home: '');
      await noHome.reload();
      expect((noHome.state as ProviderSettingsUnreadable).problems, [
        'The CodeLab home folder is not available.',
      ]);
    });
  });

  group('TestAppStrings: строки провайдеров', () {
    test('подпись строки: тип, адрес, ключ и число моделей на ru', () async {
      final cubit = make(strings);
      await cubit.reload();
      expect(
        row(cubit, 'anthropic').subtitle,
        'anthropic · Anthropic · Key: in file · 1 model',
      );

      await switchTo(AppLocalizationsRu());

      expect(
        row(cubit, 'anthropic').subtitle,
        'anthropic · Anthropic · Ключ: в хранилище file · 1 модель',
      );
      expect(
        row(cubit, 'local').subtitle,
        'local · OpenAI-compatible · http://localhost:11434/v1 · Без ключа · '
        '1 модель',
      );

      await switchTo(AppLocalizationsEn());
      expect(
        row(cubit, 'anthropic').subtitle,
        'anthropic · Anthropic · Key: in file · 1 model',
      );
    });

    test('число моделей склоняется: 2 модели, 5 моделей (D8)', () async {
      store.user = {
        'providers': {
          'two': providerMap(models: ['a', 'b'], env: 'K'),
          'five': providerMap(models: ['a', 'b', 'c', 'd', 'e'], env: 'K'),
        },
      };
      strings = TestAppStrings(AppLocalizationsRu());
      final cubit = make(strings);
      await cubit.reload();

      expect(row(cubit, 'two').subtitle, endsWith('· 2 модели'));
      expect(row(cubit, 'five').subtitle, endsWith('· 5 моделей'));
    });

    test('провайдер из файла проекта: «определён в <путь>» одним '
        'сообщением', () async {
      store.project = {
        'providers': {
          'team': providerMap(models: ['big']),
        },
      };
      strings = TestAppStrings(AppLocalizationsRu());
      final cubit = make(strings);
      await cubit.reload();

      expect(
        row(cubit, 'team').subtitle,
        endsWith('· определён в ${FakeAgentConfigStore.projectPath}'),
      );
    });

    test('статус ключа и строка «Key»: хранилище, переменная, файл, нет '
        'ключа — каждый одним сообщением (нет склейки)', () async {
      store.user = {
        'providers': {
          'stored': providerMap(secret: 'codelab/stored'),
          'missing': providerMap(secret: 'codelab/missing'),
          'env': providerMap(env: 'OPENAI_API_KEY'),
          'envUnset': providerMap(env: 'OTHER_KEY'),
          'lit': {...providerMap(), 'api_key': leakMarker},
          'none': providerMap(baseUrl: 'http://localhost:1/v1'),
        },
      };
      session.secrets['codelab/stored'] = leakMarker;
      strings = TestAppStrings(AppLocalizationsRu());
      final cubit = make(strings, environment: {'OPENAI_API_KEY': leakMarker});
      await cubit.reload();

      expect(row(cubit, 'stored').keyLabel, 'Ключ: в хранилище file');
      expect(_keyShown(row(cubit, 'stored')), 'В file как «codelab/stored»');
      expect(row(cubit, 'missing').keyLabel, 'Ключ: нет в хранилище file');
      expect(
        _keyShown(row(cubit, 'missing')),
        'Нет в file как «codelab/missing»',
      );
      expect(
        row(cubit, 'env').keyLabel,
        'Ключ: переменная OPENAI_API_KEY (задана)',
      );
      expect(
        _keyShown(row(cubit, 'env')),
        'Переменная окружения OPENAI_API_KEY (задана)',
      );
      expect(
        _keyShown(row(cubit, 'envUnset')),
        'Переменная окружения OTHER_KEY (не задана)',
      );
      // security: открытый текстом ключ в конфиге.
      expect(
        _keyShown(row(cubit, 'lit')),
        'В файле конфигурации (открытым текстом)',
      );
      expect(row(cubit, 'none').keyLabel, 'Без ключа');
      expect(_keyShown(row(cubit, 'none')), 'Без ключа');
      // Значение ключа на экран не попадает ни на одном языке (SETUP-1).
      expect(
        [
          for (final r in now(cubit).rows) '${r.subtitle}${_keyShown(r)}',
        ].join(),
        isNot(contains(leakMarker)),
      );
    });

    test('подсказки кнопок и строки: литеральный ключ (security), вид без '
        'проверки, последний провайдер, несколько файлов', () async {
      store.user = {
        'providers': {
          'only': {...providerMap(), 'api_key': leakMarker},
        },
      };
      strings = TestAppStrings(AppLocalizationsRu());
      var cubit = make(strings);
      await cubit.reload();
      expect(
        row(cubit, 'only').keyHint,
        'Ключ записан в config.yaml. Перенесите его в хранилище секретов: '
        'codelab secret migrate.',
      );
      expect(
        row(cubit, 'only').removeHint,
        'Агенту нужен хотя бы один провайдер. Сначала добавьте другого.',
      );

      store.user = {
        'providers': {
          'g': providerMap(kind: 'gemini', baseUrl: null, env: 'G'),
        },
      };
      cubit = make(strings);
      await cubit.reload();
      expect(
        row(cubit, 'g').checkHint,
        'Проверка для провайдеров gemini пока недоступна.',
      );

      store
        ..user = _two()
        ..projectLocal = {
          'providers': {
            'local': {'base_url': 'http://localhost:9999/v1'},
          },
        };
      cubit = make(strings);
      await cubit.reload();
      expect(
        row(cubit, 'local').editHint,
        'Этот провайдер определён в нескольких файлах конфигурации. '
        'Измените его там.',
      );
    });

    test('неизвестный вид провайдера: «Unknown kind» переводится, '
        'имя вида — нет', () async {
      store.user = {
        'providers': {
          'x': {...providerMap(env: 'K'), 'kind': 'future-kind'},
        },
      };
      strings = TestAppStrings(AppLocalizationsRu());
      final cubit = make(strings);
      await cubit.reload();

      // Вид, незнакомый app, показывается как есть: это значение провода.
      expect(row(cubit, 'x').subtitle, contains('future-kind'));
    });
  });

  group('TestAppStrings: итоги проверок хранятся данными', () {
    test('успех: метка и подробность на ru, затем обратно', () async {
      session.checkResult = () async =>
          const CheckOk([RemoteModel('a'), RemoteModel('b'), RemoteModel('c')]);
      final cubit = make(strings);
      await cubit.reload();
      await cubit.check('local');
      expect(row(cubit, 'local').check.label, 'ok, 3 models');

      await switchTo(AppLocalizationsRu());

      final check = row(cubit, 'local').check;
      expect(check.label, 'успешно, 3 модели');
      expect(check.detail, startsWith('14:01 · 3 модели · '));
      expect(check.detail, endsWith(' мс'));

      await switchTo(AppLocalizationsEn());
      expect(row(cubit, 'local').check.label, 'ok, 3 models');
    });

    test('отказы: тег и подробность с кодом HTTP, команды и коды без '
        'перевода', () async {
      const labels = {
        ProviderCheckFailureKind.unauthorized: 'не авторизован',
        ProviderCheckFailureKind.notFound: 'не найдено',
        ProviderCheckFailureKind.unreachable: 'недоступен',
        ProviderCheckFailureKind.timeout: 'тайм-аут',
        ProviderCheckFailureKind.tlsError: 'ошибка TLS',
        ProviderCheckFailureKind.badResponse: 'неверный ответ',
      };
      strings = TestAppStrings(AppLocalizationsRu());
      final cubit = make(strings);
      await cubit.reload();
      for (final MapEntry(:key, :value) in labels.entries) {
        session.checkResult = () async => CheckFailure(
          ProviderCheckFailure(kind: key, statusCode: 401, message: 'x'),
        );
        await cubit.check('local');
        final check = row(cubit, 'local').check;
        expect(check.label, value, reason: key.name);
        expect(check.detail, '14:01 · $value (HTTP 401)', reason: key.name);
      }
    });

    test('ключ не найден: запрос не отправляется, тег и подробность '
        'на ru', () async {
      store.user = {
        'providers': {'team': providerMap(secret: 'codelab/team')},
      };
      strings = TestAppStrings(AppLocalizationsRu());
      final cubit = make(strings);
      await cubit.reload();

      await cubit.check('team');

      expect(session.checks, isEmpty);
      final check = row(cubit, 'team').check;
      expect(check.label, 'Ключ: нет');
      expect(check.detail, 'Не проверялся: ключа нет');
    });

    test('«ещё не проверялся» и «проверка…» на ru', () async {
      final gate = Completer<ProviderCheckResult>();
      session.checkResult = () => gate.future;
      strings = TestAppStrings(AppLocalizationsRu());
      final cubit = make(strings);
      await cubit.reload();
      expect(row(cubit, 'local').check.label, 'не проверялся');
      expect(row(cubit, 'local').check.detail, 'Ещё не проверялся');

      final pending = cubit.check('local');
      expect(row(cubit, 'local').check.label, 'проверка…');
      expect(row(cubit, 'local').check.detail, 'Проверка…');

      gate.complete(const CheckCancelled());
      await pending;
    });

    test('идущая проверка: итог, пришедший после смены языка, сразу на '
        'новом языке (правило 1: не строка, а данные)', () async {
      final gate = Completer<ProviderCheckResult>();
      session.checkResult = () => gate.future;
      final cubit = make(strings);
      await cubit.reload();
      final pending = cubit.check('local');
      expect(row(cubit, 'local').check.label, 'checking…');

      await switchTo(AppLocalizationsRu());
      expect(row(cubit, 'local').check.label, 'проверка…');
      gate.complete(const CheckOk([RemoteModel('a')]));
      await pending;

      expect(row(cubit, 'local').check.label, 'успешно, 1 модель');
    });
  });

  group('TestAppStrings: «Read-only», нечитаемый конфиг', () {
    test('WebSocket-агент: заголовок без пути и запроса, подсказка с '
        'командами', () async {
      defaultProfile = _remote;
      final cubit = make(strings);
      await cubit.reload();

      await switchTo(AppLocalizationsRu());

      final state = cubit.state as ProviderSettingsReadOnly;
      expect(
        state.notice,
        'Только чтение: агент работает на wss://devbox:7420.',
      );
      expect(
        state.hint,
        'Изменить провайдеров и MCP можно на том хосте: codelab provider add, '
        'codelab mcp add, codelab config set.',
      );
      expect(state.notice, isNot(contains('/acp')));
    });

    test('сторонний stdio-агент: имя агента — плейсхолдер', () async {
      defaultProfile = _foreign;
      final cubit = make(strings);
      await cubit.reload();
      expect(
        (cubit.state as ProviderSettingsReadOnly).notice,
        'Provider settings are managed by python.',
      );

      await switchTo(AppLocalizationsRu());

      expect(
        (cubit.state as ProviderSettingsReadOnly).notice,
        'Настройками провайдеров управляет python.',
      );
    });

    test('нечитаемый конфиг: проблемы приложения переводятся, проблемы '
        'загрузчика остаются как есть (D7)', () async {
      store.omitUserLayer = true;
      final cubit = make(strings);
      await cubit.reload();
      expect((cubit.state as ProviderSettingsUnreadable).problems, [
        'The user config.yaml cannot be read.',
      ]);

      await switchTo(AppLocalizationsRu());

      expect((cubit.state as ProviderSettingsUnreadable).problems, [
        'Пользовательский config.yaml не удаётся прочитать.',
      ]);
    });

    test('нет домашней папки и сбой открытия сессии', () async {
      strings = TestAppStrings(AppLocalizationsRu());
      final noHome = make(strings, home: '');
      await noHome.reload();
      expect((noHome.state as ProviderSettingsUnreadable).problems, [
        'Домашняя папка CodeLab недоступна.',
      ]);

      final broken = make(
        strings,
        open: () async => throw StateError('cannot open'),
      );
      await broken.reload();
      expect((broken.state as ProviderSettingsUnreadable).problems, [
        'Не удаётся прочитать настройки агента.',
      ]);
    });
  });

  group('разовые сообщения (D5: типизированные, язык их не стирает)', () {
    test('баннер удаления остаётся после смены языка', () async {
      store.user = {
        'agent': {'default_model': 'local/qwen'},
        'providers': _two()['providers'],
      };
      final cubit = make(strings);
      await cubit.reload();
      expect(await cubit.remove('anthropic'), isTrue);
      final banner = now(cubit).banner;
      expect(banner, isNotNull);

      await switchTo(AppLocalizationsRu());

      expect(now(cubit).banner, isNotNull);
      expect(now(cubit).banner!.kind, banner!.kind);
    });

    test('отказ удаления последнего провайдера остаётся баннером', () async {
      store.user = {
        'providers': {'only': providerMap(env: 'K')},
      };
      final cubit = make(strings);
      await cubit.reload();
      await cubit.remove('only');
      // Кнопка недоступна, поэтому баннера нет; смена языка не создаёт его.
      expect(now(cubit).banner, isNull);

      await switchTo(AppLocalizationsRu());

      expect(now(cubit).banner, isNull);
    });
  });

  group('подписка на AppStrings (D5 правила 1–3; R3)', () {
    test('одна подписка с момента создания, снимается в close()', () async {
      final cubit = make(strings);
      expect(strings.subscriberCount, 1);

      await cubit.reload();
      await cubit.reload();
      workspace.emit(
        WorkspaceState(
          connection: const ConnectionView.connected(),
          profile: embeddedConnectionProfile,
        ),
      );
      await pumpEventQueue();
      expect(strings.subscriberCount, 1);

      await cubit.close();

      expect(strings.hasListener, isFalse);
    });

    test('после close событие языка не меняет состояние', () async {
      final cubit = make(strings);
      await cubit.reload();
      final before = cubit.state;
      await cubit.close();

      await switchTo(AppLocalizationsRu());

      expect(identical(cubit.state, before), isTrue);
    });

    test(
      'смена языка не обращается к агенту и не читает конфиг заново',
      () async {
        final cubit = make(strings);
        await cubit.reload();
        final snapshots = store.snapshots;
        final isSetCalls = session.isSetCalls.length;

        await switchTo(AppLocalizationsRu());

        expect(store.snapshots, snapshots);
        expect(session.isSetCalls, hasLength(isSetCalls));
        expect(store.applied, isEmpty);
        expect(row(cubit, 'anthropic').id, 'anthropic');
      },
    );
  });
}
