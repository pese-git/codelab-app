import 'dart:async';

import 'package:codelab_client_core/codelab_client_core.dart'
    show EnvToken, ProfileDraftField, ProfileKind;
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../application/add_profile_cubit.dart';

/// Открывает диалог «Add connection profile» поверх [context].
///
/// Почему функция, а не страница: диалог — модальное окно над страницей
/// «Connection» (макет `AddProfile`, `ContentDialog`; spec app-settings).
/// Cubit [cubit] создаёт и закрывает владелец диалога (страница), чтобы
/// закрытие диалога любым способом отменяло идущую проверку.
///
/// Для чего: Esc и «Cancel» закрывают диалог без записи — в файл и в
/// `shared_preferences` пишет только `AddProfileCubit.save`. Фон не закрывает
/// диалог: случайный щелчок не должен терять введённое.
///
/// Как использовать: `await showAddProfileDialog(context, cubit)`; после
/// возврата владелец читает `cubit.state` (`Saved` — профиль записан) и
/// закрывает Cubit.
Future<void> showAddProfileDialog(BuildContext context, AddProfileCubit cubit) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => BlocProvider<AddProfileCubit>.value(
      value: cubit,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              unawaited(Navigator.of(dialogContext).maybePop()),
        },
        // Без узла фокуса внутри диалога Esc после щелчка по флажку не дошёл
        // бы до привязки.
        child: const Focus(autofocus: true, child: AddProfileDialog()),
      ),
    ),
  );
}

/// Содержимое диалога «Add connection profile» и экран «Profile saved»
/// (макет `docs/design/claude-design/AddProfile.dc.html`; расхождения и их
/// решения — design.md change `add-app-settings-shell`, D20).
///
/// Почему: форма добавления профиля — отдельный модальный сценарий, а не
/// часть страницы (spec app-settings «Диалог «Add connection profile»»).
///
/// Для чего: только отображение `AddProfileState`. Что доступно («Save»,
/// «Test connection»), что показывать (ошибки, подсказки, подтверждение) и
/// чем заканчивается проверка, решает `AddProfileCubit`; виджет передаёт
/// ввод и нажатия и не знает ни файлов, ни окружения, ни ACP (AGENTS.md §6,
/// §7, §10). Значение токена здесь не вводится: только имя переменной (D13).
///
/// Как использовать: под `BlocProvider<AddProfileCubit>`; открывает его
/// [showAddProfileDialog].
class AddProfileDialog extends StatelessWidget {
  const AddProfileDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AddProfileCubit, AddProfileState>(
      builder: (context, state) => switch (state) {
        Saved() => _SavedDialog(saved: state),
        AddProfileInProgress() => _FormDialog(state: state),
      },
    );
  }
}

/// Ширина диалога макета (`.ap-dlg`).
const _dialogMaxWidth = 560.0;

class _FormDialog extends StatelessWidget {
  const _FormDialog({required this.state});

  final AddProfileInProgress state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AddProfileCubit>();
    final form = state.form;
    final busy = state is Probing || state is Saving;
    final saving = state is Saving;

