import 'dart:async';
import 'dart:typed_data';

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/app_scope.dart';
import '../../../app/build_version.dart';
import '../../../app/language/app_language_cubit.dart';
import '../../../app/navigation/app_destination.dart';
import '../../../app/navigation/navigation_cubit.dart';
import '../../../l10n/l10n.dart';
import '../application/legal_documents.dart';
import '../application/legal_page_cubit.dart';
import '../application/legal_page_state.dart';
import '../application/package_license_search.dart';
import '../application/third_party_notices.dart';

/// Тело страницы «Legal» для таблицы `settingsPageBuilders` (design.md change
/// `add-app-legal-page`, D1, D6, D7).
///
/// Почему отдельный хозяин: `LegalPageCubit` создаётся на каждое открытие
/// страницы и закрывается вместе с ней, поэтому вкладка и запрос поиска не
/// переживают страницу (spec app-settings «Страница «Legal»: видимость и
/// вкладки»). Порты приходят из `CodeLabDependencies.legalPorts`, виджет их не
/// собирает (AGENTS.md §6).
///
/// Как использовать: вкладку при открытии задаёт `SettingsDestination.legalTab`
/// (`null` — «Privacy policy»), язык — `AppLanguageCubit`; смена языка при
/// открытой странице уходит в `LegalPageCubit.setLanguage`.
Widget buildLegalPage(BuildContext context) => const LegalPageHost();

/// Хозяин `LegalPageCubit`: создаёт, открывает, закрывает и передаёт смену
/// языка.
///
/// Почему `State`, а не `BlocProvider(create:)`: порты берутся из
/// `CodeLabDependencies` (зависимость от `InheritedWidget`), а её нельзя
/// читать в `create`; образец — `GeneralPageHost`.
class LegalPageHost extends StatefulWidget {
  const LegalPageHost({super.key});

  @override
  State<LegalPageHost> createState() => _LegalPageHostState();
}

class _LegalPageHostState extends State<LegalPageHost> {
  LegalPageCubit? _cubit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cubit != null) {
      return;
    }
    final destination = context.read<NavigationCubit>().state;
    final cubit = LegalPageCubit(
      ports: codeLabDependenciesOf(context).legalPorts,
    );
    _cubit = cubit;
    // Ошибки чтения Cubit превращает в состояние сам, поэтому результат
    // `open` не ждём: страница рисует `Loading`.
    unawaited(
      cubit.open(
        destination is SettingsDestination ? destination.legalTab : null,
        context.read<AppLanguageCubit>().state.locale.languageCode,
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_cubit?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = _cubit!;
    return BlocProvider<LegalPageCubit>.value(
      value: cubit,
      child: BlocListener<AppLanguageCubit, AppLanguageState>(
        listenWhen: (a, b) => a.locale.languageCode != b.locale.languageCode,
        listener: (context, state) =>
            unawaited(cubit.setLanguage(state.locale.languageCode)),
        child: const LegalPage(),
      ),
    );
  }
}

