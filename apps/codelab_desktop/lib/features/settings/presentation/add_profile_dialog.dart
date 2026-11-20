import 'dart:async';

import 'package:codelab_client_core/codelab_client_core.dart'
    show ProfileDraftField, ProfileKind;
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../l10n/l10n.dart';
import '../application/add_profile_cubit.dart';
import 'message_spans.dart';

/// Открывает диалог «Add connection profile» поверх [context].
///
/// Почему функция, а не страница: диалог — модальное окно над страницей
/// «Connection» (макет `AddProfile`, `ContentDialog`; spec app-settings).
/// Cubit [cubit] создаёт и закрывает владелец диалога (страница), чтобы
/// закрытие диалога любым способом закрывало Cubit.
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
        // Esc диалога — запись `close-overlay` каталога кита (D3).
        bindings: CodeLabShortcut.closeOverlay.bind(
          () => unawaited(Navigator.of(dialogContext).maybePop()),
        ),
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
/// Для чего: только отображение `AddProfileState`. Что доступно («Save»),
/// что показывать (ошибки, подсказки, подтверждение `ws://`) и чем
/// заканчивается сохранение, решает `AddProfileCubit`; проверки подключения в
/// диалоге нет (change `remove-test-connection`, D1, D4); виджет передаёт
/// ввод и нажатия и не знает ни файлов, ни окружения, ни ACP (AGENTS.md §6,
/// §7, §10). Значение нового токена вводится в скрытое поле и сразу уходит в
/// Cubit (`SecretText`); виджет его не хранит и не показывает (D13, D14).
///
/// Как использовать: под `BlocProvider<AddProfileCubit>`; открывает его
/// [showAddProfileDialog].
class AddProfileDialog extends StatelessWidget {
  const AddProfileDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AddProfileCubit, AddProfileState>(
      builder: (context, state) => switch (state) {
        OpeningSecrets() => const _OpeningDialog(),
        Saved() => _SavedDialog(saved: state),
        AddProfileInProgress() => _FormDialog(state: state),
      },
    );
  }
}

/// Ширина диалога макета (`.ap-dlg`).
const _dialogMaxWidth = 560.0;

