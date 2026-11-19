import 'dart:async';

import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart' hide DiagnosticLevel;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../app/app_scope.dart';
import '../../../l10n/l10n.dart';
import '../application/skills_settings_cubit.dart';
import 'settings_problem_text.dart';
import 'skills_texts.dart';

/// Тело страницы «Skills & extensions» для таблицы `settingsPageBuilders`.
///
/// Почему отдельный хозяин: Cubit страницы создаётся на каждое открытие
/// (файлы и конфиг перечитываются при открытии, change `add-app-skills-page`,
/// D6), а построитель таблицы — просто функция от `BuildContext`.
Widget buildSkillsPage(BuildContext context) => const SkillsPageHost();

/// Создаёт `SkillsSettingsCubit`, читает страницу и закрывает Cubit вместе с
/// ней (D6; `AGENTS.md` §9: подписка Cubit отменяется в `close()`).
class SkillsPageHost extends StatefulWidget {
  const SkillsPageHost({super.key});

  @override
  State<SkillsPageHost> createState() => _SkillsPageHostState();
}

class _SkillsPageHostState extends State<SkillsPageHost> {
  SkillsSettingsCubit? _cubit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cubit == null) {
      final cubit = codeLabDependenciesOf(context).createSkillsSettingsCubit();
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
      BlocProvider.value(value: _cubit!, child: const SkillsPage());
}

