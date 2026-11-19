// Тесты задач 5.1c и 5.2 change `add-desktop-localization`: функции
// presentation подписей страниц «MCP servers», «Agents & modes» и «Skills &
// extensions» на `en` и `ru` (spec app-settings «Источник конфигурации на
// русском», «Таблица «Agent status» на русском», «Таблица определений
// агентов на русском», «Страница «Skills & extensions» на русском»; design.md
// D5 «Уточнение итерации 5», D7, D8).
//
// Почему функции, а не только виджеты: состояние Cubit-ов этих страниц
// типизировано (источник, `McpServerState`, `AgentRowStatus`, сообщения
// баннеров), а текст строит presentation. Каждая функция — чистая «(данные,
// язык)», поэтому её можно проверить без дерева виджетов на обоих каталогах.
//
// Ожидания `en` — прежние строки страниц (D3). Ожидания `ru` — по
// глоссарию §4 «Настройки II» (подписи источника, состояния сервера, статусы
// определений, области, пометка режима); фразы вне глоссария (баннеры,
// отказы навыков) проверяются без выдуманного перевода: `ru` отличается от
// `en`, не содержит английской основы и хвоста, а значения (имена, пути,
// команды) сохранены (D7). `en` у `ConfigSourceKind.extraFile` различается
// по странице: `file` на «Agents & modes» и `config` на «General» (D7).

