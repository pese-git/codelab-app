import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/widget_previews.dart';

import 'codelab_approval_option_group.dart';
import 'codelab_connection_banner.dart';
import 'codelab_connection_status_row.dart';
import 'codelab_form.dart';
import 'codelab_key_value_list.dart';
import 'codelab_prompt_composer.dart';
import 'codelab_selector_bar.dart';
import 'codelab_session_status_bar.dart';
import 'codelab_settings_row.dart';
import 'codelab_settings_section.dart';
import 'codelab_step_breadcrumb.dart';
import 'codelab_tool_call_summary.dart';
import 'codelab_view_mode.dart';
import '../atomics/atomics.dart';
import '../l10n/codelab_localizations.dart';

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
  name: 'Session status bar',
  group: codelabMoleculePreviewGroup,
  size: Size(620, 100),
)
Widget codelabSessionStatusBarPreview() {
  // `Tooltip` сегментов требует `Overlay`; превью рендерится без `FluentApp`.
  return _AcpPreviewSurface(
    child: Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (_) => const CodeLabSessionStatusBar(
            data: CodeLabSessionStatusData(
              modelLabel: 'GPT-5',
              modeLabel: 'Standard',
              usage: CodeLabStatusSegment(
                label: '12.3k → 1.2k',
                tooltip:
                    'input 9300 · output 1200 · cache read 3000 · '
                    'cache write 0',
              ),
              cost: CodeLabStatusSegment(label: r'$0.0041 · session $1.20'),
              context: CodeLabStatusSegment(
                label: '85% context',
                tone: CodeLabTone.warning,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

@Preview(
  name: 'Session status bar (clickable)',
  group: codelabMoleculePreviewGroup,
  size: Size(620, 100),
)
Widget codelabSessionStatusBarClickablePreview() {
  // Со строкой связано `onTap` (change `add-desktop-usage-pane`, D6): вся
  // строка кликабельна, подсказки сегментов остаются.
  return _AcpPreviewSurface(
    child: Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (_) => CodeLabSessionStatusBar(
            onTap: () {},
            data: const CodeLabSessionStatusData(
              modelLabel: 'GPT-5',
              usage: CodeLabStatusSegment(
                label: '12.3k → 1.2k',
                tooltip: 'input 9300 · output 1200',
              ),
              cost: CodeLabStatusSegment(label: r'$0.0041 · session $1.20'),
            ),
          ),
        ),
      ],
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
        CodeLabLocalizations.delegate,
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

/// Пример пользовательской палитры (`add-app-appearance-page`, D4): теги и
/// значок берут цвета из `CodeLabPalette` в расширениях темы. Данные
/// фиктивные.
@Preview(
  name: 'Custom palette tags',
  group: codelabMoleculePreviewGroup,
  size: Size(360, 120),
)
Widget codelabCustomPalettePreview() {
  return FluentApp(
    debugShowCheckedModeBanner: false,
    theme: FluentThemeData(
      extensions: const [
        CodeLabPalette(
          success: Color(0xFFA6E3A1),
          warning: Color(0xFFF9E2AF),
          danger: Color(0xFFF38BA8),
          accent: Color(0xFF89B4FA),
          info: Color(0xFF89B4FA),
          diffAddBackground: Color(0x331E3A2A),
          diffRemoveBackground: Color(0x333A1E26),
          selection: Color(0x3345475A),
        ),
      ],
    ),
    home: const Padding(
      padding: EdgeInsets.all(16),
      child: Wrap(
        spacing: 8,
        children: [
          CodeLabBadge(label: 'Done', tone: CodeLabTone.success),
          CodeLabBadge(label: 'Failed', tone: CodeLabTone.danger),
          CodeLabIcon(FluentIcons.info, tone: CodeLabTone.accent),
        ],
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
  size: Size(640, 300),
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
        // Элемент под описанием внутри карточки: узкая область, длинная подпись.
        CodeLabSettingsRow(
          title: 'Accent color',
          description: 'Buttons, selection and focus use the system accent',
          footer: Row(
            children: [
              ToggleSwitch(checked: false, onChanged: (_) {}),
              const SizedBox(width: 8),
              const Expanded(child: Text('Use system accent')),
            ],
          ),
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

/// Образец полосы вкладок страницы «Legal» на `ru`: длинные подписи в узкой
/// области показывают прокрутку вместо многоточия (design.md change
/// `add-app-legal-page`, D6, задача 3.2).
@Preview(
  name: 'Selector bar (ru)',
  group: codelabMoleculePreviewGroup,
  size: Size(400, 80),
)
Widget codelabSelectorBarPreview() {
  return _AcpPreviewSurface(
    child: CodeLabSelectorBar<String>(
      value: 'privacy',
      semanticLabel: 'Правовые документы',
      onChanged: (_) {},
      items: const [
        CodeLabSelectorItem(
          value: 'privacy',
          label: 'Политика конфиденциальности',
        ),
        CodeLabSelectorItem(value: 'terms', label: 'Условия использования'),
        CodeLabSelectorItem(value: 'license', label: 'Лицензия'),
        CodeLabSelectorItem(value: 'notices', label: 'Сторонние уведомления'),
      ],
    ),
  );
}

@Preview(
  name: 'Key-value list',
  group: codelabMoleculePreviewGroup,
  size: Size(620, 160),
)
Widget codelabKeyValueListPreview() {
  return _AcpPreviewSurface(child: _keyValueSample());
}

@Preview(
  name: 'Key-value list (dark)',
  group: codelabMoleculePreviewGroup,
  size: Size(620, 160),
  brightness: Brightness.dark,
)
Widget codelabKeyValueListDarkPreview() {
  return _AcpPreviewSurface(
    brightness: Brightness.dark,
    child: _keyValueSample(),
  );
}

Widget _keyValueSample() {
  return const CodeLabKeyValueList(
    entries: [
      CodeLabKeyValueEntry(
        label: 'Key',
        value: 'In keychain-macos as ',
        monoValue: 'codelab/anthropic',
      ),
      CodeLabKeyValueEntry(
        label: 'Last check',
        value: '14:01 · 12 models · 184 ms',
      ),
      CodeLabKeyValueEntry(
        label: 'Source',
        monoValue: '~/.codelab/config.yaml',
      ),
    ],
  );
}

@Preview(
  name: 'Step breadcrumb',
  group: codelabMoleculePreviewGroup,
  size: Size(620, 60),
)
Widget codelabStepBreadcrumbPreview() {
  return const _AcpPreviewSurface(child: _BreadcrumbSample());
}

@Preview(
  name: 'Step breadcrumb (dark)',
  group: codelabMoleculePreviewGroup,
  size: Size(620, 60),
  brightness: Brightness.dark,
)
Widget codelabStepBreadcrumbDarkPreview() {
  return const _AcpPreviewSurface(
    brightness: Brightness.dark,
    child: _BreadcrumbSample(),
  );
}

class _BreadcrumbSample extends StatelessWidget {
  const _BreadcrumbSample();

  @override
  Widget build(BuildContext context) {
    return const CodeLabStepBreadcrumb(
      steps: ['API type', 'Base URL', 'Key', 'Check', 'Model', 'Review'],
      current: 3,
    );
  }
}

/// Кейкапы сочетаний: одна комбинация и альтернативы (change
/// `add-app-keyboard-page`, D6). Клавиши по платформе выбирает каталог.
@Preview(
  name: 'Keycaps',
  group: codelabMoleculePreviewGroup,
  size: Size(420, 120),
)
Widget codelabKeycapsPreview() {
  return _AcpPreviewSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CodeLabKeycaps(
          combos: CodeLabShortcut.allowAlways.combosFor(defaultTargetPlatform),
        ),
        const SizedBox(height: 12),
        CodeLabKeycaps(combos: CodeLabShortcut.fileTreeMove.combos),
      ],
    ),
  );
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