/// Страница настроек «Skills & extensions» (артборд `Extensions`; отступления
/// от него — design.md change `add-app-skills-page`, D13).
///
/// Почему: контекстные файлы, навыки и шаблоны — настройка агента, общая с
/// CLI (`codelab config check`), поэтому страница показывает то, что агент
/// загрузит из папки, а не собственное хранилище.
///
/// Для чего: только отображение состояния [SkillsSettingsCubit]. Что читать,
/// чьи это настройки, что открывать и как считаются бюджет, перекрытие и
/// доверие, решают Cubit и мост `codelab_setup`; страница получает нажатие
/// пользователя и вызывает методы Cubit (`AGENTS.md` §7, §10). Текст из
/// файлов (имена, описания, пути) недоверен: таблица рисует его с видимыми
/// управляющими символами (`untrusted`, D12). Переключатели навыков в этой
/// итерации только показывают состояние (запись — итерация 5).
///
/// Как использовать: Cubit берётся из `BlocProvider` выше по дереву.
class SkillsPage extends StatelessWidget {
  const SkillsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SkillsSettingsCubit>();
    final l10n = context.l10n;
    return BlocBuilder<SkillsSettingsCubit, SkillsSettingsState>(
      builder: (context, state) => KeyedSubtree(
        key: const ValueKey('settings-skills'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: switch (state) {
            SkillsSettingsLoading() => const [
              Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: ProgressRing()),
              ),
            ],
            SkillsSettingsReadOnly(:final reason) => [
              _header(l10n),
              switch (reason) {
                RemoteAgentReadOnly(:final origin) => _bar(
                  const ValueKey('skills-read-only'),
                  InfoBarSeverity.warning,
                  l10n.providersReadOnlyTitle(origin),
                  content: Text(l10n.skillsReadOnlyHint),
                ),
                ForeignAgentReadOnly(:final agentName) => _bar(
                  const ValueKey('skills-read-only'),
                  InfoBarSeverity.warning,
                  l10n.skillsReadOnlyManaged(agentName),
                ),
              },
            ],
            SkillsSettingsNoFolder() => [
              _header(
                l10n,
                cubit: cubit,
                reload: true,
                open: true,
                openTooltip: state.codelabHome == null
                    ? null
                    : l10n.skillsOpenCodelabTooltipHome(state.codelabHome!),
              ),
              if (state.banner case final banner?) _banner(l10n, banner),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: CodeLabText(
                  l10n.skillsNoFolder,
                  key: const ValueKey('skills-no-folder'),
                ),
              ),
            ],
            SkillsSettingsUnreadable() => [
              _header(l10n, cubit: cubit, reload: true),
              _bar(
                const ValueKey('skills-unreadable'),
                InfoBarSeverity.error,
                l10n.providersUnreadable,
                // Тексты загрузчика — как есть под переведённым заголовком (D6).
                content: Text(settingsProblemsText(l10n, state.issues)),
              ),
            ],
            SkillsSettingsReady() => _ready(l10n, cubit, state),
          },
        ),
      ),
    );
  }

  Widget _header(
    AppLocalizations l10n, {
    SkillsSettingsCubit? cubit,
    bool reload = false,
    bool open = false,
    String? openTooltip,
  }) {
    final title = CodeLabText(
      l10n.settingsPageSkillsAndExtensionsTitle,
      role: CodeLabTextRole.title,
    );
    final actions = [
      if (open && cubit != null)
        Tooltip(
          message: openTooltip ?? l10n.skillsOpenCodelabTooltipDefault,
          child: CodeLabButton(
            key: const ValueKey('skills-open-codelab'),
            label: l10n.skillsOpenCodelabButton,
            icon: FluentIcons.folder_open,
            onPressed: () => unawaited(cubit.openCodelabFolder()),
          ),
        ),
      if (reload && cubit != null)
        CodeLabButton(
          key: const ValueKey('skills-reload'),
          label: l10n.skillsReload,
          icon: FluentIcons.refresh,
          onPressed: () => unawaited(cubit.reload()),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      // На широкой колонке заголовок слева, кнопки справа; на узкой (русские
      // подписи длиннее, колонка ~360 pt) кнопки переносятся под заголовок
      // (D8, «Длина строк»).
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= 640
            ? Row(
                children: [
                  Expanded(child: title),
                  for (final (i, action) in actions.indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    action,
                  ],
                ],
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(width: constraints.maxWidth, child: title),
                  ...actions,
                ],
              ),
      ),
    );
  }

  static Widget _bar(
    Key key,
    InfoBarSeverity severity,
    String title, {
    Widget? content,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: InfoBar(
      key: key,
      title: Text(title),
      content: content,
      severity: severity,
      isLong: true,
    ),
  );

  /// Баннер итога действия. Текст может содержать путь или сообщение
  /// загрузчика из файлов (недоверен): строку рисует таблица с `untrusted`,
  /// чтобы управляющие и bidi-символы стали видимыми (`escapeForDisplay`
  /// пакета не экспортируется, D12). Успех записи — `success`, остальное —
  /// `warning`.
  static Widget _banner(AppLocalizations l10n, SkillsBanner banner) {
    final (severity, title) = switch (banner.kind) {
      SkillsBannerKind.saved => (
        InfoBarSeverity.success,
        l10n.skillsBannerSaved,
      ),
      SkillsBannerKind.conflict => (
        InfoBarSeverity.warning,
        l10n.skillsBannerNotSaved,
      ),
      SkillsBannerKind.error => (
        InfoBarSeverity.warning,
        l10n.skillsBannerNotSaved,
      ),
      SkillsBannerKind.openFailed => (
        InfoBarSeverity.warning,
        l10n.skillsBannerCannotOpen,
      ),
    };
    return _bar(
      const ValueKey('skills-banner'),
      severity,
      title,
      content: CodeLabStatusTable(
        columns: [l10n.skillsColMessage],
        rows: [
          CodeLabStatusTableRow(
            cells: [
              CodeLabStatusTableCell(
                skillsMessageText(l10n, banner.message),
                untrusted: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _ready(
    AppLocalizations l10n,
    SkillsSettingsCubit cubit,
    SkillsSettingsReady state,
  ) {
    final view = state.view;
    final dotCodelab = p.join(state.folder, '.codelab');
    return [
      _header(
        l10n,
        cubit: cubit,
        reload: true,
        open: true,
        openTooltip: state.codelabHome == null
            ? l10n.skillsOpenCodelabTooltip(dotCodelab)
            : l10n.skillsOpenCodelabTooltipOr(dotCodelab, state.codelabHome!),
      ),
      if (state.banner case final banner?) _banner(l10n, banner),
      if (!view.trusted)
        _bar(
          const ValueKey('skills-untrusted'),
          InfoBarSeverity.warning,
          l10n.skillsUntrustedTitle,
          content: state.userConfigPath == null
              ? null
              : Text(l10n.skillsUntrustedHint(state.userConfigPath!)),
        ),
      ..._contextSection(l10n, cubit, view),
      ..._templatesSection(l10n, cubit, view),
      ..._skillsSection(l10n, cubit, state),
    ];
  }

  // --- Context files --------------------------------------------------------

  List<Widget> _contextSection(
    AppLocalizations l10n,
    SkillsSettingsCubit cubit,
    AgentExtensionsView view,
  ) {
    final context = view.context;
    return [
      _sectionTitle(l10n.skillsSectionContext),
      ..._phaseBody(
        l10n,
        context.outcome,
        timedOut: l10n.skillsPhaseTimedOutContext,
        failed: l10n.skillsPhaseFailedContext,
        child: () => context.files.isEmpty
            ? CodeLabText(l10n.skillsContextEmpty)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CodeLabStatusTable(
                    columns: [l10n.skillsColFile, l10n.skillsColSize],
                    columnFlex: const [4, 1],
                    rows: [
                      for (var i = 0; i < context.files.length; i++)
                        _contextRow(l10n, cubit, i, context.files[i]),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: CodeLabText(
                      l10n.skillsContextTotal(
                        context.files.length,
                        skillSizeText(l10n, context.shownBytes),
                      ),
                      role: CodeLabTextRole.caption,
                    ),
                  ),
                ],
              ),
      ),
      ..._diagnostics(
        l10n,
        const ValueKey('skills-context-warnings'),
        context.warnings,
      ),
    ];
  }

  CodeLabStatusTableRow _contextRow(
    AppLocalizations l10n,
    SkillsSettingsCubit cubit,
    int index,
    ContextFileView file,
  ) {
    // Усечение — признак ядра: оно срезает и завершающий перевод строки,
    // поэтому `shownBytes < bytes` усечением по бюджету не считается.
    final truncated = !file.omitted && file.truncated;
    return CodeLabStatusTableRow(
      key: ValueKey('skills-context-$index'),
      cells: [
        CodeLabStatusTableCell(
          file.path,
          mono: true,
          untrusted: true,
          tags: [
            if (file.isClaudeAlias)
              CodeLabStatusTableTag(l10n.skillsContextClaudeAlias),
            if (file.omitted)
              CodeLabStatusTableTag(
                l10n.skillsContextOmitted,
                tone: CodeLabTone.warning,
              )
            else if (truncated)
              CodeLabStatusTableTag(
                l10n.skillsContextTruncated(
                  skillSizeText(l10n, file.shownBytes),
                ),
                tone: CodeLabTone.warning,
              ),
          ],
        ),
        CodeLabStatusTableCell(skillSizeText(l10n, file.bytes), muted: true),
      ],
      action: file.openDir == null
          ? null
          : CodeLabStatusTableAction(
              key: ValueKey('skills-open-context-$index'),
              label: l10n.skillsOpen,
              onPressed: () => unawaited(cubit.openFolder(file.openDir!)),
            ),
    );
  }

  // --- Prompt templates -----------------------------------------------------

  List<Widget> _templatesSection(
    AppLocalizations l10n,
    SkillsSettingsCubit cubit,
    AgentExtensionsView view,
  ) {
    final templates = view.templates;
    return [
      _sectionTitle(l10n.skillsSectionTemplates),
      ..._phaseBody(
        l10n,
        templates.outcome,
        timedOut: l10n.skillsPhaseTimedOutTemplates,
        failed: l10n.skillsPhaseFailedTemplates,
        child: () => templates.entries.isEmpty
            ? CodeLabText(l10n.skillsTemplatesEmpty)
            : CodeLabStatusTable(
                columns: [l10n.skillsColCommand, l10n.skillsColSource],
                columnFlex: const [3, 2],
                rows: [
                  for (final entry in templates.entries)
                    CodeLabStatusTableRow(
                      key: ValueKey(
                        'skills-template-${_withoutSlash(entry.command)}',
                      ),
                      cells: [
                        CodeLabStatusTableCell(
                          entry.argumentHint == null
                              ? entry.command
                              : '${entry.command} ${entry.argumentHint}',
                          mono: true,
                          untrusted: true,
                          secondary: entry.description.isEmpty
                              ? null
                              : entry.description,
                        ),
                        CodeLabStatusTableCell(
                          _relativeTo(view.folder, entry.sourcePath),
                          mono: true,
                          untrusted: true,
                        ),
                      ],
                      action: CodeLabStatusTableAction(
                        key: ValueKey(
                          'skills-open-template-'
                          '${_withoutSlash(entry.command)}',
                        ),
                        label: l10n.skillsOpen,
                        onPressed: () =>
                            unawaited(cubit.openTemplateFolder(entry)),
                      ),
                    ),
                ],
              ),
      ),
      ..._diagnostics(
        l10n,
        const ValueKey('skills-templates-warnings'),
        templates.warnings,
      ),
    ];
  }

  // --- Skills ---------------------------------------------------------------

  List<Widget> _skillsSection(
    AppLocalizations l10n,
    SkillsSettingsCubit cubit,
    SkillsSettingsReady state,
  ) {
    final skills = state.view.skills;
    return [
      _sectionTitle(l10n.skillsSectionSkills),
      ..._phaseBody(
        l10n,
        skills.outcome,
        timedOut: l10n.skillsPhaseTimedOutSkills,
        failed: l10n.skillsPhaseFailedSkills,
        child: () => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (skills.entries.isEmpty)
              CodeLabText(l10n.skillsEmpty)
            else
              CodeLabStatusTable(
                columns: [
                  l10n.skillsColSkill,
                  l10n.skillsColInvokeAs,
                  l10n.skillsColSource,
                ],
                columnFlex: const [4, 2, 2],
                rows: [
                  for (final entry in skills.entries)
                    _skillRow(l10n, cubit, entry, saving: state.saving),
                ],
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: CodeLabText(
                l10n.skillsSearchOrder,
                key: const ValueKey('skills-search-order'),
                role: CodeLabTextRole.caption,
              ),
            ),
            CodeLabText(l10n.skillsListFixed, role: CodeLabTextRole.caption),
            if (skills.consents.isNotEmpty)
              _consentTable(l10n, cubit, skills.consents, saving: state.saving),
          ],
        ),
      ),
      ..._skillWarnings(l10n, skills.warnings),
    ];
  }

  CodeLabStatusTableRow _skillRow(
    AppLocalizations l10n,
    SkillsSettingsCubit cubit,
    SkillEntryView entry, {
    required bool saving,
  }) {
    final enabled = entry.availability == SkillAvailability.enabled;
    final warningText = entry.warnings.map((d) => d.message).join('\n');
    return CodeLabStatusTableRow(
      key: ValueKey('skills-row-${entry.name}'),
      cells: [
        CodeLabStatusTableCell(
          entry.name,
          mono: true,
          untrusted: true,
          secondary: entry.description.isEmpty ? null : entry.description,
          tags: [
            if (entry.overrides.isNotEmpty)
              CodeLabStatusTableTag(_overridesText(l10n, entry)),
            if (enabled && entry.userInvocable && !entry.modelVisible)
              CodeLabStatusTableTag(l10n.skillsTagCommandOnly),
            if (entry.warnings.isNotEmpty)
              CodeLabStatusTableTag(
                l10n.skillsWarningCount(entry.warnings.length),
                tone: CodeLabTone.warning,
                tooltip: warningText,
              ),
          ],
        ),
        CodeLabStatusTableCell(
          entry.invokeAs ?? l10n.skillsInvokeModelOnly,
          mono: entry.invokeAs != null,
          muted: entry.invokeAs == null,
          untrusted: true,
        ),
        CodeLabStatusTableCell(
          _rootLabel(l10n, entry.root),
          mono: true,
          untrusted: true,
        ),
      ],
      toggle: CodeLabStatusTableToggle(
        key: ValueKey('skills-toggle-${entry.name}'),
        value: enabled,
        label: l10n.skillsToggleLabel(entry.name),
        // Активен, если мост не отказал и запись не идёт; отказ — подсказка с
        // причиной (D5, D9). Что писать, решает Cubit по свежему снимку.
        onChanged: entry.toggle.isAvailable && !saving
            ? (value) =>
                  unawaited(cubit.setSkillEnabled(entry.name, enabled: value))
            : null,
        tooltip: entry.toggle.refusal == null
            ? null
            : skillsRefusalText(l10n, entry.toggle.refusal!),
      ),
      action: CodeLabStatusTableAction(
        key: ValueKey('skills-open-skill-${entry.name}'),
        label: l10n.skillsOpen,
        onPressed: () => unawaited(cubit.openFolder(entry.directory)),
      ),
    );
  }

  /// Согласие на каталоги навыков других агентов (Q3): подпись называет число
  /// найденных каталогов и область действия; относительный элемент действует
  /// во всех доверенных проектах, где такой каталог есть.
  ///
  /// Почему таблица: подсказка отказа содержит путь файла из конфигурации, а
  /// переключатель строки таблицы всегда экранирует подпись и подсказку
  /// (`escapeForDisplay` пакета не экспортируется, D12). Ключ строки —
  /// `skills-consent-note-<kind>`, переключателя — `skills-consent-<kind>`.
  Widget _consentTable(
    AppLocalizations l10n,
    SkillsSettingsCubit cubit,
    List<SkillConsentView> consents, {
    required bool saving,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: CodeLabStatusTable(
      columns: [l10n.skillsColOtherAgents],
      rows: [
        for (final consent in consents)
          _consentRow(l10n, cubit, consent, saving: saving),
      ],
    ),
  );

  CodeLabStatusTableRow _consentRow(
    AppLocalizations l10n,
    SkillsSettingsCubit cubit,
    SkillConsentView consent, {
    required bool saving,
  }) {
    final kind = consentKindOf(consent.entry);
    final count = consent.skillDirs;
    // Три отдельных предложения, а не склейка частей фразы (D5, правило 7).
    final note = [
      count == null
          ? l10n.skillsConsentNotCounted
          : l10n.skillsConsentFound(count),
      if (kind != SkillsConsentKind.home) l10n.skillsConsentEveryProject,
      l10n.skillsConsentAgentsFolder,
    ].join(' ');
    return CodeLabStatusTableRow(
      key: ValueKey('skills-consent-note-${kind.key}'),
      cells: [
        CodeLabStatusTableCell(
          l10n.skillsConsentRead(consent.entry),
          mono: true,
          secondary: note,
        ),
      ],
      toggle: CodeLabStatusTableToggle(
        key: ValueKey('skills-consent-${kind.key}'),
        value: consent.granted,
        label: l10n.skillsConsentRead(consent.entry),
        onChanged: consent.toggle.isAvailable && !saving
            ? (value) =>
                  unawaited(cubit.setRootConsent(consent.entry, granted: value))
            : null,
        tooltip: consent.toggle.refusal == null
            ? null
            : skillsRefusalText(
                l10n,
                consent.toggle.refusal!,
                element: consent.entry,
              ),
      ),
    );
  }

  List<Widget> _skillWarnings(
    AppLocalizations l10n,
    List<ExtensionDiagnostic> all,
  ) {
    final shown = all.where((d) => d.level != DiagnosticLevel.info).toList();
    if (shown.isEmpty) {
      return const [];
    }
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _bar(
          const ValueKey('skills-warnings'),
          InfoBarSeverity.warning,
          l10n.skillsWarningCount(shown.length),
          content: _diagnosticLines(l10n, shown),
        ),
      ),
    ];
  }

  List<Widget> _diagnostics(
    AppLocalizations l10n,
    Key key,
    List<ExtensionDiagnostic> all,
  ) {
    final shown = all.where((d) => d.level != DiagnosticLevel.info).toList();
    if (shown.isEmpty) {
      return const [];
    }
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _bar(
          key,
          InfoBarSeverity.warning,
          l10n.skillsWarningCount(shown.length),
          content: _diagnosticLines(l10n, shown),
        ),
      ),
    ];
  }

  /// Тексты диагностик ядра фиксированы, пути — из файлов и недоверенны:
  /// строки рисует таблица с `untrusted`, чтобы управляющие и bidi-символы
  /// стали видимыми (D12; `escapeForDisplay` пакета не экспортируется).
  static Widget _diagnosticLines(
    AppLocalizations l10n,
    List<ExtensionDiagnostic> shown,
  ) => CodeLabStatusTable(
    columns: [l10n.skillsColMessage],
    rows: [
      for (final d in shown)
        CodeLabStatusTableRow(
          cells: [
            CodeLabStatusTableCell(
              d.message,
              untrusted: true,
              secondary: d.path,
            ),
          ],
        ),
    ],
  );

  // --- Общее ----------------------------------------------------------------

  static Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 6),
    child: CodeLabText(title, role: CodeLabTextRole.strong),
  );

  /// Тело раздела по исходу фазы: прочитано — [child]; иначе фиксированная
  /// строка исхода (D4: `Skills were not read within 5 s.`).
  static List<Widget> _phaseBody(
    AppLocalizations l10n,
    SectionOutcome outcome, {
    required String timedOut,
    required String Function(String errorType) failed,
    required Widget Function() child,
  }) => [
    switch (outcome) {
      SectionRead() => child(),
      SectionTimedOut() => CodeLabText(timedOut),
      SectionFailed(:final errorType) => CodeLabText(failed(errorType)),
      SectionOff(:final source) => CodeLabText(l10n.skillsPhaseOff(source)),
    },
  ];

  /// Подпись перекрытия по области из моста (`overridesScope`), а не по
  /// английскому `overridesLabel` (D6, решение пользователя В2).
  static String _overridesText(AppLocalizations l10n, SkillEntryView entry) =>
      switch (entry.overridesScope) {
        ExtensionScope.user => l10n.skillsOverridesUser,
        ExtensionScope.project => l10n.skillsOverridesProject,
        ExtensionScope.extra => l10n.skillsOverridesExtra,
        _ => l10n.skillsOverridesOther,
      };

  /// Подпись корня навыков: дополнительная папка — по элементу
  /// `extraEntry`, неизвестный корень — отдельной подписью; остальные подписи
  /// моста (`.codelab/skills`, `~/.agents/skills`) — пути и не переводятся.
  static String _rootLabel(AppLocalizations l10n, SkillRootView root) {
    if (root.scope != ExtensionScope.extra) {
      return root.label;
    }
    final entry = root.extraEntry;
    return entry == null ? l10n.skillsUnknownRoot : l10n.skillsExtraRoot(entry);
  }

  static String _withoutSlash(String command) =>
      command.startsWith('/') ? command.substring(1) : command;

  /// Путь от папки проекта, если файл внутри неё; иначе как есть.
  static String _relativeTo(String folder, String path) =>
      p.isWithin(folder, path) ? p.relative(path, from: folder) : path;
}