import 'package:codelab_desktop/features/settings/application/agents_modes_messages.dart';
import 'package:codelab_desktop/features/settings/application/mcp_messages.dart';
import 'package:codelab_desktop/features/settings/application/skills_messages.dart';
import 'package:codelab_desktop/features/settings/presentation/agents_modes_texts.dart';
import 'package:codelab_desktop/features/settings/presentation/config_source_label.dart';
import 'package:codelab_desktop/features/settings/presentation/mcp_texts.dart';
import 'package:codelab_desktop/features/settings/presentation/skills_texts.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:codelab_embedded/codelab_embedded.dart' show McpServerState;
import 'package:codelab_setup/codelab_setup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = AppLocalizationsEn();
  final ru = AppLocalizationsRu();

  group('configSourceLabel: одна функция по ConfigSourceKind? (D7)', () {
    test(
      'en совпадает с прежними подписями «Agents & modes» и «General» (forGeneral)',
      () {
        expect(configSourceLabel(en, null), 'default');
        expect(configSourceLabel(en, ConfigSourceKind.user), 'user');
        expect(configSourceLabel(en, ConfigSourceKind.project), 'project');
        expect(configSourceLabel(en, ConfigSourceKind.projectLocal), 'local');
        // Файл `--config`: прежние подписи страниц различались — `file` на
        // «Agents & modes» и `config` на «General» (D7).
        expect(configSourceLabel(en, ConfigSourceKind.extraFile), 'file');
        expect(
          configSourceLabel(en, ConfigSourceKind.extraFile, forGeneral: true),
          'config',
        );
        expect(configSourceLabel(en, ConfigSourceKind.environment), 'env');
      },
    );

    test(
      'ru — по глоссарию: именительная форма, окружение и файл --config',
      () {
        expect(configSourceLabel(ru, null), 'по умолчанию');
        expect(configSourceLabel(ru, ConfigSourceKind.user), 'пользователь');
        expect(configSourceLabel(ru, ConfigSourceKind.project), 'проект');
        expect(
          configSourceLabel(ru, ConfigSourceKind.projectLocal),
          'локально',
        );
        expect(configSourceLabel(ru, ConfigSourceKind.extraFile), 'файл');
        expect(
          configSourceLabel(ru, ConfigSourceKind.environment),
          'окружение',
        );
      },
    );

    test('подписи всех видов на ru различны и ни одна не равна en', () {
      final kinds = <ConfigSourceKind?>[null, ...ConfigSourceKind.values];
      final labels = [for (final k in kinds) configSourceLabel(ru, k)];
      expect(labels.toSet().length, kinds.length);
      for (final kind in kinds) {
        expect(configSourceLabel(ru, kind), isNot(configSourceLabel(en, kind)));
      }
    });
  });

  group('mcpSourceLabel: подпись источника строки MCP-сервера', () {
    test('en: user, this project, defined in <file>', () {
      expect(mcpSourceLabel(en, ConfigSourceKind.user), 'user');
      expect(mcpSourceLabel(en, ConfigSourceKind.projectLocal), 'this project');
      expect(
        mcpSourceLabel(en, ConfigSourceKind.project, file: '~/app/.codelab/c'),
        'defined in ~/app/.codelab/c',
      );
      expect(
        mcpSourceLabel(en, ConfigSourceKind.extraFile, file: '/etc/c.yaml'),
        'defined in /etc/c.yaml',
      );
    });

    test(
      'ru: пользователь, этот проект, определён в <file>; путь как есть',
      () {
        expect(mcpSourceLabel(ru, ConfigSourceKind.user), 'пользователь');
        expect(
          mcpSourceLabel(ru, ConfigSourceKind.projectLocal),
          'этот проект',
        );
        expect(
          mcpSourceLabel(
            ru,
            ConfigSourceKind.project,
            file: '~/app/.codelab/c',
          ),
          'определён в ~/app/.codelab/c',
        );
        expect(
          mcpSourceLabel(ru, ConfigSourceKind.environment, file: 'env'),
          'определён в env',
        );
      },
    );
  });

  group('mcpServerStateText: состояние сервера и повтор (D5, D8)', () {
    test('en: прежние подписи', () {
      expect(mcpServerStateText(en, McpServerState.connected), 'connected');
      expect(mcpServerStateText(en, McpServerState.connecting), 'connecting');
      expect(mcpServerStateText(en, McpServerState.disabled), 'disabled');
      expect(mcpServerStateText(en, McpServerState.failed), 'failed');
      expect(
        mcpServerStateText(
          en,
          McpServerState.failed,
          retryIn: const Duration(seconds: 24),
        ),
        'failed · retry in 24 s',
      );
    });

    test('ru: по глоссарию, «с» без plural', () {
      expect(mcpServerStateText(ru, McpServerState.connected), 'подключён');
      expect(mcpServerStateText(ru, McpServerState.connecting), 'подключается');
      expect(mcpServerStateText(ru, McpServerState.disabled), 'отключён');
      expect(mcpServerStateText(ru, McpServerState.failed), 'сбой');
      for (final seconds in const [1, 2, 5, 21, 24]) {
        expect(
          mcpServerStateText(
            ru,
            McpServerState.failed,
            retryIn: Duration(seconds: seconds),
          ),
          'сбой · повтор через $seconds с',
          reason: '$seconds',
        );
      }
    });
  });

  group('mcpDraftProblemText: проблемы по коду (D6)', () {
    test('en совпадает с message моста для каждого кода', () {
      for (final code in McpDraftProblemCode.values) {
        final problem = McpDraftProblem.of(
          code,
          McpDraftField.name,
          argument: 'Authorization',
        );
        expect(
          mcpDraftProblemText(en, problem),
          problem.message,
          reason: code.name,
        );
      }
    });

    test('ru: каждый код переведён, имя ключа сохранено, английского нет', () {
      for (final code in McpDraftProblemCode.values) {
        final problem = McpDraftProblem.of(
          code,
          McpDraftField.name,
          argument: 'Authorization',
        );
        final text = mcpDraftProblemText(ru, problem);
        expect(text, isNotEmpty, reason: code.name);
        expect(text, isNot(problem.message), reason: code.name);
        if (problem.argument != null) {
          expect(text, contains('Authorization'), reason: code.name);
        }
      }
    });

    test('проблема без кода показывается как есть на любом языке', () {
      const foreign = McpDraftProblem(
        McpDraftField.name,
        'Foreign problem text.',
      );
      expect(mcpDraftProblemText(en, foreign), 'Foreign problem text.');
      expect(mcpDraftProblemText(ru, foreign), 'Foreign problem text.');
    });
  });

  group('mcpMessageLines: баннер страницы «MCP servers»', () {
    test('en: прежние строки сохранения, удаления и очистки секретов', () {
      expect(mcpMessageLines(en, const McpServerSavedMessage('github')), [
        'Server github saved.',
      ]);
      expect(
        mcpMessageLines(
          en,
          const McpServerSavedMessage('web', restartHint: true),
        ),
        [
          'Server web saved. It starts after Restart agent '
              '(Settings › Connection).',
        ],
      );
      expect(mcpMessageLines(en, const McpServerEnabledMessage('web')), [
        'Server web enabled. It starts after Restart agent '
            '(Settings › Connection).',
      ]);
      expect(
        mcpMessageLines(
          en,
          const McpServerRemovedMessage(
            'pg',
            secrets: [
              McpSecretNote('codelab/mcp/pg/a', SecretCleanup.kept),
              McpSecretNote('codelab/mcp/pg/b', SecretCleanup.stillReferenced),
              McpSecretNote('codelab/mcp/pg/c', SecretCleanup.failed),
              McpSecretNote('codelab/mcp/pg/d', SecretCleanup.deleted),
            ],
          ),
        ),
        [
          'Server pg removed.',
          'codelab/mcp/pg/a is kept: it was not created by this page.',
          'codelab/mcp/pg/b is kept because other settings still use it.',
          'codelab/mcp/pg/c could not be deleted. Delete it with: '
              'codelab secret delete codelab/mcp/pg/c',
        ],
      );
    });

    test('ru: команда secret delete и имена секретов без изменений, '
        'английских фраз нет', () {
      final lines = mcpMessageLines(
        ru,
        const McpServerRemovedMessage(
          'pg',
          secrets: [
            McpSecretNote('codelab/mcp/pg/a', SecretCleanup.kept),
            McpSecretNote('codelab/mcp/pg/b', SecretCleanup.stillReferenced),
            McpSecretNote('codelab/mcp/pg/c', SecretCleanup.failed),
          ],
        ),
      );
      expect(lines, hasLength(4));
      expect(lines.first, contains('pg'));
      expect(lines.first, isNot('Server pg removed.'));
      expect(lines[1], contains('codelab/mcp/pg/a'));
      expect(lines[2], contains('codelab/mcp/pg/b'));
      expect(lines[3], contains('codelab/mcp/pg/c'));
      expect(lines[3], contains('codelab secret delete codelab/mcp/pg/c'));
      final all = lines.join('\n');
      for (final english in const [
        'is kept',
        'could not be deleted',
        'removed.',
      ]) {
        expect(all, isNot(contains(english)), reason: english);
      }
    });

    test('ru: отказ хранилища — переведённый заголовок, причина как есть', () {
      final lines = mcpMessageLines(
        ru,
        const McpSecretNotStoredMessage(
          'keychain is locked',
          notRolledBack: ['codelab/mcp/pg/a'],
        ),
      );
      expect(lines.first, contains('keychain is locked'));
      expect(lines.first, isNot(contains('The secret was not stored')));
      expect(
        lines.join('\n'),
        contains('codelab secret delete codelab/mcp/pg/a'),
      );
    });

    test('ru: предупреждение записи и проблемы ядра — как есть под '
        'переведённым заголовком', () {
      final saved = mcpMessageLines(
        ru,
        const McpServerSavedMessage(
          'pg',
          warnings: ['mcp.servers[pg].env.URL: variable PG_URL is not set'],
        ),
      );
      expect(saved, hasLength(2));
      expect(saved.last, 'mcp.servers[pg].env.URL: variable PG_URL is not set');
      expect(saved.first, isNot('Server pg saved.'));

      final rejected = mcpMessageLines(
        ru,
        const McpWriteFailedMessage(
          McpWriteFailure.rejected,
          issues: 'mcp.servers: duplicate name',
        ),
      );
      expect(rejected.single, contains('mcp.servers: duplicate name'));
      expect(rejected.single, isNot(contains('The config was not saved')));
    });

    test('ru: отказ моста переведён для каждой причины', () {
      for (final reason in McpServerRefusal.values) {
        final en1 = mcpMessageLines(en, McpRefusedMessage(reason)).single;
        final ru1 = mcpMessageLines(ru, McpRefusedMessage(reason)).single;
        expect(en1, isNotEmpty, reason: reason.name);
        expect(ru1, isNotEmpty, reason: reason.name);
        expect(ru1, isNot(en1), reason: reason.name);
      }
    });
  });

  group('agentModeLabel и agentRowStatusText (D5, D7)', () {
    test('en: прежние подписи режима', () {
      expect(
        agentModeLabel(en, 'standard', blocksWriteAndExec: false),
        'standard',
      );
      expect(
        agentModeLabel(en, 'ask', blocksWriteAndExec: true),
        'ask (edits and commands blocked by plan)',
      );
    });

    test('ru: id режима без перевода, пометка переведена (glossary §4)', () {
      expect(
        agentModeLabel(ru, 'standard', blocksWriteAndExec: false),
        'standard',
      );
      expect(
        agentModeLabel(ru, 'ask', blocksWriteAndExec: true),
        'ask (правки и команды запрещены режимом plan)',
      );
    });

    test('en: статусы строки определения', () {
      expect(agentRowStatusText(en, AgentRowStatus.available), 'Available');
      expect(agentRowStatusText(en, AgentRowStatus.overridden), 'Overridden');
      expect(
        agentRowStatusText(
          en,
          AgentRowStatus.overridden,
          overriddenBy: '~/.codelab/agents/review.md',
        ),
        'Overridden by ~/.codelab/agents/review.md',
      );
      expect(
        agentRowStatusText(en, AgentRowStatus.modelNotConfigured),
        'Model not configured',
      );
      expect(agentRowStatusText(en, AgentRowStatus.error), 'Error');
      expect(
        agentRowStatusText(en, AgentRowStatus.error, line: 4),
        'Error · line 4',
      );
      expect(
        agentRowStatusText(en, AgentRowStatus.duplicate),
        'Not loaded: duplicate name',
      );
      expect(
        agentRowStatusText(en, AgentRowStatus.shadowed),
        'Shadowed by project',
      );
      expect(
        agentRowStatusText(en, AgentRowStatus.subagentsOff),
        'Subagents off',
      );
    });

    test('ru: статусы по глоссарию, число строки и путь сохранены', () {
      expect(agentRowStatusText(ru, AgentRowStatus.available), 'Доступно');
      expect(
        agentRowStatusText(ru, AgentRowStatus.overridden),
        'Переопределено',
      );
      expect(
        agentRowStatusText(
          ru,
          AgentRowStatus.overridden,
          overriddenBy: '~/.codelab/agents/review.md',
        ),
        'Переопределено: ~/.codelab/agents/review.md',
      );
      expect(
        agentRowStatusText(ru, AgentRowStatus.modelNotConfigured),
        'Модель не настроена',
      );
      expect(
        agentRowStatusText(ru, AgentRowStatus.error, line: 4),
        'Ошибка · строка 4',
      );
      expect(
        agentRowStatusText(ru, AgentRowStatus.duplicate),
        'Не загружено: повторяющееся имя',
      );
      expect(
        agentRowStatusText(ru, AgentRowStatus.shadowed),
        'Перекрыто проектом',
      );
      expect(
        agentRowStatusText(ru, AgentRowStatus.subagentsOff),
        'Субагенты отключены',
      );
    });

    test('agentRowScopeText: en как есть, ru по глоссарию', () {
      expect(agentRowScopeText(en, AgentRowScope.session), 'session');
      expect(agentRowScopeText(en, AgentRowScope.subagent), 'subagent');
      expect(agentRowScopeText(en, AgentRowScope.both), 'both');
      expect(agentRowScopeText(ru, AgentRowScope.session), 'сессия');
      expect(agentRowScopeText(ru, AgentRowScope.subagent), 'субагент');
      expect(agentRowScopeText(ru, AgentRowScope.both), 'сессия и субагент');
    });
  });

  group('agentsModesMessageText: целые фразы баннера записи (D5)', () {
    const ask = 'ask';

    test('en: три вида × три «когда применится», прежние строки', () {
      const cases = [
        (AgentsApplyWhen.now, '.'),
        (AgentsApplyWhen.afterRestart, ' after Restart agent.'),
        (AgentsApplyWhen.whenAgentStarts, ' when the agent starts.'),
      ];
      for (final (applyWhen, tail) in cases) {
        expect(
          agentsModesMessageText(
            en,
            AgentsSavedMessage(
              setting: AgentsModesSetting.effort,
              value: 'high',
              when: applyWhen,
            ),
          ),
          'Saved. New sessions use high$tail',
          reason: '${applyWhen.name} saved',
        );
        expect(
          agentsModesMessageText(
            en,
            AgentsSavedOverriddenMessage(
              setting: AgentsModesSetting.mode,
              target: ConfigLayer.user,
              source: ConfigSourceKind.projectLocal,
              value: ask,
              when: applyWhen,
              blocksWriteAndExec: true,
            ),
          ),
          'Saved to All projects; local overrides it: new sessions use '
          'ask (edits and commands blocked by plan)$tail',
          reason: '${applyWhen.name} overridden',
        );
        expect(
          agentsModesMessageText(
            en,
            AgentsSavedNarrowedMessage(
              target: ConfigLayer.projectLocal,
              value: 'plan',
              when: applyWhen,
            ),
          ),
          'Saved to This project only; the untrusted project overrides it: '
          'new sessions use plan$tail',
          reason: '${applyWhen.name} narrowed',
        );
      }
    });

    test('en: прочие баннеры', () {
      expect(
        agentsModesMessageText(
          en,
          const AgentsSavedOnlyMessage(ConfigLayer.projectLocal),
        ),
        'Saved to This project only.',
      );
      expect(
        agentsModesMessageText(en, const AgentsBypassStaleMessage()),
        'Settings changed while the dialog was open; bypass was not saved.',
      );
      expect(
        agentsModesMessageText(en, const AgentsNotSavedMessage()),
        'The config was not saved.',
      );
    });

    test('ru: каждая из девяти фраз целиком — без английской основы и хвоста, '
        'значения как есть', () {
      for (final when in AgentsApplyWhen.values) {
        final texts = {
          agentsModesMessageText(
            ru,
            AgentsSavedMessage(
              setting: AgentsModesSetting.effort,
              value: 'high',
              when: when,
            ),
          ),
          agentsModesMessageText(
            ru,
            AgentsSavedOverriddenMessage(
              setting: AgentsModesSetting.mode,
              target: ConfigLayer.user,
              source: ConfigSourceKind.projectLocal,
              value: ask,
              when: when,
              blocksWriteAndExec: true,
            ),
          ),
          agentsModesMessageText(
            ru,
            AgentsSavedNarrowedMessage(
              target: ConfigLayer.projectLocal,
              value: 'plan',
              when: when,
            ),
          ),
        };
        expect(texts, hasLength(3), reason: when.name);
        for (final text in texts) {
          expect(text, isNotEmpty);
          for (final english in const [
            'Saved',
            'New sessions',
            'new sessions',
            'Restart agent',
            'when the agent starts',
            'overrides it',
          ]) {
            expect(text, isNot(contains(english)), reason: '$english: $text');
          }
        }
        expect(texts.first, contains('high'));
        expect(texts.elementAt(1), contains('ask'));
        expect(texts.elementAt(1), contains('plan)'));
        expect(texts.elementAt(1), contains('локально'));
        expect(texts.last, contains('plan'));
      }
    });

    test('ru: «когда применится» различается в трёх фразах одного вида', () {
      final texts = {
        for (final when in AgentsApplyWhen.values)
          agentsModesMessageText(
            ru,
            AgentsSavedMessage(
              setting: AgentsModesSetting.effort,
              value: 'high',
              when: when,
            ),
          ),
      };
      expect(texts, hasLength(3));
    });
  });

  group('skillsRefusalText и skillSizeText (D5, D8)', () {
    test('en: прежние тексты отказов', () {
      expect(
        skillsRefusalText(en, const SkillsListNotEditable('~/p/.codelab/c')),
        'Set in ~/p/.codelab/c; edit that file.',
      );
      expect(
        skillsRefusalText(
          en,
          const SkillsListDisabledByProject('~/p/.codelab/c'),
        ),
        'Disabled by the project config (~/p/.codelab/c).',
      );
      expect(
        skillsRefusalText(
          en,
          const SkillsListUntrustedProject(),
          element: '.claude/skills',
        ),
        'Trust this project to read .claude/skills.',
      );
      expect(
        skillsRefusalText(en, const SkillsListUntrustedProject()),
        'Trust this project to read this folder.',
      );
      expect(
        skillsRefusalText(
          en,
          const SkillsListLayerUnreadable(ConfigLayer.user),
        ),
        'The config file of this layer cannot be read. Fix it first.',
      );
    });

    test('ru: переведено, путь и элемент папки как есть', () {
      final notEditable = skillsRefusalText(
        ru,
        const SkillsListNotEditable('~/p/.codelab/c'),
      );
      expect(notEditable, contains('~/p/.codelab/c'));
      expect(notEditable, isNot(contains('Set in')));
      final disabled = skillsRefusalText(
        ru,
        const SkillsListDisabledByProject('~/p/.codelab/c'),
      );
      expect(disabled, contains('~/p/.codelab/c'));
      expect(disabled, isNot(contains('Disabled by')));
      final untrusted = skillsRefusalText(
        ru,
        const SkillsListUntrustedProject(),
        element: '.claude/skills',
      );
      expect(untrusted, contains('.claude/skills'));
      expect(untrusted, isNot(contains('Trust this project')));
      expect(
        skillsRefusalText(
          ru,
          const SkillsListLayerUnreadable(ConfigLayer.user),
        ),
        isNot(contains('cannot be read')),
      );
    });

    test('баннер и подсказка — один текст на языке: сообщение отказа даёт тот '
        'же текст, что и функция', () {
      const refusal = SkillsListNotEditable('~/p/.codelab/c');
      expect(
        skillsMessageText(ru, const SkillsRefusedMessage(refusal)),
        skillsRefusalText(ru, refusal),
      );
      expect(
        skillsMessageText(
          en,
          const SkillsRefusedMessage(
            SkillsListUntrustedProject(),
            element: '.claude/skills',
          ),
        ),
        'Trust this project to read .claude/skills.',
      );
    });

    test('размер: единицы из каталога, число с точкой без локали (D8)', () {
      expect(skillSizeText(en, 512), '512 B');
      expect(skillSizeText(en, 4915), '4.8 KB');
      expect(skillSizeText(en, 1331), '1.3 KB');
      expect(skillSizeText(en, 3 * 1024 * 1024), '3.0 MB');
      expect(skillSizeText(ru, 512), '512 Б');
      expect(skillSizeText(ru, 4915), '4.8 КБ');
      expect(skillSizeText(ru, 1331), '1.3 КБ');
      expect(skillSizeText(ru, 3 * 1024 * 1024), '3.0 МБ');
    });

    test('баннеры записи списков навыков: en прежние, ru переведены', () {
      expect(
        skillsMessageText(en, const SkillsOpenFailedMessage('/p/.codelab')),
        'Could not open /p/.codelab.',
      );
      expect(
        skillsMessageText(en, const SkillsNotSavedMessage()),
        'The config was not saved.',
      );
      expect(
        skillsMessageText(en, const SkillsInlineSecretMessage('skills.x')),
        'The config was not saved: skills.x must not hold a literal secret.',
      );
      final opened = skillsMessageText(
        ru,
        const SkillsOpenFailedMessage('/p/.codelab'),
      );
      expect(opened, contains('/p/.codelab'));
      expect(opened, isNot(contains('Could not open')));
      final rejected = skillsMessageText(
        ru,
        const SkillsRejectedMessage('skills.x: bad value'),
      );
      expect(rejected, contains('skills.x: bad value'));
      expect(rejected, isNot(contains('The config was not saved')));
    });
  });
}