/// Страница настроек «Legal»: четыре вкладки правовых документов сборки
/// (артборды «Legal», «Terms», «License», «Notices»; отступления — D12).
///
/// Почему только отображение: что выбрано, что загружено и что найдено,
/// решает `LegalPageCubit`; что делать со ссылкой, решает политика
/// `legalLinkOf` (D8). Принятия условий нет: ни флажков, ни записи о согласии
/// (D-29, §12.7.7а). Кнопок «Copy link», «Open on the web», «Copy all»,
/// «Open LICENSE» и оглавления «On this page» нет: у них нет поведения в этой
/// сборке (SETUP-17, D12).
///
/// Как использовать: строится [LegalPageHost] под `BlocProvider<LegalPageCubit>`.
class LegalPage extends StatelessWidget {
  const LegalPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<LegalPageCubit, LegalPageState>(
      builder: (context, state) {
        final cubit = context.read<LegalPageCubit>();
        return Column(
          key: const ValueKey('settings-legal'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CodeLabText(
              l10n.settingsPageLegalTitle,
              role: CodeLabTextRole.title,
            ),
            const SizedBox(height: 12),
            CodeLabSelectorBar<LegalTab>(
              semanticLabel: l10n.settingsLegalTabsLabel,
              value: state.tab,
              onChanged: (tab) => unawaited(cubit.selectTab(tab)),
              items: [
                for (final tab in LegalTab.values)
                  CodeLabSelectorItem<LegalTab>(
                    value: tab,
                    label: _tabLabel(l10n, tab),
                    key: ValueKey('settings-legal-tab-${tab.slug}'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            KeyedSubtree(
              key: const ValueKey('settings-legal-source'),
              child: CodeLabText(
                l10n.settingsLegalSource(
                  codelabDesktopVersion,
                  state.shownAsset,
                ),
                role: CodeLabTextRole.caption,
                color: FluentTheme.of(context).resources.textFillColorSecondary,
              ),
            ),
            const SizedBox(height: 12),
            if (state.note == LegalNote.linkFailed) ...[
              InfoBar(
                key: const ValueKey('settings-legal-link-failed'),
                title: Text(l10n.settingsLegalLinkFailed),
                severity: InfoBarSeverity.warning,
              ),
              const SizedBox(height: 12),
            ],
            switch (state.tab) {
              LegalTab.privacyPolicy || LegalTab.termsOfUse => _MarkdownBody(
                state: state,
                id: 'legal-${state.tab.slug}-${state.languageCode}',
                text: (t) => t,
              ),
              LegalTab.license => _LicenseBody(state: state),
              LegalTab.thirdPartyNotices => _NoticesBody(state: state),
            },
          ],
        );
      },
    );
  }

  static String _tabLabel(AppLocalizations l10n, LegalTab tab) => switch (tab) {
    LegalTab.privacyPolicy => l10n.settingsLegalTabPrivacy,
    LegalTab.termsOfUse => l10n.settingsLegalTabTerms,
    LegalTab.license => l10n.settingsLegalTabLicense,
    LegalTab.thirdPartyNotices => l10n.settingsLegalTabNotices,
  };
}

/// Политика ссылок документов (D8): решение принимает `legalLinkOf`, виджет
/// получает только ответ. Изображения не загружаются: в правовых текстах их
/// нет, а загрузка нарушила бы «офлайн».
class _LinkScope extends StatelessWidget {
  const _LinkScope({required this.child});

  final Widget child;

  static bool _canOpen(Uri uri) => legalLinkOf(uri) is! LegalLinkNone;
  static bool _never(Uri uri) => false;
  static ImageProvider _noImage(Uri uri) => MemoryImage(Uint8List(0));
  static void _ignoreKey(String key) {}
  static void _ignoreFailure(String key, Object error) {}

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<LegalPageCubit>();
    return CodeLabMarkdownScope(
      canOpenLink: _canOpen,
      onOpenLink: (uri) => unawaited(cubit.onDocumentLink(uri)),
      canLoadImage: _never,
      imageFor: _noImage,
      shownImages: const {},
      onShowImage: _ignoreKey,
      onImageFailed: _ignoreFailure,
      child: child,
    );
  }
}

/// Документ показанного ресурса: загрузка, сбой или markdown.
class _MarkdownBody extends StatelessWidget {
  const _MarkdownBody({
    required this.state,
    required this.id,
    required this.text,
  });

  final LegalPageState state;
  final String id;

  /// Выбор показываемой части текста (записи реестра, документ целиком).
  final String Function(String) text;

  @override
  Widget build(BuildContext context) => _DocumentView(
    load: state.documents[state.shownAsset],
    loaded: (raw) => _LinkScope(
      child: CodeLabMarkdown(id: id, text: text(raw)),
    ),
  );
}

/// Состояние загрузки ресурса: индикатор, InfoBar сбоя без пути или готовое.
class _DocumentView extends StatelessWidget {
  const _DocumentView({required this.load, required this.loaded});

  final DocumentLoad? load;
  final Widget Function(String text) loaded;

  @override
  Widget build(BuildContext context) => switch (load) {
    DocumentLoaded(:final text) => loaded(text),
    DocumentFailed() => InfoBar(
      key: const ValueKey('settings-legal-load-failed'),
      // Путь и текст исключения не показываются: причина — в журнале (D11).
      title: Text(context.l10n.settingsLegalLoadFailed),
      severity: InfoBarSeverity.warning,
    ),
    _ => const Align(alignment: Alignment.centerLeft, child: ProgressRing()),
  };
}

/// Вкладка «License»: краткое содержание MIT, абзац о сторонних компонентах и
/// полный текст `LICENSE` как есть.
class _LicenseBody extends StatelessWidget {
  const _LicenseBody({required this.state});

  final LegalPageState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<LegalPageCubit>();
    final secondary = FluentTheme.of(context).resources.textFillColorSecondary;
    // Название вкладки подставляется в абзац как ссылка: ARB даёт фразу целиком,
    // маркер разрезает её на текст до и после (перевод может менять порядок).
    // U+E000 — символ области частного использования: он не встречается в
    // переводах, поэтому не спутается с текстом абзаца, и его не видно, если
    // маркер вдруг попадёт на экран.
    const marker = '\uE000';
    final parts = l10n.settingsLegalComponentsText(marker).split(marker);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: const ValueKey('settings-legal-license-summary'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CodeLabKeyValueList(
                entries: [
                  CodeLabKeyValueEntry(
                    label: l10n.settingsLegalLicenseAllowed,
                    value: l10n.settingsLegalLicenseAllowedValue,
                  ),
                  CodeLabKeyValueEntry(
                    label: l10n.settingsLegalLicenseCondition,
                    value: l10n.settingsLegalLicenseConditionValue,
                  ),
                  CodeLabKeyValueEntry(
                    label: l10n.settingsLegalLicenseNoWarranty,
                    value: l10n.settingsLegalLicenseNoWarrantyValue,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              CodeLabText(
                l10n.settingsLegalLicenseSummaryNote,
                role: CodeLabTextRole.caption,
                color: secondary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        CodeLabText(
          l10n.settingsLegalComponentsTitle,
          role: CodeLabTextRole.strong,
        ),
        const SizedBox(height: 4),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (parts.first.isNotEmpty) CodeLabText(parts.first),
            HyperlinkButton(
              key: const ValueKey('settings-legal-license-notices-link'),
              onPressed: () =>
                  unawaited(cubit.selectTab(LegalTab.thirdPartyNotices)),
              child: Text(l10n.settingsLegalTabNotices),
            ),
            if (parts.length > 1 && parts.last.isNotEmpty)
              CodeLabText(parts.last),
          ],
        ),
        const SizedBox(height: 16),
        _DocumentView(
          load: state.documents[state.shownAsset],
          // Полный текст не переводится и не правится: моноширинно, с
          // выделением.
          loaded: (text) => KeyedSubtree(
            key: const ValueKey('settings-legal-license-text'),
            child: CodeLabMonospaceBlock(text),
          ),
        ),
      ],
    );
  }
}

/// Вкладка «Third-party notices»: записи реестра и лицензии пакетов с поиском
/// (D5, D6, D10).
class _NoticesBody extends StatelessWidget {
  const _NoticesBody({required this.state});

  final LegalPageState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final secondary = FluentTheme.of(context).resources.textFillColorSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CodeLabText(
          l10n.settingsLegalNoticesRegister,
          role: CodeLabTextRole.strong,
        ),
        const SizedBox(height: 4),
        // Записи видны при любом запросе и при сбое реестра лицензий: они не
        // зависят ни от поиска, ни от потока `LicenseRegistry` (D10).
        // Подпись внутри блока: spec называет её частью `…-notices-records`.
        KeyedSubtree(
          key: const ValueKey('settings-legal-notices-records'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CodeLabText(
                l10n.settingsLegalNoticesCaption,
                role: CodeLabTextRole.caption,
                color: secondary,
              ),
              const SizedBox(height: 8),
              _MarkdownBody(
                state: state,
                id: 'legal-notices-records',
                text: thirdPartyRecordsOf,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        CodeLabText(
          l10n.settingsLegalPackageLicenses,
          role: CodeLabTextRole.strong,
        ),
        const SizedBox(height: 8),
        InfoBar(
          key: const ValueKey('settings-legal-packages-info'),
          title: Text(l10n.settingsLegalPackagesInfo),
          severity: InfoBarSeverity.info,
        ),
        const SizedBox(height: 8),
        _PackageSearchField(query: state.query),
        const SizedBox(height: 8),
        _Packages(state: state),
      ],
    );
  }
}

/// Поле поиска пакетов: `TextEditingController` — механизм ввода, источник
/// истины — запрос в `LegalPageCubit` (D6).
class _PackageSearchField extends StatefulWidget {
  const _PackageSearchField({required this.query});

  final String query;

  @override
  State<_PackageSearchField> createState() => _PackageSearchFieldState();
}

class _PackageSearchFieldState extends State<_PackageSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query,
  );

