import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/widget_previews.dart';

import '../atomics/atomics.dart';
import '../l10n/codelab_localizations.dart';
import '../molecules/molecules.dart';
import 'codelab_activity_bar.dart';
import 'codelab_agents_pane.dart';
import 'codelab_app_bar.dart';
import 'codelab_approval_prompt.dart';
import 'codelab_command_palette_surface.dart';
import 'codelab_connection_screen.dart';
import 'codelab_file_preview.dart';
import 'codelab_file_tree.dart';
import 'codelab_open_project_screen.dart';
import 'codelab_progress_checklist.dart';
import 'codelab_session_pane_header.dart';
import 'codelab_session_sidebar.dart';
import 'codelab_shortcut_table.dart';
import 'codelab_settings_navigation.dart';
import 'codelab_start_screen.dart';
import 'codelab_status_table.dart';
import 'codelab_terminal_pane.dart';
import 'codelab_tool_dock.dart';
import 'codelab_transcript_panel.dart';
import 'codelab_transcript_row.dart';
import 'codelab_usage_pane.dart';
import 'codelab_workbench_layout.dart';

const codelabOrganismPreviewGroup = 'ACP organisms';

@Preview(
  name: 'Status table',
  group: codelabOrganismPreviewGroup,
  size: Size(820, 320),
)
Widget codelabStatusTablePreview() {
  return const _AcpOrganismPreviewSurface(child: _StatusTableSample());
}

@Preview(
  name: 'Status table dark',
  group: codelabOrganismPreviewGroup,
  size: Size(820, 320),
  brightness: Brightness.dark,
)
Widget codelabStatusTableDarkPreview() {
  return const _AcpOrganismPreviewSurface(
    brightness: Brightness.dark,
    child: _StatusTableSample(),
  );
}

/// Пример панели «Agent status» (артборд `Mcp`): подключённый сервер, сбой с
/// повтором и выключенный сервер без действия.
class _StatusTableSample extends StatelessWidget {
  const _StatusTableSample();

  @override
  Widget build(BuildContext context) {
    return CodeLabStatusTable(
      columns: const ['SERVER', 'STATE', 'TOOLS', 'LAST ERROR'],
      rows: [
        CodeLabStatusTableRow(
          cells: const [
            CodeLabStatusTableCell('github', mono: true),
            CodeLabStatusTableCell('connected', tone: CodeLabStatusTone.active),
            CodeLabStatusTableCell('42'),
            CodeLabStatusTableCell('—', muted: true),
          ],
          action: CodeLabStatusTableAction(
            label: 'Reconnect',
            onPressed: codelabPreviewReconnect,
          ),
        ),
        CodeLabStatusTableRow(
          cells: const [
            CodeLabStatusTableCell('postgres', mono: true),
            CodeLabStatusTableCell(
              'failed · retry in 24 s',
              tone: CodeLabStatusTone.danger,
            ),
            CodeLabStatusTableCell('0'),
            CodeLabStatusTableCell('ECONNREFUSED 127.0.0.1:5432', mono: true),
          ],
          action: CodeLabStatusTableAction(
            label: 'Reconnect',
            onPressed: codelabPreviewReconnect,
          ),
        ),
        const CodeLabStatusTableRow(
          cells: [
            CodeLabStatusTableCell('filesystem', mono: true),
            // Длинный статус переносится на вторую строку (`maxLines: 3`).
            CodeLabStatusTableCell(
              'failed · retry in 24 s after the connection was refused',
              tone: CodeLabStatusTone.danger,
              maxLines: 3,
            ),
            CodeLabStatusTableCell('—', muted: true),
            CodeLabStatusTableCell('—', muted: true),
          ],
        ),
        const CodeLabStatusTableRow(
          cells: [
            CodeLabStatusTableCell('playwright', mono: true),
            CodeLabStatusTableCell('disabled', tone: CodeLabStatusTone.idle),
            CodeLabStatusTableCell('—', muted: true),
            CodeLabStatusTableCell('—', muted: true),
          ],
        ),
      ],
    );
  }
}

@Preview(
  name: 'Skills table',
  group: codelabOrganismPreviewGroup,
  size: Size(820, 300),
)
Widget codelabSkillsTablePreview() {
  return const _AcpOrganismPreviewSurface(child: _SkillsTableSample());
}

/// Пример таблицы навыков (артборд `Extensions`, change `add-app-skills-page`,
/// D12): описание второй строкой, теги, включённый и неактивный переключатели,
/// недоверенный текст с видимым `U+202E`.
class _SkillsTableSample extends StatelessWidget {
  const _SkillsTableSample();

  @override
  Widget build(BuildContext context) {
    return CodeLabStatusTable(
      columns: const ['SKILL', 'SOURCE'],
      columnFlex: const [3, 1],
      rows: [
        CodeLabStatusTableRow(
          cells: const [
            CodeLabStatusTableCell(
              'review',
              mono: true,
              secondary: 'Review a pull request and summarize follow-ups.',
              tags: [
                CodeLabStatusTableTag('Overrides user skill'),
                CodeLabStatusTableTag(
                  '1 warning',
                  tone: CodeLabTone.warning,
                  tooltip: 'SKILL.md: unknown frontmatter key',
                ),
              ],
              untrusted: true,
            ),
            CodeLabStatusTableCell('project'),
          ],
          toggle: CodeLabStatusTableToggle(
            value: true,
            label: 'Enable review',
            onChanged: (_) {},
          ),
        ),
        const CodeLabStatusTableRow(
          cells: [
            CodeLabStatusTableCell(
              'deploy\u202Egpj',
              mono: true,
              secondary: 'Deploy from a file written by another agent.',
              tags: [CodeLabStatusTableTag('Command only')],
              untrusted: true,
            ),
            CodeLabStatusTableCell('~/.agents/skills'),
          ],
          toggle: CodeLabStatusTableToggle(
            value: false,
            label: 'Enable deploy',
            onChanged: null,
            tooltip: 'Set in project config; edit it there.',
          ),
        ),
      ],
    );
  }
}