    // Пока профиль пишется, диалог не закрывается (Esc, «Cancel»): иначе
    // страница не узнала бы о записи, а пользователь решил бы, что отменил
    // её. Закрытие остаётся доступным при проверке: Cubit отменяет её сам.
    return PopScope(
      canPop: !saving,
      child: ContentDialog(
        constraints: const BoxConstraints(maxWidth: _dialogMaxWidth),
        title: const _DialogTitle('Add connection profile'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Subtitle(id: form.draft.id, path: cubit.profilesPathLabel),
              const SizedBox(height: 12),
              _Fields(state: state),
              if (state case ConfirmingPlaintext(:final message))
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _CaptionInfoBar(
                    key: const ValueKey('add-profile-unencrypted'),
                    severity: InfoBarSeverity.warning,
                    title: 'Unencrypted connection',
                    message: message,
                    action: CodeLabButton(
                      key: const ValueKey('add-profile-save-anyway'),
                      label: 'Save anyway',
                      onPressed: () => unawaited(cubit.confirmPlaintext()),
                    ),
                  ),
                ),
              if (state case ConfirmingPlaintextProbe(:final message))
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _CaptionInfoBar(
                    key: const ValueKey('add-profile-unencrypted'),
                    severity: InfoBarSeverity.warning,
                    title: 'Unencrypted connection',
                    message: message,
                    action: CodeLabButton(
                      key: const ValueKey('add-profile-test-anyway'),
                      label: 'Test anyway',
                      onPressed: () => unawaited(cubit.confirmPlaintextProbe()),
                    ),
                  ),
                ),
              if (state case SaveFailed(:final message))
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: InfoBar(
                    title: Text(message),
                    severity: InfoBarSeverity.error,
                    isLong: true,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          CodeLabButton(
            key: const ValueKey('add-profile-save'),
            label: form.saveLabel,
            emphasis: CodeLabButtonEmphasis.primary,
            onPressed: form.canSave && !busy
                ? () => unawaited(cubit.save())
                : null,
          ),
          CodeLabButton(
            key: const ValueKey('add-profile-cancel'),
            label: 'Cancel',
            onPressed: saving ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// Подзаголовок: куда пишется профиль и как его назвать в CLI.
class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.id, required this.path});

  final String id;

  /// Настоящий путь файла профилей (`AddProfileCubit.profilesPathLabel`).
  final String path;

  @override
  Widget build(BuildContext context) {
    final resources = FluentTheme.of(context).resources;
    final caption = CodeLabText.styleOf(context, CodeLabTextRole.caption);
    final mono = CodeLabText.styleOf(context, CodeLabTextRole.mono);
    return Text.rich(
      TextSpan(
        style: caption?.copyWith(color: resources.textFillColorSecondary),
        children: [
          const TextSpan(text: 'Saved to '),
          TextSpan(text: path, style: mono),
          const TextSpan(text: ' and shared with codelab_cli as '),
          TextSpan(text: 'codelab -a ${id.isEmpty ? '…' : id}', style: mono),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }
}

/// Поля формы в порядке макета: Type, Name, поля типа, Check, After saving.
class _Fields extends StatelessWidget {
  const _Fields({required this.state});

  final AddProfileInProgress state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AddProfileCubit>();
    final form = state.form;
    final draft = form.draft;
    final errors = form.errors;
    final isStdio = draft.kind == ProfileKind.stdio;
    final probing = state is Probing;

    CodeLabFormNote? error(ProfileDraftField field) => errors[field] == null
        ? null
        : CodeLabFormNote(errors[field]!, tone: CodeLabFormNoteTone.error);

    return CodeLabForm(
      children: [
        // Одного типа достаточно для хоста без stdio (SETUP-22): переключателя
        // нет, диалог сразу на нём.
        if (form.kinds.length > 1)
          CodeLabFormRow(
            label: 'Type',
            notes: [
              CodeLabFormNote(
                isStdio
                    ? 'Starts the agent as a child process per window and '
                          'talks ACP over stdin/stdout.'
                    : 'Connects to codelab-agent serve --ws on this or '
                          'another machine.',
              ),
            ],
            child: Align(
              alignment: Alignment.centerLeft,
              child: CodeLabSegmentedControl<ProfileKind>(
                semanticLabel: 'Profile type',
                value: draft.kind,
                options: const [
                  CodeLabSegment(
                    value: ProfileKind.stdio,
                    label: 'Local stdio',
                    key: ValueKey('add-profile-type-stdio'),
                  ),
                  CodeLabSegment(
                    value: ProfileKind.webSocket,
                    label: 'WebSocket',
                    key: ValueKey('add-profile-type-websocket'),
                  ),
                ],
                onChanged: cubit.selectKind,
              ),
            ),
          ),
        CodeLabFormRow(
          label: 'Name',
          notes: [
            _IdLine(id: draft.id, onChanged: cubit.setId),
            ?error(ProfileDraftField.label),
            ?error(ProfileDraftField.id),
          ],
          child: _FormTextBox(
            fieldKey: const ValueKey('add-profile-name'),
            value: draft.label,
            placeholder: 'devbox 2',
            onChanged: cubit.setLabel,
          ),
        ),
        if (isStdio) ..._stdioRows(cubit, form, error),
        if (!isStdio) ..._webSocketRows(cubit, form, error),
        CodeLabFormRow(
          label: 'Check',
          notes: [
            if (form.probeNote case final note?
                when probing || form.probe != null)
              CodeLabFormNote(note, tone: CodeLabFormNoteTone.warning),
            const CodeLabFormNote(
              'Sends initialize only: no session is created, the process or '
              'socket closes right after.',
            ),
          ],
          child: _CheckRow(state: state),
        ),
        CodeLabFormRow(
          label: 'After saving',
          notes: const [
            CodeLabFormNote(
              'Used when CodeLab starts and by Connect on start.',
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Checkbox(
              key: const ValueKey('add-profile-use-by-default'),
              checked: form.useByDefault,
              onChanged: (value) => cubit.setUseByDefault(value ?? false),
              content: const Flexible(child: Text('Use by default')),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _stdioRows(
    AddProfileCubit cubit,
    AddProfileForm form,
    CodeLabFormNote? Function(ProfileDraftField) error,
  ) {
    final draft = form.draft;
    return [
      CodeLabFormRow(
        label: 'Command',
        notes: [?error(ProfileDraftField.command)],
        child: _FormTextBox(
          fieldKey: const ValueKey('add-profile-command'),
          value: draft.command,
          placeholder: 'codelab-agent',
          mono: true,
          onChanged: cubit.setCommand,
        ),
      ),
      CodeLabFormRow(
        label: 'Arguments',
        notes: [
          const CodeLabFormNote(
            'Parsed like a shell: quotes and escapes work.',
          ),
          ?error(ProfileDraftField.args),
        ],
        child: _FormTextBox(
          fieldKey: const ValueKey('add-profile-args'),
          value: draft.args,
          placeholder: 'serve --stdio',
          mono: true,
          onChanged: cubit.setArgs,
        ),
      ),
      CodeLabFormRow(
        label: 'Folder',
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Checkbox(
            key: const ValueKey('add-profile-run-in-project'),
            checked: draft.runInProjectDirectory,
            onChanged: (value) => cubit.setRunInProject(value ?? false),
            // Flexible: в узком диалоге подпись переносится, а не обрезается.
            content: const Flexible(child: Text('Run in the project folder')),
          ),
        ),
      ),
      CodeLabFormRow(
        label: 'Environment',
        notes: [?error(ProfileDraftField.env)],
        child: _FormTextBox(
          fieldKey: const ValueKey('add-profile-env'),
          value: draft.env,
          placeholder: 'RUST_LOG=info',
          mono: true,
          maxLines: 4,
          onChanged: cubit.setEnv,
        ),
      ),
    ];
  }

  List<Widget> _webSocketRows(
    AddProfileCubit cubit,
    AddProfileForm form,
    CodeLabFormNote? Function(ProfileDraftField) error,
  ) {
    final draft = form.draft;
    final token = draft.token;
    return [
      CodeLabFormRow(
        label: 'URL',
        notes: [
          ?error(ProfileDraftField.url),
          if (form.warning case final warning?)
            CodeLabFormNote(warning, tone: CodeLabFormNoteTone.warning),
        ],
        child: _FormTextBox(
          fieldKey: const ValueKey('add-profile-url'),
          value: draft.url,
          placeholder: 'wss://host:7420',
          mono: true,
          onChanged: cubit.setUrl,
        ),
      ),
      CodeLabFormRow(
        label: 'Token',
        // Подсказки D13 показываются всегда: они объясняют, почему вариантов
        // два и почему значения токена здесь нет.
        notes: const [
          CodeLabFormNote(
            'CodeLab reads the token from this environment variable when it '
            'connects. Token values are not saved in profiles.json.',
          ),
          CodeLabFormNote(
            'Apps opened from Finder do not see variables set in your shell '
            'profile.',
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RadioGroup<bool>(
              groupValue: token is EnvToken,
              onChanged: (isEnv) {
                if (isEnv ?? false) {
                  cubit.selectTokenEnv();
                } else {
                  cubit.selectTokenNone();
                }
              },
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadioButton<bool>(
                    key: ValueKey('add-profile-token-none'),
                    value: false,
                    content: Text('No token'),
                  ),
                  SizedBox(height: 6),
                  RadioButton<bool>(
                    key: ValueKey('add-profile-token-env'),
                    value: true,
                    content: Text('From environment variable'),
                  ),
                ],
              ),
            ),
            if (token is EnvToken) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: _FormTextBox(
                  fieldKey: const ValueKey('add-profile-token-env-name'),
                  value: form.tokenEnvName,
                  placeholder: defaultTokenEnvName,
                  mono: true,
                  onChanged: cubit.setTokenEnvName,
                ),
              ),
              if (form.tokenNotice case final notice?)
                Padding(
                  padding: const EdgeInsets.only(left: 28, top: 4),
                  child: CodeLabFormNote(
                    notice,
                    tone: CodeLabFormNoteTone.warning,
                  ),
                ),
              if (error(ProfileDraftField.token) case final note?)
                Padding(
                  padding: const EdgeInsets.only(left: 28, top: 4),
                  child: note,
                ),
            ],
          ],
        ),
      ),
    ];
  }
}

/// Строка id под именем: «id [поле] · cannot change after saving».
///
/// Почему поле, а не текст макета: id можно поправить до сохранения (spec
/// app-settings «Имя и id»); после сохранения нельзя, и подпись говорит об
/// этом.
class _IdLine extends StatelessWidget {
  const _IdLine({required this.id, required this.onChanged});

  final String id;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final resources = FluentTheme.of(context).resources;
    return Row(
      children: [
        CodeLabText(
          'id',
          role: CodeLabTextRole.caption,
          color: resources.textFillColorSecondary,
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 200,
          child: _FormTextBox(
            fieldKey: const ValueKey('add-profile-id'),
            value: id,
            placeholder: 'profile-id',
            mono: true,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: CodeLabText(
            '· cannot change after saving',
            role: CodeLabTextRole.caption,
            color: resources.textFillColorSecondary,
          ),
        ),
      ],
    );
  }
}

/// Строка «Check»: кнопка проверки и её ход или исход.
class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.state});

  final AddProfileInProgress state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AddProfileCubit>();
    final form = state.form;
    final probing = state is Probing;
    final probe = form.probe;
    final resources = FluentTheme.of(context).resources;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 28),
      child: Row(
        children: [
          CodeLabButton(
            key: const ValueKey('add-profile-test'),
            label: 'Test connection',
            onPressed: form.canTest && !probing
                ? () => unawaited(cubit.testConnection())
                : null,
          ),
          const SizedBox(width: 8),
          if (probing) ...[
            const SizedBox.square(
              dimension: 16,
              child: ProgressRing(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: CodeLabText(
                'initialize…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                color: resources.textFillColorSecondary,
              ),
            ),
          ],
          if (probe != null)
            Flexible(
              child: KeyedSubtree(
                key: const ValueKey('add-profile-probe-result'),
                child: CodeLabBadge(
                  label: form.probeText ?? '',
                  tone: probeOutcomeIsOk(probe)
                      ? CodeLabTone.success
                      : CodeLabTone.danger,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Экран «Profile saved».
class _SavedDialog extends StatelessWidget {
  const _SavedDialog({required this.saved});

  final Saved saved;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AddProfileCubit>();
    final resources = FluentTheme.of(context).resources;
    final caption = CodeLabText.styleOf(context, CodeLabTextRole.caption);
    final mono = CodeLabText.styleOf(context, CodeLabTextRole.mono);

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: _dialogMaxWidth),
      title: const _DialogTitle('Profile saved'),
      content: Column(
        key: const ValueKey('add-profile-saved'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _CaptionInfoBar(
            key: const ValueKey('add-profile-saved-bar'),
            severity: InfoBarSeverity.success,
            title: saved.label,
            message: 'Added to profiles.json as ',
            tail: [
              TextSpan(text: saved.profileId, style: mono),
              // Метка «Not tested» хранится только за жизнь страницы
              // (D14), но экран честно говорит о ней сразу.
              if (!saved.tested) const TextSpan(text: ' · marked "Not tested"'),
              if (saved.useByDefault)
                const TextSpan(text: ' · used by default'),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'The current connection is unchanged. Use Connect in the profile '
            'row to switch now.',
            style: caption?.copyWith(color: resources.textFillColorSecondary),
          ),
        ],
      ),
      actions: [
        CodeLabButton(
          key: const ValueKey('add-profile-done'),
          label: 'Done',
          emphasis: CodeLabButtonEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        CodeLabButton(
          key: const ValueKey('add-profile-add-another'),
          label: 'Add another',
          onPressed: cubit.addAnother,
        ),
      ],
    );
  }
}

/// Текстовое поле, значение которого принадлежит Cubit-у.
///
/// Почему `StatefulWidget`: `TextBox` хранит правку в контроллере, а значение
/// (id, следующий за именем; сброс после «Add another») может измениться
/// снаружи. Контроллер принадлежит State и освобождается в `dispose`; текст
/// подменяется только если он действительно отличается, иначе курсор прыгал
/// бы при каждом вводе.
class _FormTextBox extends StatefulWidget {
  const _FormTextBox({
    required this.fieldKey,
    required this.value,
    required this.onChanged,
    this.placeholder,
    this.mono = false,
    this.maxLines = 1,
  });

  /// Ключ самого `TextBox`: по нему тесты вводят и читают текст.
  final Key fieldKey;
  final String value;
  final ValueChanged<String> onChanged;
  final String? placeholder;
  final bool mono;
  final int maxLines;

  @override
  State<_FormTextBox> createState() => _FormTextBoxState();
}

class _FormTextBoxState extends State<_FormTextBox> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(_FormTextBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextBox(
      key: widget.fieldKey,
      controller: _controller,
      placeholder: widget.placeholder,
      minLines: 1,
      maxLines: widget.maxLines,
      style: widget.mono
          ? CodeLabText.styleOf(context, CodeLabTextRole.mono)
          : null,
      onChanged: widget.onChanged,
    );
  }
}

/// Заголовок диалога по артборду: `h2.t-sub` — 20 px / 28 / 600.
///
/// Почему: `ContentDialog` по умолчанию ставит крупный заголовок (~28 px), а
/// артборд `AddProfile` задаёт `typography.subtitle` (fluent.css `.t-sub`).
class _DialogTitle extends StatelessWidget {
  const _DialogTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: CodeLabText.styleOf(context, CodeLabTextRole.subtitle));
}

/// InfoBar артборда (`.f-ib`): одна строка — значок, текст `t-cap` 12/16 с
/// жирным заголовком в начале, действие справа.
///
/// Почему не `InfoBar` Fluent: он ставит текст размера body, а действие
/// переносит под текст; артборд требует caption и кнопку в той же строке
/// (`flex: 1` у текста). Рамка и цвета берутся из `InfoBarTheme`, поэтому
/// вид совпадает с остальными InfoBar приложения.
///
/// Как использовать: [title] — жирное начало, [message] — продолжение,
/// [tail] — доп. фрагменты после него (например, моно-id); [action] —
/// необязательная кнопка справа.
class _CaptionInfoBar extends StatelessWidget {
  const _CaptionInfoBar({
    required this.severity,
    required this.title,
    required this.message,
    this.tail = const [],
    this.action,
    super.key,
  });

  final InfoBarSeverity severity;
  final String title;
  final String message;
  final List<InlineSpan> tail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final style = InfoBarTheme.of(context);
    final caption = CodeLabText.styleOf(context, CodeLabTextRole.caption);
    final icon = style.icon?.call(severity);
    return Container(
      decoration: style.decoration?.call(severity),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          if (icon != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 14),
              child: Icon(
                icon,
                size: 16,
                color: style.iconColor?.call(severity),
              ),
            ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$title ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: message),
                  ...tail,
                ],
              ),
              style: caption,
            ),
          ),
          if (action != null) ...[const SizedBox(width: 12), action!],
        ],
      ),
    );
  }
}
