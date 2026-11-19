import 'dart:async';

import 'package:codelab_setup/codelab_setup.dart' show ConfigLayer;
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/app_scope.dart';
import '../application/agents_modes_cubit.dart';

/// Тело страницы «Agents & modes» для таблицы `settingsPageBuilders`.
///
/// Почему отдельный хозяин: Cubit страницы создаётся на каждое открытие
/// (снимок конфига перечитывается при открытии, design.md change
/// `add-settings-agents-modes`, D11), а построитель таблицы — просто функция
/// от `BuildContext`.
Widget buildAgentsModesPage(BuildContext context) =>
    const AgentsModesPageHost();

/// Создаёт `AgentsModesCubit`, читает снимок и закрывает Cubit вместе со
/// страницей.
///
/// Почему не виджет, создающий зависимости: Cubit собирает composition root
/// (`CodeLabDependencies.createAgentsModesCubit`); здесь он только получает
/// владельца жизненного цикла (AGENTS.md §6).
class AgentsModesPageHost extends StatefulWidget {
  const AgentsModesPageHost({super.key});

  @override
  State<AgentsModesPageHost> createState() => _AgentsModesPageHostState();
}

class _AgentsModesPageHostState extends State<AgentsModesPageHost> {
  AgentsModesCubit? _cubit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cubit == null) {
      final cubit = codeLabDependenciesOf(context).createAgentsModesCubit();
      _cubit = cubit;
      unawaited(cubit.reload());
    }
  }

  @override
  void dispose() {
    unawaited(_cubit?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocProvider.value(value: _cubit!, child: const AgentsModesPage());
}

/// Страница настроек «Agents & modes»: режим разрешений и effort новых сессий
/// (артборд `docs/design/claude-design/Modes-dark.dc.html`; отступления —
/// design.md change `add-settings-agents-modes`, D10).
///
/// Почему: эти умолчания — ключи конфига агента, общие с CLI, а не настройки
/// app (D2). Страница показывает итог из снимка и не повторяет правил слоёв и
/// доверия (SETUP-8).
///
/// Для чего: только отображение состояния [AgentsModesCubit]. Опасно ли
/// действие, какой слой писать и что записано, решают Cubit и мост; страница
/// получает решение пользователя и вызывает методы Cubit. Для `bypass`
/// страница показывает подтверждение и передаёт ответ (`confirmBypass` или
/// `cancelBypass`), сама `selectMode('bypass')` не вызывает (D5).
///
/// Как использовать: Cubit берётся из `BlocProvider` выше по дереву. Ключи
/// теста — D9.
class AgentsModesPage extends StatelessWidget {
  const AgentsModesPage({super.key});

  /// Режимы радиогруппы сверху вниз.
  static const _modes = ['plan', 'ask', 'standard', 'accept-edits', 'bypass'];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AgentsModesCubit, AgentsModesState>(
      builder: (context, state) => KeyedSubtree(
        key: const ValueKey('settings-agents-modes'),
        child: switch (state) {
          AgentsModesLoading() => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: ProgressRing()),
          ),
          AgentsModesReadOnly() => _page([
            _bar(
              const ValueKey('agents-modes-read-only'),
              InfoBarSeverity.warning,
              state.notice,
            ),
          ]),
          AgentsModesUnreadable() => _page([
            if (state.banner case final banner?)
              _bar(
                const ValueKey('agents-modes-banner'),
                InfoBarSeverity.success,
                banner.text,
              ),
            _bar(
              const ValueKey('agents-modes-unreadable'),
              InfoBarSeverity.error,
              'Cannot read the agent config. Fix or remove the file; CodeLab '
              'will not overwrite it.',
              content: state.problems.join('\n'),
            ),
          ]),
          AgentsModesReady() => _ready(context, state),
        },
      ),
    );
  }

  Widget _page(List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: CodeLabText('Agents & modes', role: CodeLabTextRole.title),
      ),
      ...children,
    ],
  );

  /// Недоверенный текст (путь из файлов и проекта) одной ячейкой таблицы с
  /// `untrusted`: управляющие и bidi-символы становятся видимыми `\\uXXXX`
  /// (D20.4, как `skills-banner`).
  static Widget _escaped(
    String text, {
    bool mono = false,
    String column = 'PATH',
  }) => CodeLabStatusTable(
    columns: const ['PATH'],
    rows: [
      CodeLabStatusTableRow(
        cells: [CodeLabStatusTableCell(text, mono: mono, untrusted: true)],
      ),
    ],
  );

  Widget _escapedBar(
    Key key,
    InfoBarSeverity severity,
    String title,
    String text,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: InfoBar(
      key: key,
      title: Text(title),
      content: CodeLabStatusTable(
        columns: const ['MESSAGE'],
        rows: [
          CodeLabStatusTableRow(
            cells: [CodeLabStatusTableCell(text, untrusted: true)],
          ),
        ],
      ),
      severity: severity,
      isLong: true,
    ),
  );

  Widget _bar(
    Key key,
    InfoBarSeverity severity,
    String title, {
    String? content,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: InfoBar(
      key: key,
      title: Text(title),
      content: content == null ? null : Text(content),
      severity: severity,
      isLong: true,
    ),
  );

  Widget _ready(BuildContext context, AgentsModesReady state) {
    final cubit = context.read<AgentsModesCubit>();
    final secondary = FluentTheme.of(context).resources.textFillColorSecondary;
    return _page([
      if (state.banner case final banner?)
        _bar(const ValueKey('agents-modes-banner'), switch (banner.kind) {
          AgentsModesBannerKind.saved => InfoBarSeverity.success,
          AgentsModesBannerKind.warning ||
          AgentsModesBannerKind.conflict => InfoBarSeverity.warning,
          AgentsModesBannerKind.error => InfoBarSeverity.error,
        }, banner.text),
      if (state.narrowedNotice case final notice?)
        _bar(
          const ValueKey('agents-modes-mode-narrowed'),
          InfoBarSeverity.warning,
          notice,
        ),
      CodeLabSettingsRow(
        title: 'Save to',
        description: 'One target for the mode and the reasoning effort.',
        leading: FluentIcons.save,
        trailing: CodeLabSegmentedControl<ConfigLayer>(
          key: const ValueKey('agents-modes-target'),
          semanticLabel: 'Save to',
          options: [
            const CodeLabSegment(
              value: ConfigLayer.user,
              label: 'All projects',
            ),
            if (state.canTargetProject)
              const CodeLabSegment(
                value: ConfigLayer.projectLocal,
                label: 'This project only',
              ),
          ],
          value: state.target,
          onChanged: cubit.selectTarget,
        ),
      ),
      CodeLabSettingsSection(
        title: 'Default permission mode',
        children: [_modeCard(context, state, secondary)],
      ),
      CodeLabSettingsSection(
        title: 'Default reasoning effort',
        children: [_effortRow(cubit, state)],
      ),
      if (state.definitions case final definitions?)
        _definitionsSection(context, cubit, definitions, secondary),
    ]);
  }

  /// Блок «Agent definitions» (design.md change `add-settings-agents-modes`,
  /// D7, D8, D9): таблица только для чтения, InfoBar ошибок файлов с «Open
  /// file», меню «Open folder» и «Reload». Что читать, открывать и создавать,
  /// решает Cubit; здесь только отображение и вызовы.
  Widget _definitionsSection(
    BuildContext context,
    AgentsModesCubit cubit,
    AgentsDefinitionsView definitions,
    Color secondary,
  ) {
    final bars = <Widget>[
      for (final error in definitions.errors)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InfoBar(
            key: ValueKey('agents-definitions-error-${error.index}'),
            title: Text(
              error.line == null
                  ? 'Cannot load the definition'
                  : 'Cannot load the definition · line ${error.line}',
            ),
            // Путь файла — недоверенный текст: показывается экранированным,
            // как в `skills-banner` (D20.4).
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _escaped(error.pathLabel, mono: true),
                const SizedBox(height: 4),
                // Сообщение разбора YAML может нести символы из файла.
                _escaped(error.message, column: 'MESSAGE'),
              ],
            ),
            severity: InfoBarSeverity.error,
            isLong: true,
            action: CodeLabButton(
              key: ValueKey('agents-definitions-open-file-${error.index}'),
              label: 'Open folder',
              onPressed: () =>
                  unawaited(cubit.openDefinitionFolder(error.path)),
            ),
          ),
        ),
      if (definitions.untrustedProject)
        _escapedBar(
          const ValueKey('agents-definitions-untrusted'),
          InfoBarSeverity.info,
          'Project definitions are not read',
          'Definitions in ${definitions.projectLabel ?? 'the project'}/.codelab/agents '
              'are not read: the project is not trusted.',
        ),
      if (definitions.timedOut)
        _bar(
          const ValueKey('agents-definitions-timeout'),
          InfoBarSeverity.warning,
          'Agent definitions were not read within 5 s.',
        ),
      if (definitions.failed)
        _bar(
          const ValueKey('agents-definitions-failed'),
          InfoBarSeverity.error,
          'Agent definitions could not be read.',
        ),
      if (definitions.openFailure case final label?)
        _escapedBar(
          const ValueKey('agents-definitions-open-failed'),
          InfoBarSeverity.warning,
          'Cannot open the folder',
          'Could not open $label.',
        ),
    ];
    return CodeLabSettingsSection(
      title: 'Agent definitions',
      children: [
        Row(
          children: [
            Expanded(
              child: CodeLabText(
                'Definitions are read when a session is created; choose one '
                'for a single session in the composer agent menu.',
                role: CodeLabTextRole.caption,
                color: secondary,
              ),
            ),
            const SizedBox(width: 12),
            DropDownButton(
              key: const ValueKey('agents-definitions-open-folder'),
              title: const Text('Open folder'),
              items: [
                MenuFlyoutItem(
                  key: const ValueKey('agents-definitions-open-user'),
                  text: Text(
                    'User definitions (${definitions.userFolderLabel})',
                  ),
                  onPressed: () =>
                      unawaited(cubit.openFolder(AgentsFolder.user)),
                ),
                if (definitions.projectFolderAvailable)
                  MenuFlyoutItem(
                    key: const ValueKey('agents-definitions-open-project'),
                    text: definitions.projectFolderExists
                        ? const Text('This project (.codelab/agents)')
                        : const Tooltip(
                            message:
                                'Create .codelab/agents in the project to add '
                                'definitions.',
                            child: Text('This project (.codelab/agents)'),
                          ),
                    // Каталога проекта нет: app его не создаёт (Q11 (б)).
                    onPressed: definitions.projectFolderExists
                        ? () =>
                              unawaited(cubit.openFolder(AgentsFolder.project))
                        : null,
                  ),
              ],
            ),
            const SizedBox(width: 8),
            CodeLabButton(
              key: const ValueKey('agents-definitions-reload'),
              label: 'Reload',
              icon: FluentIcons.refresh,
              onPressed: () => unawaited(cubit.reload()),
            ),
          ],
        ),
        ...bars,
        LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              // Таблица не уже 880 px и прокручивается по горизонтали; длинные
              // статусы и пути источника переносятся (до трёх строк).
              width: constraints.maxWidth < 880 ? 880 : constraints.maxWidth,
              child: CodeLabStatusTable(
                key: const ValueKey('agents-definitions-table'),
                columns: const [
                  'Name',
                  'Description',
                  'Source',
                  'Available in',
                  'Tools',
                  'Model',
                  'Status',
                ],
                // Длинный путь источника переносится, а не съедает статус.
                columnFlex: const [2, 3, 3, 2, 2, 2, 7],
                rows: [
                  for (final (index, row) in definitions.rows.indexed)
                    CodeLabStatusTableRow(
                      key: ValueKey(_rowKey(definitions.rows, index)),
                      cells: [
                        CodeLabStatusTableCell(
                          row.name,
                          mono: true,
                          untrusted: true,
                        ),
                        CodeLabStatusTableCell(
                          row.description,
                          muted: row.description == '—',
                          untrusted: true,
                        ),
                        CodeLabStatusTableCell(
                          row.source,
                          mono: true,
                          untrusted: true,
                        ),
                        CodeLabStatusTableCell(
                          row.availableIn,
                          muted: row.availableIn == '—',
                        ),
                        CodeLabStatusTableCell(
                          row.tools,
                          muted: row.tools == '—',
                          untrusted: true,
                        ),
                        CodeLabStatusTableCell(
                          row.model,
                          muted: row.model == '—',
                        ),
                        CodeLabStatusTableCell(
                          row.status,
                          maxLines: 3,
                          // «Overridden by <путь>»: путь из файлов (D20.4).
                          untrusted: true,
                          tone: switch (row.tone) {
                            AgentsStatusTone.success =>
                              CodeLabStatusTone.active,
                            AgentsStatusTone.warning =>
                              CodeLabStatusTone.warning,
                            AgentsStatusTone.danger => CodeLabStatusTone.danger,
                          },
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Ключ строки: `agents-definitions-row-<name>` у первой строки имени и
  /// `…-<name>#<n>` (n с 2; `#` не встречается в имени файла) у следующих — имена не уникальны (встроенный
  /// `review` и файл `review.md`, пользовательский и проектный файлы).
  static String _rowKey(List<AgentsDefinitionRow> rows, int index) {
    final name = rows[index].name;
    final n = rows.take(index).where((r) => r.name == name).length + 1;
    return n == 1
        ? 'agents-definitions-row-$name'
        : 'agents-definitions-row-$name#$n';
  }

  Widget _modeCard(
    BuildContext context,
    AgentsModesReady state,
    Color secondary,
  ) {
    final cubit = context.read<AgentsModesCubit>();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.cardBackgroundFillColorDefault,
        border: Border.all(
          color: FluentTheme.of(context).resources.cardStrokeColorDefault,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CodeLabText(
              'New sessions start in it after Restart agent; change it for '
              'one session from the composer.',
              role: CodeLabTextRole.caption,
              color: secondary,
            ),
            const SizedBox(height: 8),
            CodeLabText('Effective: ${state.modeLabel}'),
            CodeLabText(
              'Source: ${state.modeSource}',
              key: const ValueKey('agents-modes-mode-source'),
              role: CodeLabTextRole.caption,
              color: secondary,
            ),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: state.mode,
              onChanged: (id) {
                if (state.saving || id == null) {
                  return;
                }
                if (id == 'bypass') {
                  // Токен фиксирует состояние на момент открытия диалога (D5).
                  final token = cubit.beginBypass();
                  if (token != null) {
                    unawaited(_confirmBypass(context, cubit, token));
                  }
                } else {
                  unawaited(cubit.selectMode(id));
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final id in _modes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RadioButton<String>(
                        key: ValueKey('agents-modes-mode-$id'),
                        value: id,
                        enabled: !state.saving,
                        content: Text(id),
                      ),
                    ),
                  const RadioButton<String>(
                    key: ValueKey('agents-modes-mode-autopilot'),
                    value: 'autopilot',
                    enabled: false,
                    content: Text('autopilot'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: CodeLabText(
                'Only as a launch flag of the agent (codelab-agent serve '
                '--permission-mode autopilot); never saved in config.',
                role: CodeLabTextRole.caption,
                color: secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _effortRow(AgentsModesCubit cubit, AgentsModesReady state) =>
      CodeLabSettingsRow(
        title: 'Reasoning effort · ${state.effortSource}',
        description:
            'Sent as a session option only if the model supports reasoning; '
            'change it for one session from the composer.',
        leading: FluentIcons.lightbulb,
        trailing: SizedBox(
          width: 160,
          child: ComboBox<String>(
            key: const ValueKey('agents-modes-effort'),
            isExpanded: true,
            value: state.effort,
            items: const [
              ComboBoxItem(value: 'low', child: Text('low')),
              ComboBoxItem(value: 'medium', child: Text('medium')),
              ComboBoxItem(value: 'high', child: Text('high')),
            ],
            onChanged: state.saving
                ? null
                : (id) {
                    if (id != null) {
                      unawaited(cubit.selectEffort(id));
                    }
                  },
          ),
        ),
      );

  /// Подтверждение `bypass` (D5): запись постоянна и действует на все новые
  /// сессии цели, поэтому решает пользователь; закрытие без «Use bypass»
  /// (Cancel, Esc) — отказ.
  Future<void> _confirmBypass(
    BuildContext context,
    AgentsModesCubit cubit,
    BypassToken token,
  ) async {
    var closed = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        // Единственный путь закрытия (кнопки, Esc, слушатель): второй `pop`
        // закрыл бы уже маршрут под диалогом (D17).
        void close([bool? result]) {
          if (closed) {
            return;
          }
          closed = true;
          Navigator.of(dialogContext).pop(result);
        }

        return BlocListener<AgentsModesCubit, AgentsModesState>(
          bloc: cubit,
          // Страница ушла из `Ready` (другой агент, нечитаемый конфиг): диалог
          // закрывается без записи (D17).
          listener: (_, state) {
            if (state is! AgentsModesReady &&
                !closed &&
                ModalRoute.of(dialogContext)?.isCurrent == true) {
              cubit.dismissBypass(token);
              close();
            }
          },
          child: CallbackShortcuts(
            // Esc диалога — запись `close-overlay` каталога кита (D3).
            bindings: CodeLabShortcut.closeOverlay.bind(() => close(false)),
            child: Focus(
              autofocus: true,
              child: ContentDialog(
                key: const ValueKey('agents-modes-bypass-confirm'),
                title: const CodeLabDialogTitle('Use bypass for new sessions?'),
                content: const Text(
                  "Only critical commands, changes to the agent's configuration "
                  'and network tools still ask. Commands run without asking and '
                  'can reach the network too. Use bypass only in a disposable '
                  'checkout.',
                ),
                actions: [
                  Button(
                    onPressed: () => close(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => close(true),
                    child: const Text('Use bypass'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (cubit.isClosed || confirmed == null) {
      // Диалог закрыт самой страницей (D17): записи и отказа нет.
      return;
    }
    if (confirmed) {
      await cubit.confirmBypass(token);
    } else {
      cubit.cancelBypass();
    }
  }
}