@Preview(
  name: 'Transcript panel conversation',
  group: codelabOrganismPreviewGroup,
  size: Size(820, 460),
)
Widget codelabTranscriptPanelPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 820,
      height: 460,
      child: CodeLabTranscriptPanel(
        rows: [
          CodeLabUserRow(
            id: 'user-1',
            text: 'Run analyzer and summarize any failures.',
          ),
          CodeLabThoughtRow(
            id: 'thought-1',
            text:
                'The analyzer runs per package; start with codelab_ui and '
                'report only errors.',
          ),
          CodeLabAgentTextRow(
            id: 'agent-1',
            text:
                'I will inspect the **workspace checks** first, starting with '
                '`dart analyze`:\n\n```bash\nfvm dart analyze '
                'packages/flutter/codelab_ui\n```',
          ),
          CodeLabAgentTextRow(
            id: 'agent-block-1',
            text: '```text\nMCP servers (1)\n  docs  connected  3 tools\n```',
          ),
          CodeLabToolCallRow(
            id: 'tool-1',
            status: CodeLabToolCallStatus.succeeded,
            label: 'Read',
            detail: 'lib/src/organisms/codelab_transcript_panel.dart',
            output: ['import \'package:fluent_ui/fluent_ui.dart\';'],
          ),
          CodeLabToolCallRow(
            id: 'tool-2',
            status: CodeLabToolCallStatus.running,
            label: 'Run',
            detail: 'fvm dart analyze packages/flutter/codelab_ui',
          ),
          CodeLabNoticeRow(
            id: 'notice-1',
            severity: CodeLabNoticeSeverity.info,
            body:
                'The agent cannot restore sessions; a new session was '
                'started.',
          ),
        ],
      ),
    ),
  );
}

@Preview(
  name: 'Transcript panel thinking',
  group: codelabOrganismPreviewGroup,
  size: Size(620, 300),
)
Widget codelabTranscriptPanelThinkingPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 620,
      height: 300,
      child: CodeLabTranscriptPanel(
        rows: [
          CodeLabUserRow(id: 'user-1', text: 'Why is the build slow?'),
          CodeLabThoughtRow(
            id: 'thought-1',
            streaming: true,
            text:
                'The build runs build_runner for every package.\n'
                'Only three packages have generated files.\n'
                'Check melos.yaml for the bootstrap hook.',
          ),
        ],
      ),
    ),
  );
}

@Preview(
  name: 'Transcript panel failed turn',
  group: codelabOrganismPreviewGroup,
  size: Size(620, 300),
)
Widget codelabTranscriptPanelFailedTurnPreview() {
  return _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 620,
      height: 300,
      child: CodeLabTranscriptPanel(
        rows: [
          const CodeLabUserRow(
            id: 'user-1',
            text: 'Run analyzer and summarize any failures.',
          ),
          CodeLabNoticeRow(
            id: 'prompt-error-1',
            severity: CodeLabNoticeSeverity.error,
            title: 'The model provider is unavailable',
            body: '503 Service Unavailable',
            details: 'ACP request session/prompt failed: Turn failed',
            action: CodeLabTranscriptAction(
              label: 'Retry',
              icon: FluentIcons.refresh,
              onPressed: () {},
            ),
          ),
        ],
      ),
    ),
  );
}

@Preview(
  name: 'Transcript panel verbose',
  group: codelabOrganismPreviewGroup,
  size: Size(620, 420),
)
Widget codelabTranscriptPanelVerbosePreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 620,
      height: 420,
      child: CodeLabTranscriptPanel(
        viewMode: CodeLabViewMode.verbose,
        rows: [
          CodeLabAgentTextRow(
            id: 'agent-verbose-1',
            text:
                'Analyzed protocol package, checked generated DTO boundaries, '
                'and kept the current session state unchanged while reporting '
                'the formatter-only diff.',
          ),
          CodeLabToolCallRow(
            id: 'tool-verbose-1',
            status: CodeLabToolCallStatus.failed,
            label: 'Read',
            detail: 'lib/main.dart',
            secondary: 'File not found: lib/main.dart',
          ),
        ],
      ),
    ),
  );
}

