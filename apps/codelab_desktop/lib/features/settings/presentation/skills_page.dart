import 'dart:async';

import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart' hide DiagnosticLevel;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../app/app_scope.dart';
import '../application/skills_settings_cubit.dart';

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
            SkillsSettingsReadOnly() => [
              _header(),
              _bar(
                const ValueKey('skills-read-only'),
                InfoBarSeverity.warning,
                state.notice,
                content: state.hint == null ? null : Text(state.hint!),
              ),
            ],
            SkillsSettingsNoFolder() => [
              _header(
                cubit: cubit,
                reload: true,
                open: true,
                openTooltip: state.codelabHome == null
                    ? null
                    : 'Open the CodeLab home folder: ${state.codelabHome}',
              ),
              if (state.banner case final banner?) _banner(banner),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CodeLabText(
                  'Open a project folder to see the context files, skills and '
                  'prompt templates the agent uses there.',
                  key: ValueKey('skills-no-folder'),
                ),
              ),
            ],
            SkillsSettingsUnreadable() => [
              _header(cubit: cubit, reload: true),
              _bar(
                const ValueKey('skills-unreadable'),
                InfoBarSeverity.error,
                'Cannot read the agent config. Fix or remove the file; '
                'CodeLab will not overwrite it.',
                content: Text(state.problems.join('\n')),
              ),
            ],
            SkillsSettingsReady() => _ready(cubit, state),
          },
        ),
      ),
    );
  }

  Widget _header({
    SkillsSettingsCubit? cubit,
    bool reload = false,
    bool open = false,
    String? openTooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const Expanded(
            child: CodeLabText(
              'Skills & extensions',
              role: CodeLabTextRole.title,
            ),
          ),
          if (open && cubit != null) ...[
            Tooltip(
              message: openTooltip ?? 'Open the CodeLab home folder',
              child: CodeLabButton(
                key: const ValueKey('skills-open-codelab'),
                label: 'Open .codelab folder',
                icon: FluentIcons.folder_open,
                onPressed: () => unawaited(cubit.openCodelabFolder()),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (reload && cubit != null)
            CodeLabButton(
              key: const ValueKey('skills-reload'),
              label: 'Reload',
              icon: FluentIcons.refresh,
              onPressed: () => unawaited(cubit.reload()),
            ),
        ],
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
  static Widget _banner(SkillsBanner banner) {
    final (severity, title) = switch (banner.kind) {
      SkillsBannerKind.saved => (InfoBarSeverity.success, 'Saved'),
      SkillsBannerKind.conflict => (InfoBarSeverity.warning, 'Not saved'),
      SkillsBannerKind.error => (InfoBarSeverity.warning, 'Not saved'),
      SkillsBannerKind.openFailed => (
        InfoBarSeverity.warning,
        'Cannot open the folder',
      ),
    };
    return _bar(
      const ValueKey('skills-banner'),
      severity,
      title,
      content: CodeLabStatusTable(
        columns: const ['MESSAGE'],
        rows: [
          CodeLabStatusTableRow(
            cells: [CodeLabStatusTableCell(banner.text, untrusted: true)],
          ),
        ],
      ),
    );
  }

  List<Widget> _ready(SkillsSettingsCubit cubit, SkillsSettingsReady state) {
    final view = state.view;
    return [
      _header(
        cubit: cubit,
        reload: true,
        open: true,
        openTooltip:
            'Open ${p.join(state.folder, '.codelab')}'
            '${state.codelabHome == null ? '' : ', or ${state.codelabHome} if it does not exist'}',
      ),
      if (state.banner case final banner?) _banner(banner),
      if (!view.trusted)
        _bar(
          const ValueKey('skills-untrusted'),
          InfoBarSeverity.warning,
          'This project is not in trusted_projects, so the agent does not '
          'read its skills and prompt templates. Your own skills and '
          'AGENTS.md files are shown.',
          content: state.userConfigPath == null
              ? null
              : Text(
                  'Trust is set in trusted_projects of '
                  '${state.userConfigPath}.',
                ),
        ),
      ..._contextSection(cubit, view),
      ..._templatesSection(cubit, view),
      ..._skillsSection(cubit, state),
    ];
  }

  // --- Context files --------------------------------------------------------

  List<Widget> _contextSection(
    SkillsSettingsCubit cubit,
    AgentExtensionsView view,
  ) {
    final context = view.context;
    return [
      _sectionTitle('Context files'),
      ..._phaseBody(
        context.outcome,
        subject: 'Context files',
        child: () => context.files.isEmpty
            ? const CodeLabText('No AGENTS.md files for this folder.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CodeLabStatusTable(
                    columns: const ['FILE', 'SIZE'],
                    columnFlex: const [4, 1],
                    rows: [
                      for (var i = 0; i < context.files.length; i++)
                        _contextRow(cubit, i, context.files[i]),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: CodeLabText(
                      '${context.files.length} '
                      '${context.files.length == 1 ? 'file' : 'files'} · '
                      '${_size(context.shownBytes)}',
                      role: CodeLabTextRole.caption,
                    ),
                  ),
                ],
              ),
      ),
      ..._diagnostics(
        const ValueKey('skills-context-warnings'),
        context.warnings,
      ),
    ];
  }

  CodeLabStatusTableRow _contextRow(
    SkillsSettingsCubit cubit,
    int index,
    ContextFileView file,
  ) {
    final truncated = !file.omitted && file.shownBytes < file.bytes;
    return CodeLabStatusTableRow(
      key: ValueKey('skills-context-$index'),
      cells: [
        CodeLabStatusTableCell(
          file.path,
          mono: true,
          untrusted: true,
          tags: [
            if (file.isClaudeAlias)
              const CodeLabStatusTableTag(
                'used because this folder has no AGENTS.md',
              ),
            if (file.omitted)
              const CodeLabStatusTableTag(
                'not included (budget)',
                tone: CodeLabTone.warning,
              )
            else if (truncated)
              CodeLabStatusTableTag(
                'truncated to ${_size(file.shownBytes)}',
                tone: CodeLabTone.warning,
              ),
          ],
        ),
        CodeLabStatusTableCell(_size(file.bytes), muted: true),
      ],
      action: file.openDir == null
          ? null
          : CodeLabStatusTableAction(
              key: ValueKey('skills-open-context-$index'),
              label: 'Open',
              onPressed: () => unawaited(cubit.openFolder(file.openDir!)),
            ),
    );
  }

  // --- Prompt templates -----------------------------------------------------

  List<Widget> _templatesSection(
    SkillsSettingsCubit cubit,
    AgentExtensionsView view,
  ) {
    final templates = view.templates;
    return [
      _sectionTitle('Prompt templates'),
      ..._phaseBody(
        templates.outcome,
        subject: 'Prompt templates',
        child: () => templates.entries.isEmpty
            ? const CodeLabText('No prompt templates.')
            : CodeLabStatusTable(
                columns: const ['COMMAND', 'SOURCE'],
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
                        label: 'Open',
                        onPressed: () =>
                            unawaited(cubit.openTemplateFolder(entry)),
                      ),
                    ),
                ],
              ),
      ),
      ..._diagnostics(
        const ValueKey('skills-templates-warnings'),
        templates.warnings,
      ),
    ];
  }

  // --- Skills ---------------------------------------------------------------

  List<Widget> _skillsSection(
    SkillsSettingsCubit cubit,
    SkillsSettingsReady state,
  ) {
    final skills = state.view.skills;
    return [
      _sectionTitle('Skills'),
      ..._phaseBody(
        skills.outcome,
        subject: 'Skills',
        child: () => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (skills.entries.isEmpty)
              const CodeLabText('No skills found.')
            else
              CodeLabStatusTable(
                columns: const ['SKILL', 'INVOKE AS', 'SOURCE'],
                columnFlex: const [4, 2, 2],
                rows: [
                  for (final entry in skills.entries)
                    _skillRow(cubit, entry, saving: state.saving),
                ],
              ),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: CodeLabText(
                'Search order: .codelab/skills, then .agents/skills from this '
                r'folder up to the repository root; then $CODELAB_HOME/skills, '
                '~/.agents/skills; extra roots last. The nearest overrides the '
                'farthest.',
                key: ValueKey('skills-search-order'),
                role: CodeLabTextRole.caption,
              ),
            ),
            const CodeLabText(
              'The list is fixed when a session opens: new and changed skills '
              'apply to new sessions.',
              role: CodeLabTextRole.caption,
            ),
            if (skills.consents.isNotEmpty)
              _consentTable(cubit, skills.consents, saving: state.saving),
          ],
        ),
      ),
      ..._skillWarnings(skills.warnings),
    ];
  }

  CodeLabStatusTableRow _skillRow(
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
            if (entry.overridesLabel case final label?)
              CodeLabStatusTableTag(label),
            if (enabled && entry.userInvocable && !entry.modelVisible)
              const CodeLabStatusTableTag('Command only'),
            if (entry.warnings.isNotEmpty)
              CodeLabStatusTableTag(
                '${entry.warnings.length} '
                '${entry.warnings.length == 1 ? 'warning' : 'warnings'}',
                tone: CodeLabTone.warning,
                tooltip: warningText,
              ),
          ],
        ),
        CodeLabStatusTableCell(
          entry.invokeAs ?? 'Model only',
          mono: entry.invokeAs != null,
          muted: entry.invokeAs == null,
          untrusted: true,
        ),
        CodeLabStatusTableCell(entry.root.label, mono: true, untrusted: true),
      ],
      toggle: CodeLabStatusTableToggle(
        key: ValueKey('skills-toggle-${entry.name}'),
        value: enabled,
        label: 'Enabled: ${entry.name}',
        // Активен, если мост не отказал и запись не идёт; отказ — подсказка с
        // причиной (D5, D9). Что писать, решает Cubit по свежему снимку.
        onChanged: entry.toggle.isAvailable && !saving
            ? (value) =>
                  unawaited(cubit.setSkillEnabled(entry.name, enabled: value))
            : null,
        tooltip: entry.toggle.refusal == null
            ? null
            : skillsRefusalText(entry.toggle.refusal!),
      ),
      action: CodeLabStatusTableAction(
        key: ValueKey('skills-open-skill-${entry.name}'),
        label: 'Open',
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
    SkillsSettingsCubit cubit,
    List<SkillConsentView> consents, {
    required bool saving,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: CodeLabStatusTable(
      columns: const ['SKILLS OF OTHER AGENTS'],
      rows: [
        for (final consent in consents)
          _consentRow(cubit, consent, saving: saving),
      ],
    ),
  );

  CodeLabStatusTableRow _consentRow(
    SkillsSettingsCubit cubit,
    SkillConsentView consent, {
    required bool saving,
  }) {
    final kind = consentKindOf(consent.entry);
    final count = consent.skillDirs;
    final found = count == null
        ? 'The number of skill folders is not counted.'
        : '$count skill ${count == 1 ? 'folder' : 'folders'} found.';
    final scope = kind == SkillsConsentKind.home
        ? ''
        : ' Consent applies in every trusted project.';
    return CodeLabStatusTableRow(
      key: ValueKey('skills-consent-note-${kind.key}'),
      cells: [
        CodeLabStatusTableCell(
          'Read ${consent.entry}',
          mono: true,
          secondary:
              '$found$scope The .agents/skills folder of a trusted project is '
              'read without consent.',
        ),
      ],
      toggle: CodeLabStatusTableToggle(
        key: ValueKey('skills-consent-${kind.key}'),
        value: consent.granted,
        label: 'Read ${consent.entry}',
        onChanged: consent.toggle.isAvailable && !saving
            ? (value) =>
                  unawaited(cubit.setRootConsent(consent.entry, granted: value))
            : null,
        tooltip: consent.toggle.refusal == null
            ? null
            : skillsRefusalText(
                consent.toggle.refusal!,
                element: consent.entry,
              ),
      ),
    );
  }

  List<Widget> _skillWarnings(List<ExtensionDiagnostic> all) {
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
          '${shown.length} ${shown.length == 1 ? 'warning' : 'warnings'}',
          content: _diagnosticLines(shown),
        ),
      ),
    ];
  }

  List<Widget> _diagnostics(Key key, List<ExtensionDiagnostic> all) {
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
          '${shown.length} ${shown.length == 1 ? 'warning' : 'warnings'}',
          content: _diagnosticLines(shown),
        ),
      ),
    ];
  }

  /// Тексты диагностик ядра фиксированы, пути — из файлов и недоверенны:
  /// строки рисует таблица с `untrusted`, чтобы управляющие и bidi-символы
  /// стали видимыми (D12; `escapeForDisplay` пакета не экспортируется).
  static Widget _diagnosticLines(List<ExtensionDiagnostic> shown) =>
      CodeLabStatusTable(
        columns: const ['MESSAGE'],
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
    SectionOutcome outcome, {
    required String subject,
    required Widget Function() child,
  }) => [
    switch (outcome) {
      SectionRead() => child(),
      SectionTimedOut() => CodeLabText('$subject were not read within 5 s.'),
      SectionFailed(:final errorType) => CodeLabText(
        '$subject could not be read ($errorType).',
      ),
      SectionOff(:final source) => CodeLabText(
        'Skills are switched off: skills.enabled is false in $source.',
      ),
    },
  ];

  static String _withoutSlash(String command) =>
      command.startsWith('/') ? command.substring(1) : command;

  /// Путь от папки проекта, если файл внутри неё; иначе как есть.
  static String _relativeTo(String folder, String path) =>
      p.isWithin(folder, path) ? p.relative(path, from: folder) : path;

  /// Размер файла: 1024-ичный, одна цифра после точки (`4.8 KB`).
  static String _size(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
