import 'dart:async';

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/app_scope.dart';
import '../application/connection_settings_cubit.dart';

/// Тело страницы «Connection» для таблицы `settingsPageBuilders`.
///
/// Почему отдельный виджет-хозяин: Cubit страницы создаётся на каждое открытие
/// (файл профилей перечитывается при открытии, D4), а построитель таблицы —
/// просто функция от `BuildContext`.
Widget buildConnectionPage(BuildContext context) => const ConnectionPageHost();

/// Создаёт `ConnectionSettingsCubit` страницы, читает файл и закрывает Cubit
/// вместе со страницей.
///
/// Почему не виджет, создающий репозитории: Cubit собирает composition root
/// (`CodeLabDependencies.createConnectionSettingsCubit`); здесь он только
/// получает владельца жизненного цикла (AGENTS.md §6: виджет не создаёт
/// зависимостей).
class ConnectionPageHost extends StatefulWidget {
  const ConnectionPageHost({super.key});

  @override
  State<ConnectionPageHost> createState() => _ConnectionPageHostState();
}

class _ConnectionPageHostState extends State<ConnectionPageHost> {
  ConnectionSettingsCubit? _cubit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cubit == null) {
      final cubit = codeLabDependenciesOf(
        context,
      ).createConnectionSettingsCubit();
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
      BlocProvider.value(value: _cubit!, child: const ConnectionPage());
}

/// Страница настроек «Connection»: профили подключения и блок «Behavior»
/// (макет `docs/design/claude-design/Connection.dc.html`; расхождения и их
/// решения — design.md change `add-app-settings-shell`, D20).
///
/// Почему: подключение окна к агенту — настройка app, а не диалог из сайдбара;
/// профили общие с CLI (spec app-settings «Список профилей на странице
/// «Connection»»).
///
/// Для чего: только отображение состояния `ConnectionSettingsCubit`. Что
/// доступно (Remove, Restart), решает Cubit (`canRemove`, `canRestart`);
/// страница получает решение пользователя и вызывает его методы. Значение
/// токена здесь недоступно: строка показывает только источник.
///
/// Как использовать: `Cubit` берётся из `BlocProvider` выше по дереву.
/// [onAddProfile], [onTestProfile] и [onRenameProfile] — точки итерации 3
/// (диалог «Add connection profile», «Test connection», «Rename»); без
/// обработчика кнопка недоступна.
class ConnectionPage extends StatefulWidget {
  const ConnectionPage({
    this.onAddProfile,
    this.onTestProfile,
    this.onRenameProfile,
    super.key,
  });

