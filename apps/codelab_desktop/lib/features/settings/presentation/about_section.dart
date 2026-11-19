import 'dart:async';

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show LicenseRegistry;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/build_version.dart';
import '../../../app/language/app_language_cubit.dart';
import '../../../core/platform/external_link_opener.dart';
import '../../../core/platform/local_folder_opener.dart';
import '../../../l10n/l10n.dart';
import '../application/about_diagnostics.dart';
import '../application/about_ports.dart';
import '../application/third_party_notices.dart';

/// Раздел «About» страницы «General»: версии, лицензия, папка настроек,
/// диагностика, сторонние уведомления, заметки о выпуске и папка журналов
/// (design.md change `add-app-general-page`, D11–D14; spec app-settings
/// «Раздел «About» страницы «General»»).
///
/// Почему без Cubit: данные неизменяемы за время работы окна ([AboutInfo]),
/// а состояние — только «развёрнут ли» (`Expander`) и заметка об исходе
/// последнего действия, то есть эфемерный UI-стейт (AGENTS.md §13).
///
/// Для чего: показывает данные и передаёт нажатия портам [AboutPorts]; что
/// безопасно открывать, решает composition root: адрес — константа app,
/// каталог — путь журналов, а не ввод пользователя. Текст диагностики строит
/// чистая функция `diagnosticsReportOf`, страница только кладёт его в буфер
/// обмена (как «Copy path» панели Files). Строки «Channel» и «Signed by» не
/// показываются: в сборке нет источника их значений (D11).
///
/// Как использовать: `GeneralPage` создаёт раздел, если ему передан
/// [AboutPorts]; `AppLanguageCubit` берётся из ближайшего `BlocProvider`.
class AboutSection extends StatefulWidget {
  const AboutSection({required this.ports, super.key});

  final AboutPorts ports;

  @override
  State<AboutSection> createState() => _AboutSectionState();
}

/// Заметка об исходе последнего действия раздела.
enum _Note { copied, copyFailed, releaseNotesFailed, logsFailed }

class _AboutSectionState extends State<AboutSection> {
  late final Future<AboutInfo?> _info = _loadInfo();

  /// Данные раздела; сбой чтения ресурсов не прячет раздел молча: пишется
  /// имя типа ошибки (без пути и текста), вместо раздела — InfoBar.
  Future<AboutInfo?> _loadInfo() async {
    try {
      return await widget.ports.info();
    } on Object catch (error) {
      widget.ports.logger?.warning(
        'settings.about_load_failed',
        context: {'error_type': error.runtimeType.toString()},
      );
      return null;
    }
  }

  _Note? _note;

  void _log(String action, String outcome) => widget.ports.logger?.info(
    'settings.about_action',
    context: {'action': action, 'outcome': outcome},
  );

  Future<void> _copyDiagnostics(AboutInfo about) async {
    final language = context.read<AppLanguageCubit>().state;
    try {
      final window = await widget.ports.window();
      final report = diagnosticsReportOf(
        about,
        DiagnosticsContext(
          connection: window.connection,
          connectionState: window.state,
          access: window.access,
          locale: language.locale.languageCode,
          languagePreference: language.preference,
          customConfigHome: window.customConfigHome,
        ),
      );
      await Clipboard.setData(ClipboardData(text: report));
    } on Object {
      // Текст исключения в журнал и InfoBar не идёт: в нём бывают пути.
      _log('copy_diagnostics', 'failed');
      if (mounted) {
        setState(() => _note = _Note.copyFailed);
      }
      return;
    }
    _log('copy_diagnostics', 'copied');
    if (mounted) {
      setState(() => _note = _Note.copied);
    }
  }

  Future<void> _openReleaseNotes() async {
    final outcome = await widget.ports.externalLinks.open(
      Uri.parse(kCodeLabReleaseNotesUrl),
    );
    _log('release_notes', switch (outcome) {
      ExternalLinkOutcome.opened => 'opened',
      ExternalLinkOutcome.failed => 'failed',
      ExternalLinkOutcome.rejectedScheme => 'rejected_scheme',
    });
    if (mounted) {
      setState(
        () => _note = outcome == ExternalLinkOutcome.opened
            ? null
            : _Note.releaseNotesFailed,
      );
    }
  }