@Preview(
  name: 'Transcript panel with embedded approval',
  group: codelabOrganismPreviewGroup,
  size: Size(820, 460),
)
Widget codelabTranscriptPanelEmbeddedApprovalPreview() {
  return _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 820,
      height: 460,
      child: CodeLabTranscriptPanel(
        rows: [
          const CodeLabToolCallRow(
            id: 'tool-resolved-1',
            status: CodeLabToolCallStatus.succeeded,
            label: 'Edit',
            detail: 'jest.config.js',
            approval: CodeLabTranscriptApproval.resolved(
              label: 'Allow once',
              outcome: CodeLabApprovalOutcome.allowed,
            ),
          ),
          CodeLabToolCallRow(
            id: 'tool-pending-1',
            status: CodeLabToolCallStatus.queued,
            label: 'Run',
            detail: 'npm test --coverage',
            approval: CodeLabTranscriptApproval.pending(
              risk: CodeLabApprovalRisk.shell,
              reason: 'Agent wants to execute a build script.',
              command: 'npm test --coverage',
              rawInput: '{\n  "command": "npm test --coverage"\n}',
              onOptionSelected: codelabPreviewApprovalSelected,
              options: const [
                CodeLabApprovalOption(
                  id: 'allow_once',
                  label: 'Allow once',
                  kind: CodeLabApprovalOptionKind.allowOnce,
                  tone: CodeLabTone.success,
                ),
                CodeLabApprovalOption(
                  id: 'allow_always',
                  label: 'Always allow npm test',
                  kind: CodeLabApprovalOptionKind.allowAlways,
                  tone: CodeLabTone.success,
                ),
                CodeLabApprovalOption(
                  id: 'reject_once',
                  label: 'Reject',
                  kind: CodeLabApprovalOptionKind.rejectOnce,
                  tone: CodeLabTone.danger,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

@Preview(
  name: 'Approval prompt',
  group: codelabOrganismPreviewGroup,
  size: Size(620, 160),
)
Widget codelabApprovalPromptPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 620,
      child: CodeLabApprovalPrompt(
        reason: 'The agent wants to verify the Flutter UI package.',
        rawInput: '{\n  "command": "fvm dart run melos run analyze"\n}',
        onOptionSelected: codelabPreviewApprovalSelected,
        options: [
          CodeLabApprovalOption(
            id: 'allow_once',
            label: 'Allow once',
            kind: CodeLabApprovalOptionKind.allowOnce,
          ),
          CodeLabApprovalOption(
            id: 'allow_always',
            label: 'Always allow melos run analyze',
            kind: CodeLabApprovalOptionKind.allowAlways,
          ),
          CodeLabApprovalOption(
            id: 'reject_once',
            label: 'Reject',
            kind: CodeLabApprovalOptionKind.rejectOnce,
          ),
          CodeLabApprovalOption(
            id: 'reject_always',
            label: 'Always reject',
            kind: CodeLabApprovalOptionKind.rejectAlways,
          ),
        ],
      ),
    ),
  );
}

/// Пример экрана на русском: полоса одобрения с делегатом кита и `ru`
/// (`add-desktop-localization`, D4). Подписи вариантов — текст агента, они
/// остаются как пришли.
@Preview(
  name: 'Approval prompt (ru)',
  group: codelabOrganismPreviewGroup,
  size: Size(620, 160),
)
Widget codelabApprovalPromptRuPreview() {
  return const _AcpOrganismPreviewSurface(
    locale: Locale('ru'),
    child: SizedBox(
      width: 620,
      child: CodeLabApprovalPrompt(
        reason: 'The agent wants to verify the Flutter UI package.',
        rawInput: '{\n  "command": "fvm dart run melos run analyze"\n}',
        onOptionSelected: codelabPreviewApprovalSelected,
        options: [
          CodeLabApprovalOption(
            id: 'allow_once',
            label: 'Allow once',
            kind: CodeLabApprovalOptionKind.allowOnce,
          ),
          CodeLabApprovalOption(
            id: 'allow_always',
            label: 'Always allow melos run analyze',
            kind: CodeLabApprovalOptionKind.allowAlways,
          ),
          CodeLabApprovalOption(
            id: 'reject_once',
            label: 'Reject',
            kind: CodeLabApprovalOptionKind.rejectOnce,
          ),
          CodeLabApprovalOption(
            id: 'reject_always',
            label: 'Always reject',
            kind: CodeLabApprovalOptionKind.rejectAlways,
          ),
        ],
      ),
    ),
  );
}

/// Пример полосы одобрения с клавиатурным фокусом: рамка вместо подсказки
/// перехода (change `fix-approval-focus`, D4). Фокус ставится после первого
/// кадра, как это делает лента по «Go to approval». Обычное превью
/// «Approval prompt» показывает полосу без фокуса, с подсказкой.
@Preview(
  name: 'Approval prompt (focused)',
  group: codelabOrganismPreviewGroup,
  size: Size(620, 160),
)
Widget codelabApprovalPromptFocusedPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(width: 620, child: _FocusedApprovalPrompt()),
  );
}

/// Полоса одобрения, которой после первого кадра передан фокус.
///
/// Почему: фокус полосы нельзя задать параметром — он принадлежит её
/// `State` (D4, п. 3), а превью должно показать рамку.
/// Как использовать: только в превью; ищет узел полосы по
/// [CodeLabApprovalPrompt.barKey], как лента.
class _FocusedApprovalPrompt extends StatefulWidget {
  const _FocusedApprovalPrompt();

  @override
  State<_FocusedApprovalPrompt> createState() => _FocusedApprovalPromptState();
}

class _FocusedApprovalPromptState extends State<_FocusedApprovalPrompt> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Element? bar;
      void visit(Element element) {
        if (bar != null) return;
        if (element.widget.key == CodeLabApprovalPrompt.barKey) {
          bar = element;
          return;
        }
        element.visitChildren(visit);
      }

      (context as Element).visitChildren(visit);
      if (bar case final found?) {
        Focus.maybeOf(found, createDependency: false)?.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const CodeLabApprovalPrompt(
      reason: 'The agent wants to verify the Flutter UI package.',
      onOptionSelected: codelabPreviewApprovalSelected,
      options: [
        CodeLabApprovalOption(
          id: 'allow_once',
          label: 'Allow once',
          kind: CodeLabApprovalOptionKind.allowOnce,
        ),
        CodeLabApprovalOption(
          id: 'reject_once',
          label: 'Reject',
          kind: CodeLabApprovalOptionKind.rejectOnce,
        ),
      ],
    );
  }
}

@Preview(
  name: 'Activity bar — plan collapsed',
  group: codelabOrganismPreviewGroup,
  size: Size(620, 100),
)
Widget codelabActivityBarPlanCollapsedPreview() {
  return _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 620,
      child: CodeLabActivityBar(sections: [_previewPlanSection()]),
    ),
  );
}

