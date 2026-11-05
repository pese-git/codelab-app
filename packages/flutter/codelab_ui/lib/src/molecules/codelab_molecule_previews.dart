import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/widget_previews.dart';

import 'codelab_approval_option_group.dart';
import 'codelab_connection_banner.dart';
import 'codelab_connection_status_row.dart';
import 'codelab_form.dart';
import 'codelab_prompt_composer.dart';
import 'codelab_settings_row.dart';
import 'codelab_settings_section.dart';
import 'codelab_tool_call_summary.dart';
import 'codelab_view_mode.dart';
import '../atomics/atomics.dart';

const codelabMoleculePreviewGroup = 'ACP molecules';

@Preview(
  name: 'Prompt composer',
  group: codelabMoleculePreviewGroup,
  size: Size(620, 120),
)
Widget codelabPromptComposerPreview() {
  return _AcpPreviewSurface(
    child: CodeLabPromptComposer(
      initialPrompt: 'Summarize the current diff',
      canCancel: true,
      onSubmit: codelabPreviewPromptSubmit,
      onCancel: codelabPreviewCancel,
    ),
  );
}

@Preview(
  name: 'Tool call summary normal',
  group: codelabMoleculePreviewGroup,
  size: Size(520, 120),
)
Widget codelabToolCallSummaryPreview() {
  return const _AcpPreviewSurface(
    child: CodeLabToolCallSummary(
      name: 'shell',
      target: 'fvm dart analyze',
      status: CodeLabToolCallStatus.running,
      detail: 'cwd packages/flutter/codelab_ui',
    ),
  );
}

@Preview(
  name: 'Tool call summary summary',
  group: codelabMoleculePreviewGroup,
  size: Size(360, 120),
)
Widget codelabToolCallSummarySummaryPreview() {
  return const _AcpPreviewSurface(
    child: CodeLabToolCallSummary(
      name: 'shell',
      target: 'fvm dart analyze',
      status: CodeLabToolCallStatus.running,
      detail: 'cwd packages/flutter/codelab_ui',
      viewMode: CodeLabViewMode.summary,
    ),
  );
}

@Preview(
  name: 'Tool call summary verbose',
  group: codelabMoleculePreviewGroup,
  size: Size(520, 180),
)
Widget codelabToolCallSummaryVerbosePreview() {
  return const _AcpPreviewSurface(
    child: CodeLabToolCallSummary(
      name: 'shell',
      target: 'fvm dart analyze',
      status: CodeLabToolCallStatus.running,
      detail: 'cwd packages/flutter/codelab_ui',
      viewMode: CodeLabViewMode.verbose,
    ),
  );
}

@Preview(
  name: 'Connection status row',
  group: codelabMoleculePreviewGroup,
  size: Size(560, 140),
)
Widget codelabConnectionStatusRowPreview() {
  return const _AcpPreviewSurface(
    child: CodeLabConnectionStatusRow(
      status: CodeLabConnectionStatus.connected,
      transportLabel: 'stdio',
      profileLabel: 'Codelab Agent',
      detail: 'codelab serve --stdio',
    ),
  );
}

