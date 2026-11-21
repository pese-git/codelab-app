import 'dart:ui' show PathMetric;

import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';

/// Экран панели сессии, когда проект не выбран (кадр 11a холста Claude Design).
///
/// Почему: `CodeLabStartScreen` — экран одного действия, его делит ветка
/// «проект выбран». У кадра 11a шесть блоков (герой, пояснение, кнопка с
/// подсказкой, зона перетаскивания, карточка агента, InfoBar), и добавлять их
/// необязательными параметрами в старый виджет значило бы держать две
/// несвязанные раскладки под флагами (design.md change
/// `add-empty-project-screen`, D1).
///
/// Для чего: организм без логики (`codelab_ui/AGENTS.md` §2). Он не знает
/// профилей, не решает, какой текст показать, не принимает перетаскивание из
/// ОС — это делает app (D3) и передаёт сюда только состояние [dropActive] и
/// [dropMessage]. Зона и карточка — приватные части организма.
///
/// Как использовать: хост передаёт готовые строки и колбэки. [dropMessage]
/// — текст отказа; он показывается вместо [dropLabel] и [dropHint] с тоном
/// `warning`. Колонка прокручивается, а не переполняется, при низком окне
/// (spec agent-workbench-ui «Экран без выбранного проекта»). Ключи блоков —
/// константы класса.
class CodeLabOpenProjectScreen extends StatelessWidget {
  const CodeLabOpenProjectScreen({
    required this.title,
    required this.description,
    required this.openLabel,
    required this.onOpen,
    required this.dropLabel,
    required this.dropHint,
    required this.agentName,
    required this.agentDetail,
    required this.agentNote,
    required this.settingsLinkLabel,
    required this.onOpenSettings,
    required this.infoTitle,
    required this.infoBody,
    this.openShortcut,
    this.dropActive = false,
    this.dropMessage,
    super.key,
  });

  static const screenKey = ValueKey('open-project-screen');
  static const openKey = ValueKey('start-open-project');
  static const dropZoneKey = ValueKey('open-project-drop-zone');
  static const dropMessageKey = ValueKey('open-project-drop-message');
  static const agentKey = ValueKey('open-project-agent');
  static const agentSettingsKey = ValueKey('open-project-agent-settings');
  static const infoKey = ValueKey('open-project-info');
  static const heroKey = ValueKey('open-project-hero');

  final String title;
  final String description;
  final String openLabel;

  /// Подсказка сочетания рядом с кнопкой (`Ctrl+O`, `⌘O`); `null` — без неё.
  final String? openShortcut;
  final VoidCallback onOpen;

  final String dropLabel;
  final String dropHint;

  /// Элементы из ОС сейчас над экраном: рамка зоны — в цвете акцента.
  final bool dropActive;

  /// Текст отказа последнего броска; `null` — отказа нет.
  final String? dropMessage;

  final String agentName;
  final String agentDetail;
  final String agentNote;
  final String settingsLinkLabel;
  final VoidCallback onOpenSettings;