  Future<void> _openLogs(AboutInfo about) async {
    final outcome = await widget.ports.folders.open(
      about.logDirectory,
      create: false,
    );
    _log('open_logs', switch (outcome) {
      FolderOpenOutcome.opened || FolderOpenOutcome.created => 'opened',
      FolderOpenOutcome.failed => 'failed',
      FolderOpenOutcome.missing => 'missing',
    });
    if (mounted) {
      setState(
        () => _note =
            outcome == FolderOpenOutcome.failed ||
                outcome == FolderOpenOutcome.missing
            ? _Note.logsFailed
            : null,
      );
    }
  }

  Future<void> _showThirdParty(AboutInfo about) async {
    _log('third_party', 'opened');
    await showDialog<void>(
      context: context,
      builder: (_) => _ThirdPartyDialog(notices: about.thirdPartyNotices),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<AboutInfo?>(
      future: _info,
      builder: (context, snapshot) {
        final about = snapshot.data;
        if (about == null) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox.shrink();
          }
          return CodeLabSettingsSection(
            title: l10n.settingsGeneralSectionAbout,
            children: [
              InfoBar(
                key: const ValueKey('settings-general-about-load-failed'),
                title: Text(l10n.settingsGeneralAboutLoadFailed),
                severity: InfoBarSeverity.warning,
              ),
            ],
          );
        }
        final secondary = FluentTheme.of(
          context,
        ).resources.textFillColorSecondary;
        return CodeLabSettingsSection(
          title: l10n.settingsGeneralSectionAbout,
          children: [
            // Ключ на обёртке, а не на `Expander`: Fluent прокидывает ключ
            // вложенному `Expander`, и ключ оказывается в дереве дважды.
            KeyedSubtree(
              key: const ValueKey('settings-general-about'),
              child: Expander(
                header: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CodeLabText('CodeLab ${about.version}'),
                    CodeLabText(
                      l10n.settingsGeneralAboutSubtitle(
                        '${about.os} ${about.arch}',
                        about.embeddedAgentVersion,
                      ),
                      role: CodeLabTextRole.caption,
                      color: secondary,
                    ),
                  ],
                ),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _InfoRow(
                      label: l10n.settingsGeneralAboutLicense,
                      value: about.licenseName,
                      detail: about.licenseCopyright,
                    ),
                    _InfoRow(
                      label: l10n.settingsGeneralAboutConfigFolder,
                      value: about.configHome,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Button(
                          key: const ValueKey(
                            'settings-general-about-copy-diagnostics',
                          ),
                          onPressed: () => unawaited(_copyDiagnostics(about)),
                          child: Text(l10n.settingsGeneralAboutCopyDiagnostics),
                        ),
                        Button(
                          key: const ValueKey(
                            'settings-general-about-third-party',
                          ),
                          onPressed: () => unawaited(_showThirdParty(about)),
                          child: Text(l10n.settingsGeneralAboutThirdParty),
                        ),
                        Button(
                          key: const ValueKey(
                            'settings-general-about-release-notes',
                          ),
                          onPressed: () => unawaited(_openReleaseNotes()),
                          child: Text(l10n.settingsGeneralAboutReleaseNotes),
                        ),
                        Button(
                          key: const ValueKey(
                            'settings-general-about-open-logs',
                          ),
                          onPressed: () => unawaited(_openLogs(about)),
                          child: Text(l10n.settingsGeneralAboutOpenLogs),
                        ),
                      ],
                    ),
                    if (_note case final note?) ...[
                      const SizedBox(height: 8),
                      InfoBar(
                        key: switch (note) {
                          _Note.copied => const ValueKey(
                            'settings-general-about-copied',
                          ),
                          _Note.copyFailed => const ValueKey(
                            'settings-general-about-copy-failed',
                          ),
                          _Note.releaseNotesFailed ||
                          _Note.logsFailed => const ValueKey(
                            'settings-general-about-open-failed',
                          ),
                        },
                        // Только типизированный исход: текста исключения и
                        // пути в InfoBar нет (D14).
                        title: Text(switch (note) {
                          _Note.copied => l10n.settingsGeneralAboutCopied,
                          _Note.copyFailed =>
                            l10n.settingsGeneralAboutCopyFailed,
                          _Note.releaseNotesFailed =>
                            l10n.settingsGeneralAboutReleaseNotesFailed,
                          _Note.logsFailed =>
                            l10n.settingsGeneralAboutLogsFailed,
                        }),
                        severity: note == _Note.copied
                            ? InfoBarSeverity.success
                            : InfoBarSeverity.warning,
                      ),
                    ],
                    const SizedBox(height: 8),
                    InfoBar(
                      key: const ValueKey('settings-general-about-updates'),
                      title: Text(l10n.settingsGeneralAboutUpdates),
                      severity: InfoBarSeverity.info,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Строка «подпись — значение» раздела; значения (`MIT`, путь, версии) не
/// переводятся.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final secondary = FluentTheme.of(context).resources.textFillColorSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          CodeLabText(label, role: CodeLabTextRole.caption, color: secondary),
          CodeLabText(value),
          if (detail != null && detail!.isNotEmpty)
            CodeLabText(
              detail!,
              role: CodeLabTextRole.caption,
              color: secondary,
            ),
        ],
      ),
    );
  }
}