@Preview(
  name: 'Activity bar — plan expanded',
  group: codelabOrganismPreviewGroup,
  size: Size(620, 320),
)
Widget codelabActivityBarPlanExpandedPreview() {
  return _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 620,
      child: CodeLabActivityBar(
        sections: [_previewPlanSection(initiallyExpanded: true)],
      ),
    ),
  );
}

CodeLabActivityBarSection _previewPlanSection({
  bool initiallyExpanded = false,
}) {
  final section = CodeLabProgressChecklist.section(
    id: 'plan',
    onDismiss: codelabPreviewDismissPlan,
    entries: const [
      CodeLabPlanEntry(
        content: 'Read auth module and locate token refresh call sites',
        status: CodeLabPlanEntryStatus.completed,
        priority: CodeLabPlanEntryPriority.medium,
      ),
      CodeLabPlanEntry(
        content: 'Reproduce the token refresh race condition',
        status: CodeLabPlanEntryStatus.completed,
        priority: CodeLabPlanEntryPriority.high,
      ),
      CodeLabPlanEntry(
        content: 'Run melos analyze to confirm no new lint issues',
        status: CodeLabPlanEntryStatus.inProgress,
        priority: CodeLabPlanEntryPriority.medium,
      ),
      CodeLabPlanEntry(
        content: 'Open PR for review',
        status: CodeLabPlanEntryStatus.pending,
        priority: CodeLabPlanEntryPriority.low,
      ),
    ],
  );

  return CodeLabActivityBarSection(
    id: section.id,
    headerBuilder: section.headerBuilder,
    bodyBuilder: section.bodyBuilder,
    initiallyExpanded: initiallyExpanded,
  );
}

void codelabPreviewDismissPlan() {}

@Preview(
  name: 'Connection screen',
  group: codelabOrganismPreviewGroup,
  size: Size(620, 360),
)
Widget codelabConnectionScreenPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 620,
      height: 360,
      child: CodeLabConnectionScreen(
        status: CodeLabConnectionStatus.disconnected,
        transportLabel: 'stdio',
        profileLabel: 'Codelab Agent',
        detail: 'codelab serve --stdio',
        description: 'Connect to a local ACP agent using the default profile.',
        onConnect: codelabPreviewConnect,
        onReconnect: codelabPreviewReconnect,
        onConfigureConnection: codelabPreviewEditProfile,
      ),
    ),
  );
}

/// Стартовый экран панели сессии с проектом (change `require-project-folder`,
/// D18): подсказка и «New session». Путь вымышленный.
@Preview(
  name: 'Start screen',
  group: codelabOrganismPreviewGroup,
  size: Size(620, 240),
)
Widget codelabStartScreenPreview() {
  return _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 620,
      height: 240,
      child: CodeLabStartScreen(
        message: 'Start a new session in app.',
        actionLabel: 'New session',
        onAction: codelabPreviewConnect,
      ),
    ),
  );
}

/// Экран «проект не выбран» (кадр 11a, change `add-empty-project-screen`,
/// D1): герой, пояснение, кнопка с подсказкой, зона, карточка агента и
/// InfoBar. Тёмная тема, язык `en`.
@Preview(
  name: 'Open project screen (dark)',
  group: codelabOrganismPreviewGroup,
  size: Size(620, 640),
)
Widget codelabOpenProjectScreenPreview() => _openProjectPreview(
  const Locale('en'),
  title: 'Open a project',
  description:
      'Choose the folder you want to work in. The agent starts in it, and '
      "sessions get it as their working directory. The agent can't read or "
      'write outside it.',
  openLabel: 'Open folder…',
  dropLabel: 'Drop a folder here to open it',
  dropHint: 'Files are not accepted — only a folder',
  agentName: 'Embedded agent',
  agentNote: 'Starts when you open a folder. Nothing runs before that.',
  settingsLinkLabel: 'Change in Settings › Connection',
  infoTitle: 'New session needs a folder',
  infoBody:
      'Ctrl+N without a project opens the same folder picker. Opened folders '
      'appear in the sidebar as recent projects.',
);