  final String infoTitle;
  final String infoBody;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Center(
      key: screenKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          // Ширина колонки кадра 11a (`.col{max-width:620px}`, D10).
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Герой кадра: плитка 56×56 со слабым фоном акцента и значком
              // 28 px (`.hero`, D10); «слабый» — тот же акцент с малой
              // непрозрачностью, отдельного токена в палитре нет.
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: DecoratedBox(
                  key: heroKey,
                  decoration: BoxDecoration(
                    color: CodeLabPalette.of(
                      theme,
                    ).accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SizedBox.square(
                    dimension: 56,
                    child: Center(
                      child: Icon(
                        FluentIcons.open_folder_horizontal,
                        size: 28,
                        color: CodeLabPalette.of(theme).accent,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              CodeLabText(title, role: CodeLabTextRole.title),
              const SizedBox(height: 8),
              CodeLabText(description, role: CodeLabTextRole.body),
              const SizedBox(height: 16),
              Row(
                children: [
                  CodeLabButton(
                    key: openKey,
                    label: openLabel,
                    icon: FluentIcons.open_folder_horizontal,
                    emphasis: CodeLabButtonEmphasis.primary,
                    onPressed: onOpen,
                  ),
                  if (openShortcut case final shortcut?) ...[
                    const SizedBox(width: 12),
                    CodeLabText(shortcut, role: CodeLabTextRole.caption),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              _DropZone(
                label: dropLabel,
                hint: dropHint,
                active: dropActive,
                message: dropMessage,
              ),
              const SizedBox(height: 16),
              _AgentCard(
                name: agentName,
                detail: agentDetail,
                note: agentNote,
                linkLabel: settingsLinkLabel,
                onOpenSettings: onOpenSettings,
              ),
              const SizedBox(height: 16),
              InfoBar(
                key: infoKey,
                title: Text(infoTitle),
                content: Text(infoBody),
                isLong: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Зона перетаскивания: только рисует состояние, события не принимает.
class _DropZone extends StatelessWidget {
  const _DropZone({
    required this.label,
    required this.hint,
    required this.active,
    required this.message,
  });

  final String label;
  final String hint;
  final bool active;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final palette = CodeLabPalette.of(theme);
    final borderColor = active
        ? palette.accent
        : theme.resources.controlStrongStrokeColorDefault;
    final text = message;
    final content = Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: text != null
            ? Row(
                key: CodeLabOpenProjectScreen.dropMessageKey,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.warning, size: 14, color: palette.warning),
                  const SizedBox(width: 8),
                  Flexible(
                    child: CodeLabText(
                      text,
                      role: CodeLabTextRole.body,
                      color: palette.warning,
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CodeLabText(label, role: CodeLabTextRole.strong),
                  const SizedBox(height: 4),
                  CodeLabText(hint, role: CodeLabTextRole.caption),
                ],
              ),
      ),
    );
    if (active) {
      // Выделенная зона: сплошная рамка акцента (D10).
      return DecoratedBox(
        key: CodeLabOpenProjectScreen.dropZoneKey,
        decoration: BoxDecoration(
          color: palette.accent.withValues(alpha: 0.08),
          border: Border.all(color: borderColor, width: 2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: content,
      );
    }
    // В покое — пунктир штрихом `strong` (`.drop{border:1px dashed}`): у
    // Fluent и Flutter пунктирной рамки нет, поэтому рисуется здесь.
    return CustomPaint(
      key: CodeLabOpenProjectScreen.dropZoneKey,
      painter: _DashedBorderPainter(
        color: borderColor,
        background: theme.resources.cardBackgroundFillColorDefault,
        radius: 6,
      ),
      child: content,
    );
  }
}

/// Пунктирная рамка со скруглёнными углами и фоном внутри.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({
    required this.color,
    required this.background,
    required this.radius,
  });

  final Color color;
  final Color background;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.5),
      Radius.circular(radius),
    );
    canvas.drawRRect(rect, Paint()..color = background);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..addRRect(rect);
    for (final PathMetric metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 4), stroke);
        distance += 8;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color ||
      old.background != background ||
      old.radius != radius;
}

/// Карточка агента окна: имя, транспорт, пояснение и ссылка в настройки.
class _AgentCard extends StatelessWidget {
  const _AgentCard({
    required this.name,
    required this.detail,
    required this.note,
    required this.linkLabel,
    required this.onOpenSettings,
  });

  final String name;
  final String detail;
  final String note;
  final String linkLabel;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return DecoratedBox(
      key: CodeLabOpenProjectScreen.agentKey,
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        border: Border.all(color: theme.resources.cardStrokeColorDefault),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CodeLabText(name, role: CodeLabTextRole.strong),
            CodeLabText(detail, role: CodeLabTextRole.caption),
            const SizedBox(height: 6),
            CodeLabText(note, role: CodeLabTextRole.body),
            const SizedBox(height: 4),
            // Один узел «ссылка»: кнопка Fluent сама ссылкой не объявляется,
            // поэтому подпись, роль и нажатие задаются здесь, а внутренняя
            // семантика исключается, чтобы не было двух узлов.
            Semantics(
              key: CodeLabOpenProjectScreen.agentSettingsKey,
              link: true,
              button: true,
              label: linkLabel,
              onTap: onOpenSettings,
              excludeSemantics: true,
              child: HyperlinkButton(
                onPressed: onOpenSettings,
                child: Text(linkLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
