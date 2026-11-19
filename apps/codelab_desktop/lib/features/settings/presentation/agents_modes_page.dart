import 'dart:async';

import 'package:codelab_setup/codelab_setup.dart' show ConfigLayer;
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/app_scope.dart';
import '../../../l10n/l10n.dart';
import '../application/agents_modes_cubit.dart';
import 'agents_modes_texts.dart';
import 'config_source_label.dart';
import 'settings_problem_text.dart';

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
          AgentsModesReadOnly(:final reason) => _page(context, [
            // Заголовок общий с «Providers», подсказка с командами для хоста —
            // отдельной строкой `content`, как на MCP и Skills (D5).
            switch (reason) {
              RemoteAgentReadOnly(:final origin) => _bar(
                const ValueKey('agents-modes-read-only'),
                InfoBarSeverity.warning,
                context.l10n.providersReadOnlyTitle(origin),
                content: context.l10n.agentsReadOnlyHint,
              ),
              ForeignAgentReadOnly(:final agentName) => _bar(
                const ValueKey('agents-modes-read-only'),
                InfoBarSeverity.warning,
                context.l10n.agentsReadOnlyManaged(agentName),
              ),
            },
          ]),
          AgentsModesUnreadable() => _page(context, [
            if (state.banner case final banner?)
              _bar(
                const ValueKey('agents-modes-banner'),
                InfoBarSeverity.success,
                agentsModesMessageText(context.l10n, banner.message),
              ),
            _bar(
              const ValueKey('agents-modes-unreadable'),
              InfoBarSeverity.error,
              context.l10n.providersUnreadable,
              // Тексты загрузчика — как есть под переведённым заголовком (D6).
              content: settingsProblemsText(context.l10n, state.issues),
            ),
          ]),
          AgentsModesReady() => _ready(context, state),
        },
      ),
    );
  }

  Widget _page(BuildContext context, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: CodeLabText(
          context.l10n.settingsPageAgentsAndModesTitle,
          role: CodeLabTextRole.title,
        ),
      ),
      ...children,
    ],
  );

  /// Недоверенный текст (путь из файлов и проекта) одной ячейкой таблицы с
  /// `untrusted`: управляющие и bidi-символы становятся видимыми `\\uXXXX`
  /// (D20.4, как `skills-banner`).
  static Widget _escaped(
    String text, {
    required String column,
    bool mono = false,
  }) => CodeLabStatusTable(
    columns: [column],
    rows: [
      CodeLabStatusTableRow(
        cells: [CodeLabStatusTableCell(text, mono: mono, untrusted: true)],
      ),
    ],
  );

  Widget _escapedBar(
    Key key,
    String column,
    InfoBarSeverity severity,
    String title,
    String text,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: InfoBar(
      key: key,
      title: Text(title),
      content: CodeLabStatusTable(
        columns: [column],
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
    final l10n = context.l10n;
    final modeLabel = agentModeLabel(
      l10n,
      state.mode,
      blocksWriteAndExec: state.blocksWriteAndExec,
    );
    return _page(context, [
      if (state.banner case final banner?)
        _bar(const ValueKey('agents-modes-banner'), switch (banner.kind) {
          AgentsModesBannerKind.saved => InfoBarSeverity.success,
          AgentsModesBannerKind.warning ||
          AgentsModesBannerKind.conflict => InfoBarSeverity.warning,
          AgentsModesBannerKind.error => InfoBarSeverity.error,
        }, agentsModesMessageText(l10n, banner.message)),
      if (state.narrowedByProject)
        _bar(
          const ValueKey('agents-modes-mode-narrowed'),
          InfoBarSeverity.warning,
          l10n.agentsModeNarrowed(modeLabel),
        ),
      CodeLabSettingsRow(
        title: l10n.agentsSaveToTitle,
        description: l10n.agentsSaveToDescription,
        leading: FluentIcons.save,
        trailing: CodeLabSegmentedControl<ConfigLayer>(
          key: const ValueKey('agents-modes-target'),
          semanticLabel: l10n.agentsSaveToTitle,
          options: [
            CodeLabSegment(
              value: ConfigLayer.user,
              label: l10n.agentsTargetAll,
            ),
            if (state.canTargetProject)
              CodeLabSegment(
                value: ConfigLayer.projectLocal,
                label: l10n.agentsTargetProject,
              ),
          ],
          value: state.target,
          onChanged: cubit.selectTarget,
        ),
      ),
      CodeLabSettingsSection(
        title: l10n.agentsModeSection,
        children: [_modeCard(context, state, secondary)],
      ),
      CodeLabSettingsSection(
        title: l10n.agentsEffortSection,
        children: [_effortRow(context, cubit, state)],
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
    final l10n = context.l10n;
    final bars = <Widget>[
      for (final error in definitions.errors)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InfoBar(
            key: ValueKey('agents-definitions-error-${error.index}'),
            title: Text(
              error.line == null
                  ? l10n.agentsErrorTitle
                  : l10n.agentsErrorTitleLine(error.line!),
            ),
            // Путь файла — недоверенный текст: показывается экранированным,
            // как в `skills-banner` (D20.4).
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _escaped(
                  error.pathLabel,
                  column: l10n.agentsColPath,
                  mono: true,
                ),
                const SizedBox(height: 4),
                // Сообщение разбора YAML может нести символы из файла.
                _escaped(
                  // Текст ядра — как есть; запасная фраза — по причине.
                  error.message ??
                      switch (error.reason) {
                        AgentsDefinitionErrorKind.modelNotConfigured =>
                          l10n.agentsErrorFallbackModel,
                        AgentsDefinitionErrorKind.duplicate =>
                          l10n.agentsErrorFallbackDuplicate,
                        AgentsDefinitionErrorKind.other =>
                          l10n.agentsErrorFallbackOther,
                      },
                  column: l10n.agentsColMessage,
                ),
              ],
            ),
            severity: InfoBarSeverity.error,
            isLong: true,
            action: CodeLabButton(
              key: ValueKey('agents-definitions-open-file-${error.index}'),
              label: l10n.agentsOpenFolder,
              onPressed: () =>
                  unawaited(cubit.openDefinitionFolder(error.path)),
            ),
          ),
        ),
      if (definitions.untrustedProject)
        _escapedBar(
          const ValueKey('agents-definitions-untrusted'),
          l10n.agentsColMessage,
          InfoBarSeverity.info,
          l10n.agentsUntrustedTitle,
          definitions.projectLabel == null
              ? l10n.agentsUntrustedBodyNoPath
              : l10n.agentsUntrustedBody(definitions.projectLabel!),
        ),
      if (definitions.timedOut)
        _bar(
          const ValueKey('agents-definitions-timeout'),
          InfoBarSeverity.warning,
          l10n.agentsTimedOut,
        ),
      if (definitions.failed)
        _bar(
          const ValueKey('agents-definitions-failed'),
          InfoBarSeverity.error,
          l10n.agentsFailed,
        ),
      if (definitions.openFailure case final label?)
        _escapedBar(
          const ValueKey('agents-definitions-open-failed'),
          l10n.agentsColMessage,
          InfoBarSeverity.warning,
          l10n.agentsOpenFailedTitle,
          l10n.agentsOpenFailedBody(label),
        ),
    ];
    return CodeLabSettingsSection(
      title: l10n.agentsDefinitionsSection,
      children: [
        // Подпись и кнопки в Wrap: русские подписи длиннее, и в одну строку на
        // колонке ~360 pt они не помещаются (D8, «Длина строк»).
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: CodeLabText(
                l10n.agentsDefinitionsCaption,
                role: CodeLabTextRole.caption,
                color: secondary,
              ),
            ),
            DropDownButton(
              key: const ValueKey('agents-definitions-open-folder'),
              title: Text(l10n.agentsOpenFolder),
              items: [
                MenuFlyoutItem(
                  key: const ValueKey('agents-definitions-open-user'),
                  text: Text(
                    l10n.agentsOpenUserFolder(definitions.userFolderLabel),
                  ),
                  onPressed: () =>
                      unawaited(cubit.openFolder(AgentsFolder.user)),
                ),
                if (definitions.projectFolderAvailable)
                  MenuFlyoutItem(
                    key: const ValueKey('agents-definitions-open-project'),
                    text: definitions.projectFolderExists
                        ? Text(l10n.agentsOpenProjectFolder)
                        : Tooltip(
                            message: l10n.agentsOpenProjectMissing,
                            child: Text(l10n.agentsOpenProjectFolder),
                          ),
                    // Каталога проекта нет: app его не создаёт (Q11 (б)).
                    onPressed: definitions.projectFolderExists
                        ? () =>
                              unawaited(cubit.openFolder(AgentsFolder.project))
                        : null,
                  ),
              ],
            ),
            CodeLabButton(
              key: const ValueKey('agents-definitions-reload'),
              label: l10n.agentsReload,
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
                columns: [
                  l10n.agentsColName,
                  l10n.agentsColDescription,
                  l10n.agentsColSource,
                  l10n.agentsColAvailableIn,
                  l10n.agentsColTools,
                  l10n.agentsColModel,
                  l10n.agentsColStatus,
                ],
                // Длинный путь источника переносится, а не съедает статус.
                // В таблице нет действий, поэтому колонка действий не резервируется
                // (`actionWidth: 0`), а веса дают «Доступен в» и «Инструменты»
                // место под заголовок целиком при колонке ~880 pt (ru и en).
                actionWidth: 0,
                columnFlex: const [2, 3, 3, 3, 3, 2, 5],
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
                          row.descriptionText ?? '—',
                          muted: row.descriptionText == null,
                          untrusted: true,
                        ),
                        CodeLabStatusTableCell(
                          row.sourcePath ?? l10n.agentsBuiltIn,
                          mono: true,
                          untrusted: true,
                        ),
                        // Прочерк у отклонённого файла рисует страница (D7).
                        CodeLabStatusTableCell(
                          row.scope == null
                              ? '—'
                              : agentRowScopeText(l10n, row.scope!),
                          muted: row.scope == null,
                        ),
                        CodeLabStatusTableCell(
                          !row.loaded
                              ? '—'
                              : (row.toolNames?.join(', ') ??
                                    l10n.agentsAllTools),
                          muted: !row.loaded,
                          untrusted: true,
                        ),
                        CodeLabStatusTableCell(
                          !row.loaded
                              ? '—'
                              : (row.modelId ?? l10n.agentsSessionModel),
                          muted: !row.loaded,
                        ),
                        CodeLabStatusTableCell(
                          agentRowStatusText(
                            l10n,
                            row.rowStatus,
                            line: row.errorLine,
                            overriddenBy: row.overriddenBy,
                          ),
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
    final l10n = context.l10n;
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
              l10n.agentsModeCaption,
              role: CodeLabTextRole.caption,
              color: secondary,
            ),
            const SizedBox(height: 8),
            CodeLabText(
              l10n.agentsModeEffective(
                agentModeLabel(
                  l10n,
                  state.mode,
                  blocksWriteAndExec: state.blocksWriteAndExec,
                ),
              ),
            ),
            CodeLabText(
              l10n.agentsModeSource(
                configSourceLabel(l10n, state.modeSourceKind),
              ),
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
                l10n.agentsAutopilotHint,
                role: CodeLabTextRole.caption,
                color: secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static AppLocalizations _l10n(BuildContext context) => context.l10n;

  Widget _effortRow(
    BuildContext context,
    AgentsModesCubit cubit,
    AgentsModesReady state,
  ) => CodeLabSettingsRow(
    title: _l10n(context).agentsEffortTitle(
      configSourceLabel(_l10n(context), state.effortSourceKind),
    ),
    description: _l10n(context).agentsEffortDescription,
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
                // Шире стандартных 368 pt: при них русская кнопка «Использовать
                // bypass» (~140 pt настоящим шрифтом) не помещается в свою
                // половину и переносится на две строки.
                constraints: const BoxConstraints(maxWidth: 480),
                title: CodeLabDialogTitle(dialogContext.l10n.agentsBypassTitle),
                content: Text(dialogContext.l10n.agentsBypassBody),
                actions: [
                  Button(
                    onPressed: () => close(false),
                    child: Text(dialogContext.l10n.commonCancel),
                  ),
                  FilledButton(
                    onPressed: () => close(true),
                    child: Text(dialogContext.l10n.agentsBypassConfirm),
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
