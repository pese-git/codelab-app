// Диагностика «Copy diagnostics» (задача 5.7 change `add-app-general-page`;
// spec app-settings «Диагностика для отчёта без секретов и путей», сценарии
// «Ничего лишнего в буфере» и «Текст не зависит от языка»; design.md D12).
//
// Реализация — задача 5.8 change `add-app-general-page`.
//
// Защита от утечки — отбор по белому списку: в отчёт попадают только
// фиксированные строки из перечня spec. Поэтому тесты, кроме точного текста,
// кладут маркеры (`sk-test-leak-…`, имя пользователя в пути, порт, id
// профиля) во все входы и проверяют, что каждая строка отчёта подходит под
// фиксированный образец, а маркеров, путей, URL, имён профилей и
// переменных окружения в тексте нет.

import 'package:codelab_desktop/core/platform/app_language_preferences.dart';
import 'package:codelab_desktop/features/settings/application/about_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Все пути, адреса и секреты, которые есть во входах и не должны дойти до
/// отчёта (сценарий «Ничего лишнего в буфере»).
const _leaks = [
  'sk-test-leak-0123456789',
  'devbox',
  '7420',
  '/acp',
  'alice',
  '/Users',
  'codelab-test',
  'wss://',
  'https://',
  'MARKER_ENV',
  'Library',
  'logs',
];

const _about = AboutInfo(
  version: '0.1.0',
  os: 'macOS',
  arch: 'arm64',
  embeddedAgentVersion: '0.2.3',
  licenseName: 'MIT',
  licenseCopyright: 'Copyright (c) 2026 alice',
  configHome: '/Users/alice/.codelab-test',
  logDirectory: '/Users/alice/Library/Application Support/CodeLab/logs',
);

DiagnosticsContext _context({
  DiagnosticsConnection connection = DiagnosticsConnection.websocket,
  DiagnosticsConnectionState state = DiagnosticsConnectionState.connected,
  DiagnosticsAccess access = DiagnosticsAccess.remoteReadOnly,
  String locale = 'ru',
  AppLanguagePreference preference = AppLanguagePreference.ru,
  bool custom = true,
}) => DiagnosticsContext(
  connection: connection,
  connectionState: state,
  access: access,
  locale: locale,
  languagePreference: preference,
  customConfigHome: custom,
);

List<String> _lines(String report) =>
    report.trim().split('\n').map((l) => l.trimRight()).toList();

/// Образцы строк отчёта: ничего вне перечня spec в отчёте быть не может.
final _patterns = [
  RegExp(r'^CodeLab \d+\.\d+\.\d+$'),
  RegExp(r'^OS: (macOS|Linux|Windows) (arm64|x64)$'),
  RegExp(r'^Embedded agent: \d+\.\d+\.\d+$'),
  RegExp(r'^UI language: (en|ru) \(preference: (system|en|ru)\)$'),
  RegExp(
    r'^Connection: (embedded|stdio|websocket) · '
    r'(connecting|connected|reconnecting|failed|disconnected)$',
  ),
  RegExp(r'^Agent settings: (editable|remote-read-only|not-managed)$'),
  RegExp(r'^Config folder: (default|custom)$'),
];