  @override
  void didUpdateWidget(_PackageSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Очистка кнопкой меняет запрос в Cubit, а не в поле.
    if (_controller.text != widget.query) {
      _controller.text = widget.query;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<LegalPageCubit>();
    return Semantics(
      label: l10n.settingsLegalSearchLabel,
      textField: true,
      child: TextBox(
        key: const ValueKey('settings-legal-packages-search'),
        controller: _controller,
        placeholder: l10n.settingsLegalSearchHint,
        prefix: const Padding(
          padding: EdgeInsetsDirectional.only(start: 8),
          child: Icon(FluentIcons.search, size: 14),
        ),
        suffix: widget.query.trim().isEmpty
            ? null
            : Semantics(
                label: l10n.settingsLegalClearSearch,
                button: true,
                child: IconButton(
                  key: const ValueKey('settings-legal-packages-clear'),
                  icon: const Icon(FluentIcons.chrome_close, size: 12),
                  onPressed: cubit.clearQuery,
                ),
              ),
        onChanged: cubit.setQuery,
      ),
    );
  }
}

/// Счётчик и список пакетов, индикатор сбора или пустой блок.
class _Packages extends StatelessWidget {
  const _Packages({required this.state});

  final LegalPageState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final secondary = FluentTheme.of(context).resources.textFillColorSecondary;
    final packages = state.packages;
    if (packages is! PackagesCollected) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: ProgressRing(key: ValueKey('settings-legal-packages-loading')),
      );
    }
    final search = state.search;
    final filtered = search.needle.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: const ValueKey('settings-legal-packages-count'),
          child: CodeLabText(
            filtered
                ? l10n.settingsLegalPackagesMatched(
                    search.hits.length,
                    search.total,
                  )
                : l10n.settingsLegalPackagesCount(search.total),
            role: CodeLabTextRole.caption,
            color: secondary,
          ),
        ),
        const SizedBox(height: 8),
        if (search.hits.isEmpty && filtered)
          _EmptyPackages(query: state.query)
        else
          for (final hit in search.hits)
            // Ключ на внешнем элементе списка: при сдвиге пакета фильтром
            // состояние `Expander` (развёрнут ли) переезжает вместе с ним.
            Padding(
              key: ValueKey('settings-legal-package-${hit.package.name}'),
              padding: const EdgeInsets.only(bottom: 4),
              child: _PackageRow(hit: hit),
            ),
      ],
    );
  }
}