/// Пока открывается хранилище секретов: заголовок и индикатор.
///
/// Макета для этого состояния в `AddProfile` нет; взят существующий образец
/// загрузки страницы «Connection» (`ProgressRing` в `ContentDialog`).
class _OpeningDialog extends StatelessWidget {
  const _OpeningDialog();

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      key: const ValueKey('add-profile-opening'),
      constraints: const BoxConstraints(maxWidth: _dialogMaxWidth),
      title: CodeLabDialogTitle(context.l10n.addProfileTitle),
      content: const Center(
        child: SizedBox.square(dimension: 24, child: ProgressRing()),
      ),
      actions: [
        CodeLabButton(
          key: const ValueKey('add-profile-cancel'),
          label: context.l10n.commonCancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _FormDialog extends StatelessWidget {
  const _FormDialog({required this.state});

  final AddProfileInProgress state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AddProfileCubit>();
    final l10n = context.l10n;
    final form = state.form;
    final saving = state is Saving;

    // Пока профиль пишется, диалог не закрывается (Esc, «Cancel»): иначе
    // страница не узнала бы о записи, а пользователь решил бы, что отменил
    // её.
    return PopScope(
      canPop: !saving,
      child: ContentDialog(
        constraints: const BoxConstraints(maxWidth: _dialogMaxWidth),
        title: CodeLabDialogTitle(l10n.addProfileTitle),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Subtitle(id: form.draft.id, path: cubit.profilesPathLabel),
              const SizedBox(height: 12),
              _Fields(state: state),
              if (state case ConfirmingPlaintext(
                :final origin,
                :final hasToken,
              ))
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _CaptionInfoBar(
                    key: const ValueKey('add-profile-unencrypted'),
                    severity: InfoBarSeverity.warning,
                    title: l10n.addProfilePlaintextTitle,
                    titleIsWidget: true,
                    // Подтверждение `ws://` — всегда, с токеном и без
                    // (решение пользователя 2026-11-05, D11, D20): по
                    // `ws://` открытым текстом идут и промпты с файлами.
                    message: addProfilePlaintextText(
                      l10n,
                      origin: origin,
                      hasToken: hasToken,
                    ),
                    action: CodeLabButton(
                      key: const ValueKey('add-profile-save-anyway'),
                      label: l10n.addProfileSaveAnyway,
                      onPressed: () => unawaited(cubit.confirmPlaintext()),
                    ),
                  ),
                ),
              if (state case SaveFailed(:final failure))
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: InfoBar(
                    title: Text(addProfileFailureText(l10n, failure)),
                    content: switch (addProfileFailureDetail(failure)) {
                      final detail? => Text(detail),
                      null => null,
                    },
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
            label: l10n.commonSave,
            emphasis: CodeLabButtonEmphasis.primary,
            onPressed: form.canSave && !saving
                ? () => unawaited(cubit.save())
                : null,
          ),
          CodeLabButton(
            key: const ValueKey('add-profile-cancel'),
            label: l10n.commonCancel,
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
        // Одно сообщение с двумя моноширинными значениями: порядок слов
        // принадлежит переводу (D5, правило 7).
        children: messageSpans(
          (m) => context.l10n.addProfileSubtitle(m[0], m[1]),
          [
            TextSpan(text: path, style: mono),
            TextSpan(text: 'codelab -a ${id.isEmpty ? '…' : id}', style: mono),
          ],
        ),
      ),
    );
  }
}

/// Поля формы в порядке макета: Type, Name, поля типа, After saving.
class _Fields extends StatelessWidget {
  const _Fields({required this.state});

  final AddProfileInProgress state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AddProfileCubit>();
    final l10n = context.l10n;
    final form = state.form;
    final draft = form.draft;
    final errors = form.errors;
    final isStdio = draft.kind == ProfileKind.stdio;

    CodeLabFormNote? error(ProfileDraftField field) => errors[field] == null
        ? null
        : CodeLabFormNote(errors[field]!, tone: CodeLabFormNoteTone.error);

    return CodeLabForm(
      children: [
        // Одного типа достаточно для хоста без stdio (SETUP-22): переключателя
        // нет, диалог сразу на нём.
        if (form.kinds.length > 1)
          CodeLabFormRow(
            label: l10n.addProfileFieldType,
            notes: [
              CodeLabFormNote(
                isStdio
                    ? l10n.addProfileTypeStdioNote
                    : l10n.addProfileTypeWebSocketNote,
              ),
            ],
            child: Align(
              alignment: Alignment.centerLeft,
              child: CodeLabSegmentedControl<ProfileKind>(
                semanticLabel: l10n.addProfileTypeSemantics,
                value: draft.kind,
                options: [
                  CodeLabSegment(
                    value: ProfileKind.stdio,
                    label: l10n.addProfileTypeStdio,
                    key: const ValueKey('add-profile-type-stdio'),
                  ),
                  const CodeLabSegment(
                    value: ProfileKind.webSocket,
                    // Название протокола не переводится (D7).
                    label: 'WebSocket',
                    key: ValueKey('add-profile-type-websocket'),
                  ),
                ],
                onChanged: cubit.selectKind,
              ),
            ),
          ),
        CodeLabFormRow(
          label: l10n.addProfileFieldName,
          notes: [
            _IdLine(id: draft.id, onChanged: cubit.setId),
            ?error(ProfileDraftField.label),
            ?error(ProfileDraftField.id),
          ],
          child: _FormTextBox(
            fieldKey: const ValueKey('add-profile-name'),
            field: ProfileDraftField.label,
            value: draft.label,
            placeholder: l10n.addProfileNamePlaceholder,
            onChanged: cubit.setLabel,
          ),
        ),
        if (isStdio) ..._stdioRows(l10n, cubit, form, error),
        if (!isStdio) ..._webSocketRows(l10n, cubit, form, error),
        CodeLabFormRow(
          label: l10n.addProfileFieldAfterSaving,
          notes: [CodeLabFormNote(l10n.addProfileUsedWhenAgentStarts)],
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Checkbox(
              key: const ValueKey('add-profile-use-by-default'),
              checked: form.useByDefault,
              onChanged: (value) => cubit.setUseByDefault(value ?? false),
              content: Flexible(child: Text(l10n.addProfileUseByDefault)),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _stdioRows(
    AppLocalizations l10n,
    AddProfileCubit cubit,
    AddProfileForm form,
    CodeLabFormNote? Function(ProfileDraftField) error,
  ) {
    final draft = form.draft;
    return [
      CodeLabFormRow(
        label: l10n.addProfileFieldCommand,
        notes: [?error(ProfileDraftField.command)],
        child: _FormTextBox(
          fieldKey: const ValueKey('add-profile-command'),
          field: ProfileDraftField.command,
          value: draft.command,
          placeholder: 'codelab-agent',
          mono: true,
          onChanged: cubit.setCommand,
        ),
      ),
      CodeLabFormRow(
        label: l10n.addProfileFieldArguments,
        notes: [
          CodeLabFormNote(l10n.addProfileArgumentsNote),
          ?error(ProfileDraftField.args),
        ],
        child: _FormTextBox(
          fieldKey: const ValueKey('add-profile-args'),
          field: ProfileDraftField.args,
          value: draft.args,
          placeholder: 'serve --stdio',
          mono: true,
          onChanged: cubit.setArgs,
        ),
      ),
      CodeLabFormRow(
        label: l10n.addProfileFieldFolder,
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Checkbox(
            key: const ValueKey('add-profile-run-in-project'),
            checked: draft.runInProjectDirectory,
            onChanged: (value) => cubit.setRunInProject(value ?? false),
            // Flexible: в узком диалоге подпись переносится, а не обрезается.
            content: Flexible(child: Text(l10n.addProfileRunInProject)),
          ),
        ),
      ),
      CodeLabFormRow(
        label: l10n.addProfileFieldEnvironment,
        notes: [?error(ProfileDraftField.env)],
        child: _FormTextBox(
          fieldKey: const ValueKey('add-profile-env'),
          field: ProfileDraftField.env,
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
    AppLocalizations l10n,
    AddProfileCubit cubit,
    AddProfileForm form,
    CodeLabFormNote? Function(ProfileDraftField) error,
  ) {
    final draft = form.draft;
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
          field: ProfileDraftField.url,
          value: draft.url,
          placeholder: 'wss://host:7420',
          mono: true,
          onChanged: cubit.setUrl,
        ),
      ),
      CodeLabFormRow(
        label: l10n.addProfileFieldToken,
        child: _TokenChoices(form: form, error: error(ProfileDraftField.token)),
      ),
    ];
  }
}

/// Четыре варианта токена WebSocket-профиля (design.md change
/// `add-provider-setup-ui`, D14; артборд `AddProfile`; «From environment
/// variable» — отступление D24).
///
/// Почему отдельный виджет: у каждого варианта своё поле и подсказка, а
/// доступность вариантов («Use stored secret» без имён, «Store a new token» в
/// хранилище только для чтения) решает Cubit (`AddProfileForm`), виджет её
/// только показывает (AGENTS.md §10).
///
/// Для чего: переводит выбор пользователя в вызовы `AddProfileCubit`. Значение
/// нового токена вводится в `PasswordBox` без режима подглядывания и нигде
/// больше не показывается; поле принадлежит этому виджету и исчезает при
/// выборе другого варианта.
class _TokenChoices extends StatelessWidget {
  const _TokenChoices({required this.form, required this.error});

  final AddProfileForm form;
  final CodeLabFormNote? error;

  static const _indent = EdgeInsets.only(left: 28, top: 4);

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AddProfileCubit>();
    final l10n = context.l10n;
    final kind = form.tokenKind;
    final storedHint = form.storedSecretsHint;
    // Подсказка недоступного «Store a new token» видна всегда (причина, D3),
    // доступного — только пока вариант выбран (артборд).
    final showNewHint =
        !form.newTokenAvailable || kind == AddProfileTokenKind.newToken;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RadioGroup<AddProfileTokenKind>(
          groupValue: kind,
          onChanged: (value) {
            switch (value) {
              case AddProfileTokenKind.none:
                cubit.selectTokenNone();
              case AddProfileTokenKind.stored:
                cubit.selectTokenStored();
              case AddProfileTokenKind.newToken:
                cubit.selectTokenNew();
              case AddProfileTokenKind.env:
                cubit.selectTokenEnv();
              case null:
                break;
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioButton<AddProfileTokenKind>(
                key: const ValueKey('add-profile-token-none'),
                value: AddProfileTokenKind.none,
                content: Text(l10n.addProfileTokenNone),
              ),
              const SizedBox(height: 6),
              RadioButton<AddProfileTokenKind>(
                key: const ValueKey('add-profile-token-stored'),
                value: AddProfileTokenKind.stored,
                enabled: storedHint == null,
                content: Text(l10n.addProfileTokenStored),
              ),
              if (storedHint != null)
                Padding(
                  padding: _indent,
                  child: CodeLabFormNote(
                    storedHint,
                    key: const ValueKey('add-profile-token-stored-hint'),
                  ),
                ),
              if (kind == AddProfileTokenKind.stored)
                Padding(
                  padding: _indent,
                  child: ComboBox<String>(
                    key: const ValueKey('add-profile-token-stored-name'),
                    isExpanded: true,
                    value: form.storedSecretName,
                    items: [
                      for (final name in form.secretNames)
                        ComboBoxItem<String>(value: name, child: Text(name)),
                    ],
                    onChanged: (name) {
                      if (name != null) {
                        cubit.setStoredSecret(name);
                      }
                    },
                  ),
                ),
              const SizedBox(height: 6),
              RadioButton<AddProfileTokenKind>(
                key: const ValueKey('add-profile-token-new'),
                value: AddProfileTokenKind.newToken,
                enabled: form.newTokenAvailable,
                content: Text(l10n.addProfileTokenNew),
              ),
              if (kind == AddProfileTokenKind.newToken)
                Padding(
                  padding: _indent,
                  child: PasswordBox(
                    key: const ValueKey('add-profile-token-new-value'),
                    placeholder: l10n.addProfileTokenPaste,
                    // Значение не показывается ни во время ввода, ни после
                    // (spec app-settings «Диалог «Add connection profile»»).
                    revealMode: PasswordRevealMode.hidden,
                    onChanged: cubit.setNewToken,
                  ),
                ),
              if (showNewHint)
                Padding(
                  padding: _indent,
                  child: CodeLabFormNote(
                    form.newTokenHint,
                    key: const ValueKey('add-profile-token-backend'),
                  ),
                ),
              if (showNewHint && form.newTokenDetail != null)
                Padding(
                  padding: _indent,
                  child: CodeLabFormNote(
                    form.newTokenDetail!,
                    key: const ValueKey('add-profile-token-backend-detail'),
                  ),
                ),
              const SizedBox(height: 6),
              RadioButton<AddProfileTokenKind>(
                key: const ValueKey('add-profile-token-env'),
                value: AddProfileTokenKind.env,
                content: Text(l10n.addProfileTokenEnv),
              ),
            ],
          ),
        ),
        if (kind == AddProfileTokenKind.env) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: _FormTextBox(
              fieldKey: const ValueKey('add-profile-token-env-name'),
              field: ProfileDraftField.token,
              value: form.tokenEnvName,
              placeholder: defaultTokenEnvName,
              mono: true,
              onChanged: cubit.setTokenEnvName,
            ),
          ),
          // Подписи варианта видны, только когда он выбран (как «Saved as …»
          // у «Store a new token»): они объясняют, откуда берётся токен и
          // почему приложение из Finder может его не увидеть.
          Padding(
            padding: _indent,
            child: CodeLabFormNote(l10n.addProfileTokenEnvNote),
          ),
          Padding(
            padding: _indent,
            child: CodeLabFormNote(l10n.addProfileTokenEnvFinderNote),
          ),
          if (form.tokenNotice case final notice?)
            Padding(
              padding: _indent,
              child: CodeLabFormNote(notice, tone: CodeLabFormNoteTone.warning),
            ),
        ],
        // Ошибка поля токена: «секрет уже есть», пустой токен, имя секрета.
        if (error case final note?) Padding(padding: _indent, child: note),
      ],
    );
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
            field: ProfileDraftField.id,
            value: id,
            placeholder: 'profile-id',
            mono: true,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: CodeLabText(
            context.l10n.addProfileIdCannotChange,
            role: CodeLabTextRole.caption,
            color: resources.textFillColorSecondary,
          ),
        ),
      ],
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
    final l10n = context.l10n;
    final resources = FluentTheme.of(context).resources;
    final caption = CodeLabText.styleOf(context, CodeLabTextRole.caption);
    final mono = CodeLabText.styleOf(context, CodeLabTextRole.mono);

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: _dialogMaxWidth),
      title: CodeLabDialogTitle(l10n.addProfileSavedTitle),
      content: Column(
        key: const ValueKey('add-profile-saved'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _CaptionInfoBar(
            key: const ValueKey('add-profile-saved-bar'),
            severity: InfoBarSeverity.success,
            title: saved.label,
            // Сообщение одно; id внутри него моноширинный (D5, правило 7).
            message: '',
            spans: [
              ...messageSpans((m) => l10n.addProfileSavedMessage(m[0]), [
                TextSpan(text: saved.profileId, style: mono),
              ]),
              if (saved.useByDefault)
                TextSpan(text: l10n.addProfileSavedUsedByDefault),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            l10n.addProfileSavedNote,
            style: caption?.copyWith(color: resources.textFillColorSecondary),
          ),
        ],
      ),
      actions: [
        CodeLabButton(
          key: const ValueKey('add-profile-done'),
          label: l10n.commonDone,
          emphasis: CodeLabButtonEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        CodeLabButton(
          key: const ValueKey('add-profile-add-another'),
          label: l10n.addProfileAddAnother,
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
    this.field,
    this.placeholder,
    this.mono = false,
    this.maxLines = 1,
  });

  /// Поле черновика: при потере фокуса Cubit показывает его ошибку.
  final ProfileDraftField? field;

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
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocus);
  }

  // Потеря фокуса — «пользователь покинул поле»: ошибка поля становится
  // видна, даже если он ничего не ввёл (решает Cubit, `touchField`).
  void _onFocus() {
    final field = widget.field;
    if (!_focusNode.hasFocus && field != null && mounted) {
      context.read<AddProfileCubit>().touchField(field);
    }
  }

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
    _focusNode
      ..removeListener(_onFocus)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextBox(
      key: widget.fieldKey,
      controller: _controller,
      focusNode: _focusNode,
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

/// InfoBar артборда (`.f-ib`): одна строка — значок, текст `t-cap` 12/16 с
/// жирным заголовком в начале, действие справа.
///
/// Почему не `InfoBar` Fluent: он ставит текст размера body, а действие
/// переносит под текст; артборд требует caption и кнопку в той же строке
/// (`flex: 1` у текста). Рамка и цвета берутся из `InfoBarTheme`, поэтому
/// вид совпадает с остальными InfoBar приложения.
///
/// Как использовать: [title] — жирное начало, [message] — продолжение,
/// [spans] — продолжение готовыми фрагментами (например, с моно-id); [action] —
/// необязательная кнопка справа.
class _CaptionInfoBar extends StatelessWidget {
  const _CaptionInfoBar({
    required this.severity,
    required this.title,
    required this.message,
    this.spans = const [],
    this.titleIsWidget = false,
    this.action,
    super.key,
  });

  final InfoBarSeverity severity;
  final String title;
  final String message;

  /// Продолжение текста готовыми фрагментами (сообщение со стилизованным
  /// значением внутри, `messageSpans`); [message] тогда может быть пустым.
  final List<InlineSpan> spans;

  /// Заголовок — отдельный виджет `Text` внутри строки (для предупреждения
  /// о `ws://`); иначе — жирный фрагмент общего текста.
  final bool titleIsWidget;
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
                  if (titleIsWidget) ...[
                    // Жирное начало — отдельный `Text`, а не `TextSpan`:
                    // заголовок предупреждения остаётся самостоятельным
                    // виджетом (его находят по тексту и читает скринридер), а
                    // продолжение течёт в одной строке с ним, как в макете.
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: Text(
                        title,
                        style: caption?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const TextSpan(text: ' '),
                  ] else
                    TextSpan(
                      text: '$title ',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  if (message.isNotEmpty) TextSpan(text: message),
                  ...spans,
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