void main() {
  group('состав и порядок строк', () {
    test('все семь строк по перечню spec, в этом порядке', () {
      final report = diagnosticsReportOf(_about, _context());

      expect(_lines(report), [
        'CodeLab 0.1.0',
        'OS: macOS arm64',
        'Embedded agent: 0.2.3',
        'UI language: ru (preference: ru)',
        'Connection: websocket · connected',
        'Agent settings: remote-read-only',
        'Config folder: custom',
      ]);
    });

    test('каждый вид подключения и состояние', () {
      for (final kind in DiagnosticsConnection.values) {
        for (final state in DiagnosticsConnectionState.values) {
          final report = diagnosticsReportOf(
            _about,
            _context(connection: kind, state: state),
          );

          expect(
            _lines(report),
            contains('Connection: ${kind.name} · ${state.name}'),
            reason: '${kind.name} / ${state.name}',
          );
        }
      }
    });

    test('каждый вид доступа к настройкам агента', () {
      const expected = {
        DiagnosticsAccess.editable: 'editable',
        DiagnosticsAccess.remoteReadOnly: 'remote-read-only',
        DiagnosticsAccess.notManaged: 'not-managed',
      };
      for (final entry in expected.entries) {
        final report = diagnosticsReportOf(_about, _context(access: entry.key));

        expect(
          _lines(report),
          contains('Agent settings: ${entry.value}'),
          reason: entry.key.name,
        );
      }
    });

    test('Config folder: default и custom — только признак, не путь', () {
      expect(
        _lines(diagnosticsReportOf(_about, _context(custom: false))),
        contains('Config folder: default'),
      );
      expect(
        _lines(diagnosticsReportOf(_about, _context(custom: true))),
        contains('Config folder: custom'),
      );
    });

    test('версии и платформа берутся из AboutInfo', () {
      const other = AboutInfo(
        version: '2.4.6',
        os: 'Linux',
        arch: 'x64',
        embeddedAgentVersion: '9.8.7',
        licenseName: 'MIT',
        licenseCopyright: 'Copyright (c) 2026 x',
        configHome: '~/.codelab',
        logDirectory: '/var/log/x',
        thirdPartyNotices: '',
      );

      final lines = _lines(diagnosticsReportOf(other, _context()));

      expect(lines, contains('CodeLab 2.4.6'));
      expect(lines, contains('OS: Linux x64'));
      expect(lines, contains('Embedded agent: 9.8.7'));
    });
  });

  group('язык (сценарий «Текст не зависит от языка»)', () {
    test('русский интерфейс: язык в строке, подписи английские', () {
      final report = diagnosticsReportOf(_about, _context());

      expect(_lines(report), contains('UI language: ru (preference: ru)'));
      expect(report, isNot(matches(RegExp(r'[А-Яа-яЁё]'))));
    });

    test('выбор system при применённом en', () {
      final report = diagnosticsReportOf(
        _about,
        _context(locale: 'en', preference: AppLanguagePreference.system),
      );

      expect(_lines(report), contains('UI language: en (preference: system)'));
    });

    test('смена языка меняет только строку языка', () {
      final ru = _lines(diagnosticsReportOf(_about, _context()));
      final en = _lines(
        diagnosticsReportOf(
          _about,
          _context(locale: 'en', preference: AppLanguagePreference.en),
        ),
      );

      expect(
        [
          for (final l in ru)
            if (!l.startsWith('UI language:')) l,
        ],
        [
          for (final l in en)
            if (!l.startsWith('UI language:')) l,
        ],
      );
      expect(en, contains('UI language: en (preference: en)'));
    });
  });

  group('ничего лишнего в буфере (D12)', () {
    test('в тексте нет путей, адресов, секретов и маркеров', () {
      final report = diagnosticsReportOf(_about, _context());

      expect(report, isNotEmpty);
      for (final leak in _leaks) {
        expect(report, isNot(contains(leak)), reason: leak);
      }
      // Путь без маркеров: ни разделителей каталогов, ни `~`.
      expect(report, isNot(contains('/')));
      expect(report, isNot(contains(r'\')));
      expect(report, isNot(contains('~')));
      expect(report, isNot(contains('://')));
    });

    test('каждая строка подходит под фиксированный образец', () {
      for (final kind in DiagnosticsConnection.values) {
        for (final access in DiagnosticsAccess.values) {
          final lines = _lines(
            diagnosticsReportOf(
              _about,
              _context(connection: kind, access: access),
            ),
          );

          expect(lines, hasLength(_patterns.length));
          for (var i = 0; i < lines.length; i++) {
            expect(
              lines[i],
              matches(_patterns[i]),
              reason: 'строка ${i + 1}: ${lines[i]}',
            );
          }
        }
      }
    });

    test('поля AboutInfo, которых нет в перечне, в отчёт не попадают', () {
      final report = diagnosticsReportOf(_about, _context());

      expect(report, isNotEmpty);
      expect(report, isNot(contains(_about.licenseCopyright)));
      expect(report, isNot(contains(_about.configHome)));
      expect(report, isNot(contains(_about.logDirectory)));
      expect(report, isNot(contains(_about.thirdPartyNotices)));
      expect(report, isNot(contains('MIT')));
    });
  });
}