/// То же на языке `ru` (проверка длинных русских подписей).
@Preview(
  name: 'Open project screen (dark, ru)',
  group: codelabOrganismPreviewGroup,
  size: Size(620, 640),
)
Widget codelabOpenProjectScreenRuPreview() => _openProjectPreview(
  const Locale('ru'),
  title: 'Откройте проект',
  description:
      'Выберите папку, в которой хотите работать. Агент запускается в ней, '
      'а сессии получают её рабочей папкой. Агент не читает и не пишет вне неё.',
  openLabel: 'Открыть папку…',
  dropLabel: 'Бросьте папку сюда, чтобы открыть её',
  dropHint: 'Файлы не принимаются — только папка',
  agentName: 'Встроенный агент',
  agentNote: 'Запускается, когда вы откроете папку. До этого ничего не идёт.',
  settingsLinkLabel: 'Изменить в «Настройки › Подключение»',
  infoTitle: 'Для новой сессии нужна папка',
  infoBody:
      'Ctrl+N без проекта открывает тот же выбор папки. Открытые папки '
      'попадают в сайдбар как недавние проекты.',
);

Widget _openProjectPreview(
  Locale locale, {
  required String title,
  required String description,
  required String openLabel,
  required String dropLabel,
  required String dropHint,
  required String agentName,
  required String agentNote,
  required String settingsLinkLabel,
  required String infoTitle,
  required String infoBody,
}) {
  return _AcpOrganismPreviewSurface(
    brightness: Brightness.dark,
    locale: locale,
    child: SizedBox(
      width: 620,
      height: 640,
      child: CodeLabOpenProjectScreen(
        title: title,
        description: description,
        openLabel: openLabel,
        openShortcut: 'Ctrl+O',
        onOpen: codelabPreviewConnect,
        dropLabel: dropLabel,
        dropHint: dropHint,
        agentName: agentName,
        agentDetail: 'in-process · profile of this window',
        agentNote: agentNote,
        settingsLinkLabel: settingsLinkLabel,
        onOpenSettings: codelabPreviewConnect,
        infoTitle: infoTitle,
        infoBody: infoBody,
      ),
    ),
  );
}

/// Дерево файлов (артборд `Files`): раскрытая папка, ссылка наружу и строка
/// «… N more». Пути вымышленные, без данных пользователя.
@Preview(
  name: 'File tree',
  group: codelabOrganismPreviewGroup,
  size: Size(320, 260),
)
Widget codelabFileTreePreview() {
  return _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 320,
      height: 260,
      child: CodeLabFileTree(
        selectedPath: 'lib/main.dart',
        rows: const [
          CodeLabFileTreeRowData(
            relativePath: 'lib',
            name: 'lib',
            kind: CodeLabFileTreeRowKind.directory,
            expanded: true,
          ),
          CodeLabFileTreeRowData(
            relativePath: 'lib/main.dart',
            name: 'main.dart',
            kind: CodeLabFileTreeRowKind.file,
            depth: 1,
          ),
          CodeLabFileTreeRowData(
            relativePath: 'lib/#more',
            name: '… 4980 more',
            kind: CodeLabFileTreeRowKind.more,
            depth: 1,
          ),
          CodeLabFileTreeRowData(
            relativePath: 'docs',
            name: 'docs',
            kind: CodeLabFileTreeRowKind.directory,
            loading: true,
          ),
          CodeLabFileTreeRowData(
            relativePath: 'shared',
            name: 'shared',
            kind: CodeLabFileTreeRowKind.outsideLink,
          ),
          CodeLabFileTreeRowData(
            relativePath: 'README.md',
            name: 'README.md',
            kind: CodeLabFileTreeRowKind.file,
          ),
        ],
        onToggleDirectory: codelabPreviewFileTreeRow,
        onOpenFile: codelabPreviewFileTreeRow,
      ),
    ),
  );
}

/// Колбэк строк превью дерева: превью ничего не открывает.
void codelabPreviewFileTreeRow(CodeLabFileTreeRowData row) {}

/// Просмотр файла: текст с подсвеченной строкой и предупреждением о секретах.
@Preview(
  name: 'File preview',
  group: codelabOrganismPreviewGroup,
  size: Size(420, 260),
)
Widget codelabFilePreviewPreview() {
  return _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 420,
      height: 260,
      child: CodeLabFilePreview(
        relativePath: 'config/.env',
        maybeSecret: true,
        highlightLine: 2,
        onCopyPath: codelabPreviewCopyPath,
        content: const CodeLabFilePreviewContent.text(
          'EXAMPLE_NAME=demo\nEXAMPLE_FLAG=true\n',
        ),
      ),
    ),
  );
}

/// Просмотр двоичного файла: только пометка с размером.
@Preview(
  name: 'File preview binary',
  group: codelabOrganismPreviewGroup,
  size: Size(420, 160),
)
Widget codelabFilePreviewBinaryPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 420,
      height: 160,
      child: CodeLabFilePreview(
        relativePath: 'assets/logo.bin',
        content: CodeLabFilePreviewContent.binary('24 KB'),
      ),
    ),
  );
}

/// Колбэк «Copy path» превью: ничего не копирует.
void codelabPreviewCopyPath(String relativePath) {}

@Preview(
  name: 'Session sidebar',
  group: codelabOrganismPreviewGroup,
  size: Size(320, 420),
)
Widget codelabSessionSidebarPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 320,
      height: 420,
      child: CodeLabSessionSidebar(
        activeSessionId: 'session-2',
        onSessionSelected: codelabPreviewSessionSelected,
        onNewSession: codelabPreviewNewSession,
        projects: _previewProjects,
      ),
    ),
  );
}