/// Пустой блок: запрос показывается экранированным (недоверенный ввод,
/// `escapeForDisplay`, D6).
class _EmptyPackages extends StatelessWidget {
  const _EmptyPackages({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<LegalPageCubit>();
    return Column(
      key: const ValueKey('settings-legal-packages-empty'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CodeLabText(l10n.settingsLegalEmptyTitle, role: CodeLabTextRole.strong),
        const SizedBox(height: 4),
        CodeLabText(
          l10n.settingsLegalEmptyText(escapeForDisplay(query.trim())),
        ),
        const SizedBox(height: 8),
        Button(
          key: const ValueKey('settings-legal-packages-empty-clear'),
          onPressed: cubit.clearQuery,
          child: Text(l10n.settingsLegalClearSearch),
        ),
      ],
    );
  }
}

/// Пакет: свёрнутый `Expander` с именем (подсветка совпадений) и числом
/// лицензий; развёрнутый — тексты лицензий как есть.
///
/// Почему содержимое строится только после раскрытия: пакетов сотни, а тексты
/// лицензий длинные; свёрнутая строка не должна держать их в дереве.
class _PackageRow extends StatefulWidget {
  const _PackageRow({required this.hit});

  final PackageHit hit;

  @override
  State<_PackageRow> createState() => _PackageRowState();
}

class _PackageRowState extends State<_PackageRow> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = FluentTheme.of(context);
    final package = widget.hit.package;
    // Ключ строки стоит на внешнем элементе списка (`_Packages`), а не здесь:
    // Fluent прокидывает ключ `Expander` вложенному виджету.
    return Expander(
      onStateChanged: (open) => setState(() => _open = open),
      header: Row(
        children: [
          Expanded(
            // Подпись для чтения с экрана — целое имя, а не куски подсветки.
            child: Semantics(
              // Свой узел: иначе имя слилось бы с числом лицензий в одну
              // подпись заголовка.
              container: true,
              label: package.name,
              excludeSemantics: true,
              child: Text.rich(
                _nameSpan(package.name, widget.hit.ranges, theme),
              ),
            ),
          ),
          const SizedBox(width: 12),
          CodeLabText(
            l10n.settingsLegalLicensesCount(package.licenses.length),
            role: CodeLabTextRole.caption,
            color: theme.resources.textFillColorSecondary,
          ),
        ],
      ),
      content: !_open
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < package.licenses.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  SelectableText(package.licenses[i]),
                ],
              ],
            ),
    );
  }

  /// Имя пакета с полужирными диапазонами совпадений на фоне выделения темы.
  static TextSpan _nameSpan(
    String name,
    List<(int, int)> ranges,
    FluentThemeData theme,
  ) {
    if (ranges.isEmpty) {
      return TextSpan(text: name);
    }
    final highlight = TextStyle(
      fontWeight: FontWeight.w700,
      backgroundColor: theme.accentColor
          .defaultBrushFor(theme.brightness)
          .withValues(alpha: 0.25),
    );
    final spans = <TextSpan>[];
    var at = 0;
    for (final (start, end) in ranges) {
      if (start > at) {
        spans.add(TextSpan(text: name.substring(at, start)));
      }
      spans.add(TextSpan(text: name.substring(start, end), style: highlight));
      at = end;
    }
    if (at < name.length) {
      spans.add(TextSpan(text: name.substring(at)));
    }
    return TextSpan(children: spans);
  }
}