@Preview(
  name: 'Connection banner lost',
  group: codelabMoleculePreviewGroup,
  size: Size(620, 140),
)
Widget codelabConnectionBannerPreview() {
  // `InfoBar` читает `FluentLocalizations`; превью рендерится без
  // `FluentApp`, поэтому локализации подключаются здесь.
  return _AcpPreviewSurface(
    child: Localizations(
      locale: const Locale('en'),
      delegates: const [
        FluentLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      child: CodeLabConnectionBanner(
        status: CodeLabConnectionBannerStatus.lost,
        message: 'Agent process exited with code 1.',
        onReconnect: () {},
        onConfigureConnection: () {},
      ),
    ),
  );
}

@Preview(
  name: 'Approval option group',
  group: codelabMoleculePreviewGroup,
  size: Size(520, 180),
)
Widget codelabApprovalOptionGroupPreview() {
  return _AcpPreviewSurface(
    child: CodeLabApprovalOptionGroup(
      selectedOptionId: 'allow_once',
      onSelected: codelabPreviewApprovalSelected,
      options: const [
        CodeLabApprovalOption(
          id: 'allow_once',
          label: 'Allow once',
          kind: CodeLabApprovalOptionKind.allowOnce,
          description: 'Run this command for the active prompt turn.',
          tone: CodeLabTone.warning,
        ),
        CodeLabApprovalOption(
          id: 'reject',
          label: 'Reject',
          kind: CodeLabApprovalOptionKind.rejectOnce,
          description: 'Return a denied outcome to the agent.',
          tone: CodeLabTone.danger,
        ),
      ],
    ),
  );
}

void codelabPreviewPromptSubmit(String prompt) {}

void codelabPreviewApprovalSelected(String optionId) {}

void codelabPreviewCancel() {}

@Preview(
  name: 'Settings section with rows',
  group: codelabMoleculePreviewGroup,
  size: Size(640, 220),
)
Widget codelabSettingsSectionPreview() {
  return _AcpPreviewSurface(
    child: CodeLabSettingsSection(
      title: 'Behavior',
      children: [
        CodeLabSettingsRow(
          leading: FluentIcons.power_button,
          title: 'Connect on start',
          description: 'Off: the app opens disconnected and waits for Connect',
          trailing: ToggleSwitch(checked: true, onChanged: (_) {}),
        ),
        CodeLabSettingsRow(
          leading: FluentIcons.refresh,
          title: 'Restart agent',
          description: 'Cancels running turns and reloads open sessions.',
          trailing: Button(onPressed: () {}, child: const Text('Restart')),
        ),
      ],
    ),
  );
}

/// Образец формы «Add connection profile» (макет `AddProfile`): переключатель
/// типа, поле с подсказкой, предупреждением и ошибкой.
///
/// Почему отдельная функция: светлое и тёмное превью показывают одно и то же,
/// и содержимое не должно разойтись (design.md change
/// `add-app-settings-shell`, D16, задача 3.8a).
Widget _formSample() {
  return CodeLabForm(
    children: [
      CodeLabFormRow(
        label: 'Type',
        child: Align(
          alignment: Alignment.centerLeft,
          child: CodeLabSegmentedControl<String>(
            value: 'websocket',
            semanticLabel: 'Profile type',
            options: const [
              CodeLabSegment(value: 'stdio', label: 'Local stdio'),
              CodeLabSegment(value: 'websocket', label: 'WebSocket'),
            ],
            onChanged: (_) {},
          ),
        ),
      ),
      CodeLabFormRow(
        label: 'URL',
        notes: const [
          CodeLabFormNote('Use ws:// or wss:// with a host.'),
          CodeLabFormNote(
            'ws:// to another machine: the token is sent unencrypted.',
            tone: CodeLabFormNoteTone.warning,
          ),
          CodeLabFormNote('Enter a name.', tone: CodeLabFormNoteTone.error),
        ],
        child: const TextBox(placeholder: 'wss://host:7420/acp'),
      ),
    ],
  );
}

@Preview(
  name: 'Form rows and notes',
  group: codelabMoleculePreviewGroup,
  size: Size(620, 220),
)
Widget codelabFormPreview() {
  return _AcpPreviewSurface(child: _formSample());
}

@Preview(
  name: 'Form rows and notes (dark)',
  group: codelabMoleculePreviewGroup,
  size: Size(620, 220),
  brightness: Brightness.dark,
)
Widget codelabFormDarkPreview() {
  return _AcpPreviewSurface(brightness: Brightness.dark, child: _formSample());
}

class _AcpPreviewSurface extends StatelessWidget {
  const _AcpPreviewSurface({
    required this.child,
    this.brightness = Brightness.light,
  });

  final Widget child;

  /// Тема превью: тёмный вариант нужен виджетам с тонами и обводками (D16).
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: FluentTheme(
        data: FluentThemeData(brightness: brightness),
        child: Builder(
          builder: (context) {
            return ColoredBox(
              color: FluentTheme.of(context).scaffoldBackgroundColor,
              child: Padding(padding: const EdgeInsets.all(16), child: child),
            );
          },
        ),
      ),
    );
  }
}