  final VoidCallback? onAddProfile;
  final ValueChanged<ConnectionProfileRow>? onTestProfile;
  final ValueChanged<ConnectionProfileRow>? onRenameProfile;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  /// Раскрытие справки — эфемерное состояние виджета (`state-management.md`).
  var _helpExpanded = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectionSettingsCubit, ConnectionSettingsState>(
      builder: (context, state) {
        final cubit = context.read<ConnectionSettingsCubit>();
        return switch (state) {
          ConnectionSettingsLoading() => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: ProgressRing()),
          ),
          ConnectionSettingsLoaded() => _content(context, cubit, state),
        };
      },
    );
  }

  Widget _content(
    BuildContext context,
    ConnectionSettingsCubit cubit,
    ConnectionSettingsLoaded state,
  ) {
    final ready = state is ConnectionSettingsReady ? state : null;
    final rows = state.rows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: CodeLabText('Connection', role: CodeLabTextRole.title),
            ),
            // В CommandBar только «Add profile»: «Restart agent» стоит рядом
            // со своим объяснением в блоке «Behavior» (D9).
            CodeLabButton(
              key: const ValueKey('connection-add-profile'),
              label: 'Add profile',
              icon: FluentIcons.add,
              emphasis: CodeLabButtonEmphasis.primary,
              onPressed: ready == null ? null : widget.onAddProfile,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (state is ConnectionSettingsUnreadable)
          _bar(
            const ValueKey('connection-profiles-unreadable'),
            InfoBarSeverity.error,
            switch (state.path) {
              final path? =>
                'Cannot read $path: ${state.reason}. Fix or remove the '
                    'file; CodeLab will not overwrite it.',
              null => 'Cannot use the profiles: ${state.reason}.',
            },
          ),
        if (state.failure case final failure?)
          _bar(
            const ValueKey('connection-failure'),
            InfoBarSeverity.error,
            failure,
          ),
        if (state.showsReadOnlyNotice)
          _bar(
            const ValueKey('connection-remote-read-only'),
            InfoBarSeverity.warning,
            'Read-only: this agent runs on ${state.remoteOrigin}',
            content:
                'Change providers and MCP on that host: codelab provider add, '
                'codelab mcp add, codelab config set.',
          ),
        if (ready != null && ready.ignoredDefaultEntry)
          _bar(
            const ValueKey('connection-profiles-ignored-default'),
            InfoBarSeverity.warning,
            'Profile "default" in profiles.json is ignored: default is the '
            'built-in agent. Remove it with codelab profiles remove default.',
            action: CodeLabButton(
              label: 'Remove',
              onPressed: () => unawaited(_removeIgnoredDefault(cubit)),
            ),
          ),
        CodeLabSettingsSection(
          title: 'Profiles',
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: CodeLabText(
                'Shared with codelab_cli through profiles.json in '
                r'$CODELAB_HOME. The default profile is used when CodeLab '
                'starts and by Connect before the first connection.',
                role: CodeLabTextRole.caption,
              ),
            ),
            // Радиокнопки строк образуют одну группу: выбранная — профиль по
            // умолчанию, а не текущий; «Connect» профиль по умолчанию не
            // меняет (D5).
            RadioGroup<String>(
              groupValue: switch (state) {
                ConnectionSettingsReady(:final defaultProfileId) =>
                  defaultProfileId,
                ConnectionSettingsUnreadable() => rows.first.id,
              },
              onChanged: (id) {
                if (id != null) {
                  unawaited(cubit.selectDefault(id));
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final row in rows) ...[
                    if (row != rows.first) const SizedBox(height: 4),
                    _ProfileRowCard(
                      row: row,
                      editable: ready != null,
                      onConnect: () => unawaited(cubit.connect(row.id)),
                      onTest: widget.onTestProfile == null
                          ? null
                          : () => widget.onTestProfile!(row),
                      onRename: widget.onRenameProfile == null
                          ? null
                          : () => widget.onRenameProfile!(row),
                      onRemove: () => unawaited(_removeProfile(cubit, row)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        // «Behavior» не зависит от `profiles.json` и есть в любом состоянии
        // (D4).
        CodeLabSettingsSection(
          title: 'Behavior',
          children: [
            CodeLabSettingsRow(
              title: 'Connect on start',
              description:
                  'Off: the app opens disconnected and waits for Connect',
              leading: FluentIcons.power_button,
              trailing: ToggleSwitch(
                key: const ValueKey('connection-connect-on-start'),
                checked: state.connectOnStart,
                onChanged: (value) => unawaited(cubit.setConnectOnStart(value)),
              ),
            ),
            _restartRow(cubit, state),
          ],
        ),
        const SizedBox(height: 12),
        CodeLabExpanderCard(
          // Ключ — на нажимаемом заголовке, а не на всей карточке: по нему
          // автотест раскрывает справку.
          headerKey: const ValueKey('connection-join-cli-help'),
          leading: const Icon(FluentIcons.command_prompt, size: 16),
          title: const CodeLabText('Join a session started in the CLI'),
          expanded: _helpExpanded,
          onToggle: (value) => setState(() => _helpExpanded = value),
          // Справка без замка, режима «только чтение» и «Fork»: lease не
          // реализован (D10).
          body: _helpExpanded
              ? const CodeLabText(
                  'On the host run codelab-agent serve --ws <port>; the CLI '
                  'connects with codelab -a <profile>. Choose the same '
                  'WebSocket profile here; its sessions appear in the '
                  'sidebar.',
                  role: CodeLabTextRole.caption,
                )
              : null,
        ),
      ],
    );
  }

  Widget _restartRow(
    ConnectionSettingsCubit cubit,
    ConnectionSettingsLoaded state,
  ) {
    return CodeLabSettingsRow(
      key: const ValueKey('connection-restart-row'),
      title: state.restartTitle,
      // Честный текст о переподключении цели без обещания `session/cancel`
      // (D9).
      description: state.restartDescription,
      leading: FluentIcons.refresh,
      trailing: CodeLabButton(
        key: const ValueKey('connection-restart-agent'),
        label: state.restartButtonLabel,
        onPressed: state.canRestart
            ? () => unawaited(cubit.restartAgent())
            : null,
      ),
    );
  }

  Widget _bar(
    Key key,
    InfoBarSeverity severity,
    String title, {
    String? content,
    Widget? action,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: InfoBar(
      key: key,
      title: Text(title),
      content: content == null ? null : Text(content),
      severity: severity,
      action: action,
      isLong: true,
    ),
  );

  /// Подтверждение и удаление: решение — за пользователем, запрет удаления
  /// текущего и встроенного — за Cubit (проверяется и при прямом вызове).
  Future<void> _removeProfile(
    ConnectionSettingsCubit cubit,
    ConnectionProfileRow row,
  ) async {
    final confirmed = await _confirmRemove(
      title: 'Remove profile ${row.title}?',
      details:
          'The entry is deleted from profiles.json. Environment variables '
          'and other settings are not touched.',
    );
    if (confirmed && mounted) {
      await cubit.removeProfile(row.id);
    }
  }

  Future<void> _removeIgnoredDefault(ConnectionSettingsCubit cubit) async {
    final confirmed = await _confirmRemove(
      title: 'Remove the ignored "default" profile?',
      details:
          'Only the "default" entry is deleted from profiles.json; other '
          'profiles stay.',
    );
    if (confirmed && mounted) {
      await cubit.removeIgnoredDefault();
    }
  }

  Future<bool> _confirmRemove({
    required String title,
    required String details,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ContentDialog(
        title: Text(title),
        content: Text(details),
        actions: [
          Button(
            key: const ValueKey('connection-remove-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('connection-remove-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

/// Карточка одной строки профиля.
class _ProfileRowCard extends StatelessWidget {
  const _ProfileRowCard({
    required this.row,
    required this.editable,
    required this.onConnect,
    required this.onTest,
    required this.onRename,
    required this.onRemove,
  });

  final ConnectionProfileRow row;

  /// Файл прочитан: «Rename» и «Remove» доступны (битый файл не трогаем).
  final bool editable;
  final VoidCallback onConnect;
  final VoidCallback? onTest;
  final VoidCallback? onRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final resources = FluentTheme.of(context).resources;
    final id = row.id;
    final token = row.token;

    return DecoratedBox(
      key: ValueKey('connection-profile-row-$id'),
      decoration: BoxDecoration(
        color: resources.cardBackgroundFillColorDefault,
        border: Border.all(
          color: row.isCurrent
              ? FluentTheme.of(context).accentColor
              : resources.cardStrokeColorDefault,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Радиокнопка выбирает профиль по умолчанию, а не текущий:
                // «Connect» профиль по умолчанию не меняет (D5).
                RadioButton<String>(
                  key: ValueKey('connection-profile-default-$id'),
                  value: id,
                  enabled: !row.isUnsaved,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Одна строка с многоточием; полный текст — в
                          // подсказке (D4).
                          Tooltip(
                            message: row.title,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Text(
                                row.title,
                                key: ValueKey('connection-profile-title-$id'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: FluentTheme.of(
                                  context,
                                ).typography.bodyStrong,
                              ),
                            ),
                          ),
                          if (row.isDefault)
                            const CodeLabBadge(
                              label: 'Default',
                              tone: CodeLabTone.accent,
                            ),
                          if (row.isCurrent)
                            const CodeLabBadge(
                              label: 'Current',
                              tone: CodeLabTone.success,
                            ),
                          // Состояние соединения окна — без текста ошибки: её
                          // показывает баннер рабочего места (D4).
                          if (row.status case final status?)
                            KeyedSubtree(
                              key: ValueKey('connection-profile-status-$id'),
                              child: CodeLabBadge(
                                label: status.label,
                                tone: switch (status) {
                                  ConnectionRowStatus.connecting =>
                                    CodeLabTone.warning,
                                  ConnectionRowStatus.connected =>
                                    CodeLabTone.success,
                                  ConnectionRowStatus.failed =>
                                    CodeLabTone.danger,
                                },
                              ),
                            ),
                          // Результат проверки хранится только за жизнь
                          // страницы (D14); «Test connection» — итерация 3.
                          if (row.showNotTested)
                            const CodeLabBadge(label: 'Not tested'),
                        ],
                      ),
                      const SizedBox(height: 2),
                      if (row.isUnsaved)
                        const CodeLabText(
                          'Current connection (not saved)',
                          role: CodeLabTextRole.caption,
                        ),
                      CodeLabText(row.summary, role: CodeLabTextRole.caption),
                      if (token != null)
                        Column(
                          key: ValueKey('connection-profile-token-$id'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _tokenTexts(token),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (row.hasFileActions)
                  CodeLabButton(
                    key: ValueKey('connection-profile-test-$id'),
                    label: 'Test connection',
                    icon: FluentIcons.plug_connected,
                    onPressed: editable ? onTest : null,
                  ),
                CodeLabButton(
                  key: ValueKey('connection-profile-connect-$id'),
                  label: 'Connect',
                  emphasis: CodeLabButtonEmphasis.primary,
                  onPressed: onConnect,
                ),
                if (row.hasFileActions)
                  CodeLabButton(
                    key: ValueKey('connection-profile-rename-$id'),
                    label: 'Rename',
                    onPressed: editable ? onRename : null,
                  ),
                if (row.hasFileActions) _removeButton(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// «Remove»: недоступна у текущего профиля с подсказкой «Disconnect first»
  /// (spec app-settings); решение о доступности принимает Cubit (`canRemove`).
  Widget _removeButton() {
    final button = CodeLabButton(
      key: ValueKey('connection-profile-remove-${row.id}'),
      label: 'Remove',
      onPressed: editable && row.canRemove ? onRemove : null,
    );
    return row.isCurrent
        ? Tooltip(message: 'Disconnect first', child: button)
        : button;
  }

  /// Источник токена: только имя переменной или ссылки, без значения (D13).
  static List<Widget> _tokenTexts(ProfileTokenView token) => switch (token) {
    NoTokenView() => const [
      CodeLabText('No token', role: CodeLabTextRole.caption),
    ],
    EnvTokenView(:final name, :final isSet) => [
      CodeLabText('From \$$name', role: CodeLabTextRole.caption),
      if (!isSet)
        CodeLabText(
          "$name is not set in CodeLab's environment.",
          role: CodeLabTextRole.caption,
        ),
    ],
    UnsupportedTokenView() => const [
      CodeLabText(
        'unrecognized token reference (not supported in this version)',
        role: CodeLabTextRole.caption,
      ),
    ],
  };
}