@Preview(
  name: 'Command palette empty query',
  group: codelabOrganismPreviewGroup,
  size: Size(520, 360),
)
Widget codelabCommandPaletteEmptyQueryPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 520,
      height: 360,
      child: CodeLabCommandPaletteSurface(
        onActionSelected: codelabPreviewCommand,
      ),
    ),
  );
}

@Preview(
  name: 'Command palette filtered',
  group: codelabOrganismPreviewGroup,
  size: Size(520, 260),
)
Widget codelabCommandPaletteFilteredPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 520,
      height: 260,
      child: CodeLabCommandPaletteSurface(
        initialQuery: '/log',
        onActionSelected: codelabPreviewCommand,
      ),
    ),
  );
}

@Preview(
  name: 'Command palette selected',
  group: codelabOrganismPreviewGroup,
  size: Size(520, 360),
)
Widget codelabCommandPaletteSelectedPreview() {
  return const _AcpOrganismPreviewSurface(
    child: SizedBox(
      width: 520,
      height: 360,
      child: CodeLabCommandPaletteSurface(
        selectedActionId: 'permissions',
        onActionSelected: codelabPreviewCommand,
      ),
    ),
  );
}

@Preview(
  name: 'Workbench layout desktop',
  group: codelabOrganismPreviewGroup,
  size: Size(1180, 720),
)
Widget codelabWorkbenchLayoutPreview() {
  return _AcpOrganismPreviewSurface(child: _AcpPreviewWorkbench());
}

@Preview(
  name: 'Workbench layout medium',
  group: codelabOrganismPreviewGroup,
  size: Size(860, 720),
)
Widget codelabWorkbenchLayoutMediumPreview() {
  return _AcpOrganismPreviewSurface(child: _AcpPreviewWorkbench());
}

@Preview(
  name: 'Workbench layout narrow',
  group: codelabOrganismPreviewGroup,
  size: Size(430, 720),
)
Widget codelabWorkbenchLayoutNarrowPreview() {
  return _AcpOrganismPreviewSurface(child: _AcpPreviewWorkbench());
}

void codelabPreviewApprovalSelected(String optionId) {}

void codelabPreviewSessionSelected(String sessionId) {}

void codelabPreviewCommand(CodeLabCommandAction action) {}

void codelabPreviewNewSession() {}

void codelabPreviewPromptSubmitted(String prompt) {}

void codelabPreviewConnect() {}

void codelabPreviewReconnect() {}

void codelabPreviewEditProfile() {}

@Preview(
  name: 'Settings navigation',
  group: codelabOrganismPreviewGroup,
  size: Size(900, 420),
)
Widget codelabSettingsNavigationPreview() {
  // `NavigationView` требует Navigator и локализации, поэтому превью
  // собирается внутри собственного `FluentApp`.
  return FluentApp(
    debugShowCheckedModeBanner: false,
    home: CodeLabSettingsNavigation(
      items: const [
        CodeLabSettingsNavItem(
          id: 'connection',
          title: 'Connection',
          icon: FluentIcons.plug_connected,
          group: 'Agent',
        ),
        CodeLabSettingsNavItem(
          id: 'general',
          title: 'General',
          icon: FluentIcons.settings,
          group: 'App',
        ),
      ],
      selectedId: 'connection',
      onSelected: (_) {},
      onQueryChanged: (_) {},
      onBack: () {},
      child: const Padding(
        padding: EdgeInsets.all(24),
        child: CodeLabText('Page body', role: CodeLabTextRole.title),
      ),
    ),
  );
}

@Preview(
  name: 'Usage pane',
  group: codelabOrganismPreviewGroup,
  size: Size(440, 640),
)
Widget codelabUsagePanePreview() {
  return _AcpOrganismPreviewSurface(
    child: SingleChildScrollView(
      child: CodeLabUsagePane(
        title: 'This session',
        statusLine: 'Ledger: up to date · 12 records',
        statusHint: 'refreshed from the session journal (stale)',
        showRebuild: true,
        showExport: true,
        onRebuild: codelabPreviewCancel,
        onExport: codelabPreviewCancel,
        cards: const [
          CodeLabUsageCard(
            id: 'input',
            title: 'Input',
            value: '184.2k',
            detail: 'cache read 121.0k · write 18.4k',
          ),
          CodeLabUsageCard(
            id: 'output',
            title: 'Output',
            value: '9.8k',
            detail: 'reasoning 1.2k',
          ),
          CodeLabUsageCard(
            id: 'cost',
            title: 'Cost',
            value: r'~$2.26',
            detail: 'agent sent no usage for some steps',
            tone: CodeLabTone.warning,
          ),
          CodeLabUsageCard(
            id: 'turns',
            title: 'Turns · steps',
            value: '3 · 7',
            detail: 'avg 2.3 steps per turn',
          ),
        ],
        budget: const CodeLabUsageBudget(
          title: 'This turn',
          footnote:
              'When a limit is hit, the turn stops at the next step boundary.',
          rows: [
            CodeLabUsageBudgetRow(
              id: 'steps',
              label: 'Steps',
              value: '3 / 50',
              fill: 0.06,
            ),
            CodeLabUsageBudgetRow(
              id: 'tokens',
              label: 'Tokens',
              value: '92.0k / 200.0k',
              fill: 0.46,
              hint: 'input + output, including subagents',
            ),
            CodeLabUsageBudgetRow(
              id: 'cost',
              label: 'Cost',
              value: r'$0.41 / $0.50',
              fill: 0.82,
              tone: CodeLabTone.warning,
            ),
            CodeLabUsageBudgetRow(
              id: 'time',
              label: 'Time',
              value: '3:00 / 10:00',
              fill: 0.3,
            ),
          ],
        ),
        turns: const [
          CodeLabUsageRow(
            id: '3',
            label: '3 · “Fix the build”',
            input: '41.0k',
            output: '2.1k',
            cost: r'$0.0041',
            running: true,
            children: [
              CodeLabUsageRow(
                id: '3-0',
                label: 'step 1 · Read lib/main.dart',
                input: '20.0k',
                output: '600',
                cost: r'$0.002',
                hint: 'openai/gpt-5',
              ),
              CodeLabUsageRow(
                id: '3-1',
                label: 'step 2 · reply',
                input: '21.0k',
                output: '1.5k',
                cost: r'$0.0021',
              ),
            ],
          ),
          CodeLabUsageRow(
            id: '2',
            label: '2',
            input: '—',
            output: '—',
            cost: '—',
          ),
        ],
        models: const [
          CodeLabUsageRow(
            id: 'openai/gpt-5',
            label: 'openai / gpt-5',
            input: '184.2k',
            output: '9.8k',
            cost: r'$2.26',
          ),
        ],
      ),
    ),
  );
}