/// Диалог `settings-general-third-party-dialog`: текст
/// `THIRD_PARTY_NOTICES.md` из ресурсов сборки и лицензии пакетов из реестра
/// Flutter (D13).
///
/// Почему не `showLicensePage`: он принадлежит Material и требует своих
/// локализаций и темы, а app на Fluent. Работает без сети: оба источника —
/// ресурсы сборки.
class _ThirdPartyDialog extends StatefulWidget {
  const _ThirdPartyDialog({required this.notices});

  final String notices;

  @override
  State<_ThirdPartyDialog> createState() => _ThirdPartyDialogState();
}

class _ThirdPartyDialogState extends State<_ThirdPartyDialog> {
  late final Future<Map<String, List<String>>> _licenses = _collect();

  /// Записи реестра: выделяются один раз, а не при каждой перестройке диалога.
  late final String _records = thirdPartyRecordsOf(widget.notices);

  /// Лицензии пакетов по имени пакета; сбой реестра не мешает показать
  /// уведомления — остаётся то, что успело собраться.
  Future<Map<String, List<String>>> _collect() async {
    final byPackage = <String, List<String>>{};
    try {
      await for (final entry in LicenseRegistry.licenses) {
        final text = entry.paragraphs.map((p) => p.text).join('\n');
        for (final package in entry.packages) {
          byPackage.putIfAbsent(package, () => []).add(text);
        }
      }
    } on Object {
      // Реестр лицензий недоступен: показываем уведомления без списка.
    }
    return byPackage;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ContentDialog(
      key: const ValueKey('settings-general-third-party-dialog'),
      title: Text(l10n.settingsGeneralAboutThirdParty),
      constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Подпись объясняет, почему записи на русском при любом языке
            // интерфейса: это юридический текст реестра, он не переводится
            // (D13).
            CodeLabText(
              l10n.settingsGeneralAboutThirdPartyCaption,
              role: CodeLabTextRole.caption,
            ),
            const SizedBox(height: 8),
            CodeLabMarkdown(id: 'third-party-notices', text: _records),
            const SizedBox(height: 16),
            CodeLabText(
              l10n.settingsGeneralAboutPackageLicenses,
              role: CodeLabTextRole.strong,
            ),
            const SizedBox(height: 8),
            FutureBuilder<Map<String, List<String>>>(
              future: _licenses,
              builder: (context, snapshot) {
                final licenses = snapshot.data;
                if (licenses == null) {
                  return const Align(
                    alignment: Alignment.centerLeft,
                    child: ProgressRing(),
                  );
                }
                final names = licenses.keys.toList()..sort();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final name in names)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Expander(
                          header: Text(name),
                          content: SelectableText(licenses[name]!.join('\n\n')),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.settingsGeneralAboutClose),
        ),
      ],
    );
  }
}