@Preview(
  name: 'Agents pane',
  group: codelabOrganismPreviewGroup,
  size: Size(620, 360),
)
Widget codelabAgentsPanePreview() {
  return _AcpOrganismPreviewSurface(
    child: CodeLabAgentsPane(
      counts: const {
        CodeLabAgentRowState.running: 1,
        CodeLabAgentRowState.done: 1,
      },
      selectedId: 'a1',
      rows: const [
        CodeLabAgentRow(
          id: 'a1',
          depth: 1,
          type: 'review',
          title: 'Review the change',
          state: CodeLabAgentRowState.running,
          time: '12s',
          calls: '3 tool calls',
        ),
        CodeLabAgentRow(
          id: 'a2',
          depth: 2,
          type: 'explore',
          title: 'Find auth code',
          state: CodeLabAgentRowState.done,
          time: '19s',
          calls: '2 tool calls',
          tokens: '10.2k',
        ),
      ],
      steps: const [
        CodeLabToolCallRow(
          id: 's1',
          status: CodeLabToolCallStatus.succeeded,
          label: 'Read',
          detail: 'lib/auth.dart',
        ),
      ],
    ),
  );
}

@Preview(
  name: 'Terminal pane',
  group: codelabOrganismPreviewGroup,
  size: Size(520, 260),
)
Widget codelabTerminalPanePreview() {
  return _AcpOrganismPreviewSurface(
    child: CodeLabTerminalPane(
      tabs: const [
        CodeLabTerminalTab(
          id: 'a',
          title: 'zsh',
          statusLabel: 'Running',
          statusTone: CodeLabTone.success,
        ),
        CodeLabTerminalTab(
          id: 'b',
          title: 'build',
          statusLabel: 'Exited 1',
          statusTone: CodeLabTone.warning,
        ),
      ],
      activeTabId: 'a',
      hasSession: true,
      disclosure: 'Commands run with your permissions.',
      onDisclosureClosed: codelabPreviewCancel,
      content: const ColoredBox(
        color: Color(0xFF1E1E1E),
        child: SizedBox.expand(),
      ),
    ),
  );
}

/// Таблица сочетаний страницы «Keyboard» на английском (change
/// `add-app-keyboard-page`, D6). Тексты передаёт app, здесь они фиктивные.
@Preview(
  name: 'Shortcut table',
  group: codelabOrganismPreviewGroup,
  size: Size(860, 360),
)
Widget codelabShortcutTablePreview() {
  return _AcpOrganismPreviewSurface(
    child: CodeLabShortcutTable(
      actionHeader: 'Action',
      shortcutHeader: 'Shortcut',
      whereHeader: 'Where',
      groups: _shortcutTableGroups(
        global: 'Global',
        approvals: 'Approvals',
        openPalette: 'Open the command palette',
        workbench: 'Workbench',
        allowAlways: 'Allow always',
        pendingApproval: 'Pending approval in focus',
      ),
    ),
  );
}

/// Тот же экран на русском: делегат кита переводит союз в подписи
/// альтернатив, клавиши не переводятся (D5).
@Preview(
  name: 'Shortcut table (ru)',
  group: codelabOrganismPreviewGroup,
  size: Size(860, 360),
)
Widget codelabShortcutTableRuPreview() {
  return _AcpOrganismPreviewSurface(
    locale: const Locale('ru'),
    child: CodeLabShortcutTable(
      actionHeader: 'Действие',
      shortcutHeader: 'Сочетание',
      whereHeader: 'Где',
      groups: _shortcutTableGroups(
        global: 'Общие',
        approvals: 'Одобрения',
        openPalette: 'Открыть палитру команд',
        workbench: 'Рабочее место',
        allowAlways: 'Всегда разрешать',
        pendingApproval: 'Ожидающее одобрение в фокусе',
      ),
    ),
  );
}

List<CodeLabShortcutTableGroup> _shortcutTableGroups({
  required String global,
  required String approvals,
  required String openPalette,
  required String workbench,
  required String allowAlways,
  required String pendingApproval,
}) => [
  CodeLabShortcutTableGroup(
    key: const ValueKey('preview-group-global'),
    title: global,
    rows: [
      CodeLabShortcutTableRow(
        key: const ValueKey('preview-row-command-palette'),
        action: openPalette,
        combos: CodeLabShortcut.commandPalette.combos,
        where: workbench,
      ),
    ],
  ),
  CodeLabShortcutTableGroup(
    key: const ValueKey('preview-group-approvals'),
    title: approvals,
    rows: [
      CodeLabShortcutTableRow(
        key: const ValueKey('preview-row-allow-always'),
        action: allowAlways,
        combos: CodeLabShortcut.allowAlways.combosFor(defaultTargetPlatform),
        where: pendingApproval,
      ),
    ],
  ),
];

class _AcpOrganismPreviewSurface extends StatelessWidget {
  const _AcpOrganismPreviewSurface({
    required this.child,
    this.brightness = Brightness.light,
    this.locale = const Locale('en'),
  });

  final Widget child;

  /// Язык превью: `en` по умолчанию, `ru` — пример экрана с делегатом кита
  /// (`add-desktop-localization`, D4).
  final Locale locale;

  /// Тема превью: тёмный вариант нужен таблице с тегами и обводками (D19).
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    // `InfoBar` заметок ленты читает `FluentLocalizations`; превью
    // рендерятся без `FluentApp`, поэтому локализации подключаются здесь.
    return Localizations(
      locale: locale,
      delegates: const [
        CodeLabLocalizations.delegate,
        FluentLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: FluentTheme(
          data: FluentThemeData(brightness: brightness),
          child: Builder(
            builder: (context) {
              // Подсказки (`Tooltip`) сайдбара и app bar требуют `Overlay`, а
              // превью рендерятся без `FluentApp`.
              return Overlay(
                initialEntries: [
                  OverlayEntry(
                    builder: (context) => ColoredBox(
                      color: FluentTheme.of(context).scaffoldBackgroundColor,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: child,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

void codelabPreviewCancel() {}

const _previewProjects = [
  CodeLabSidebarProject(
    path: '/work/codelab-app',
    name: 'codelab-app',
    current: true,
    sessions: [
      CodeLabSessionListItem(
        id: 'session-1',
        title: 'Repository audit',
        status: CodeLabSessionStatus.completed,
      ),
      CodeLabSessionListItem(
        id: 'session-2',
        title: 'Workbench UI',
        status: CodeLabSessionStatus.awaitingApproval,
      ),
      CodeLabSessionListItem(
        id: 'session-3',
        title: 'Transport logs',
        status: CodeLabSessionStatus.running,
      ),
    ],
  ),
  CodeLabSidebarProject(path: '/work/codelab-cli', name: 'codelab-cli'),
  CodeLabSidebarProject(path: '/work/notes-app', name: 'notes-app'),
];

const _previewPlan = [
  CodeLabPlanEntry(
    content: 'Split transcript into typed rows',
    status: CodeLabPlanEntryStatus.completed,
    priority: CodeLabPlanEntryPriority.medium,
  ),
  CodeLabPlanEntry(
    content: 'TranscriptRowMapper with row reuse',
    status: CodeLabPlanEntryStatus.inProgress,
    priority: CodeLabPlanEntryPriority.medium,
  ),
  CodeLabPlanEntry(
    content: 'Diff preview in approval card',
    status: CodeLabPlanEntryStatus.pending,
    priority: CodeLabPlanEntryPriority.high,
  ),
];

class _AcpPreviewWorkbench extends StatelessWidget {
  const _AcpPreviewWorkbench();

  @override
  Widget build(BuildContext context) {
    return CodeLabWorkbenchLayout(
      appBar: const CodeLabAppBar(
        title: 'CodeLab',
        connectionStatus: CodeLabConnectionStatus.connected,
        paneToggles: [
          CodeLabPaneToggle(pane: ToolPane.plan, selected: true),
          CodeLabPaneToggle(pane: ToolPane.protocol),
        ],
      ),
      sidebar: const CodeLabSessionSidebar(
        activeSessionId: 'session-2',
        onSessionSelected: codelabPreviewSessionSelected,
        projects: _previewProjects,
      ),
      sessionPane: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CodeLabSessionPaneHeader(
            title: 'Workbench UI',
            projectName: 'codelab-app',
            projectPath: '/work/codelab-app',
            mode: 'standard',
          ),
          SizedBox(height: 8),
          Expanded(
            child: CodeLabTranscriptPanel(
              rows: [
                CodeLabUserRow(
                  id: 'user-1',
                  text: 'Create a desktop layout shell for the workbench.',
                ),
                CodeLabAgentTextRow(
                  id: 'agent-1',
                  text: 'I will keep it slot-based for future app wiring.',
                ),
              ],
            ),
          ),
          SizedBox(height: 12),
          CodeLabPromptComposer(onSubmit: codelabPreviewPromptSubmitted),
        ],
      ),
      dock: CodeLabToolDock(
        active: ToolPane.plan,
        tabs: [
          const CodeLabDockTab(
            pane: ToolPane.plan,
            content: _PreviewPlanList(),
          ),
          CodeLabDockTab(pane: ToolPane.protocol, content: SizedBox.shrink()),
        ],
      ),
    );
  }
}

class _PreviewPlanList extends StatelessWidget {
  const _PreviewPlanList();

  @override
  Widget build(BuildContext context) =>
      CodeLabProgressChecklist.list(entries: _previewPlan);
}
