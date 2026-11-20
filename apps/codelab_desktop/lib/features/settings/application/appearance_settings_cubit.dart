import 'dart:async';
import 'dart:ui' show Brightness;

import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:fluent_ui/fluent_ui.dart' show FluentThemeData;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../app/appearance/app_appearance_cubit.dart';
import '../../../app/appearance/built_in_themes.dart';
import '../../../app/appearance/fluent_theme_builder.dart';
import '../../../core/platform/app_appearance_preferences.dart'
    show AppearanceMode;
import '../../../core/platform/local_folder_opener.dart';
import '../../../core/platform/theme_file_picker.dart';
import 'contrast_checks.dart';

/// Префикс идентификатора карточки пользовательской темы (design.md change
/// `add-app-appearance-page`, D9а): файл `dark.json` в каталоге не должен
/// совпасть с встроенной темой `dark`, поэтому пространства имён разведены.
const customThemeIdPrefix = 'custom-';

/// Идентификатор карточки пользовательской темы по имени файла.
String customThemeId(String name) => '$customThemeIdPrefix$name';

/// Вид темы на карточке (`Built-in · default`, `Built-in`, `Custom · extends`).
enum AppearanceThemeKind { builtInDefault, builtIn, custom }

/// Карточка темы страницы «Appearance» (design.md change
/// `add-app-appearance-page`, D13, D14).
///
/// Почему данные, а не виджет: страница только рисует; разбор, контраст и
/// подсчёт предупреждений делает Cubit, потому что бейдж `N warnings`
/// учитывает и предупреждения разбора, и роли с низким контрастом.
///
/// Для чего: [theme] — готовая `FluentThemeData` для мини-превью и блока
/// «Preview» (`null` у темы, которая не загрузилась); [mode] — режим темы
/// (`null` у не загрузившейся); [extendsBase] — `extends` пользовательской
/// темы; [contrast] — проверки на фоне кода; [parseWarnings] — число
/// предупреждений разбора.
final class AppearanceThemeCard {
  const AppearanceThemeCard({
    required this.id,
    required this.kind,
    required this.loaded,
    this.mode,
    this.extendsBase,
    this.theme,
    this.contrast = const [],
    this.parseWarnings = 0,
  });

  final String id;
  final AppearanceThemeKind kind;
  final bool loaded;
  final Brightness? mode;
  final String? extendsBase;
  final FluentThemeData? theme;
  final List<ContrastCheck> contrast;
  final int parseWarnings;

  /// Имя темы как в документе оформления и в файле (`acme-night`); у встроенной
  /// совпадает с [id], у пользовательской — [id] без префикса `custom-`.
  String get name => kind == AppearanceThemeKind.custom
      ? id.substring(customThemeIdPrefix.length)
      : id;

  /// Роли ниже порога 4,5:1: они применяются как заданы, но дают предупреждение.
  int get lowContrast => contrast.where((c) => !c.passes).length;

  /// Число в бейдже `N warnings`: предупреждения разбора и низкий контраст.
  int get warningCount => parseWarnings + lowContrast;
}

/// Проблема выбранной темы: строка списка `settings-appearance-issue-<n>`.
sealed class AppearanceIssue {
  const AppearanceIssue();
}

/// Предупреждение разбора файла (код, позиция, ключ, подсказка — без текста).
final class AppearanceParseIssue extends AppearanceIssue {
  const AppearanceParseIssue(this.issue);

  final ThemeIssue issue;
}

/// Роль ниже порога контраста: `Low contrast` в списке и на карточке.
final class AppearanceLowContrastIssue extends AppearanceIssue {
  const AppearanceLowContrastIssue(this.role, this.ratio);

  final ThemeRole role;
  final double ratio;
}

/// Данные панели проблем и просмотра выбранной темы.
///
/// [fileText] — текст файла (до 64 КиБ, `null`, если файл не прочитан или тема
/// встроенная); [issues] — по порядку позиции; [unsetRoles] — справка о
/// незаданных ролях без `status_bg` и `approval_border`, которые app не
/// применяет (Q8); [error] — ошибка разбора, [readError] — ошибка чтения
/// файла: тогда тема не загрузилась и справки о ролях нет.
final class AppearanceSelection {
  const AppearanceSelection({
    required this.card,
    this.fileText,
    this.issues = const [],
    this.unsetRoles = const [],
    this.error,
    this.readError,
  });

  final AppearanceThemeCard card;
  final String? fileText;
  final List<AppearanceIssue> issues;
  final List<ThemeRole> unsetRoles;
  final ThemeIssue? error;
  final ThemeReadError? readError;

  /// Строки файла с предупреждением разбора (с 1) для `CodeLabFilePreview`.
  Set<int> get warningLines => {
    for (final issue in issues)
      if (issue is AppearanceParseIssue && issue.issue.line > 0)
        issue.issue.line,
  };
}

/// Исход импорта на странице: идёт ли он и что нужно показать.
enum AppearanceImportStatus { idle, importing, needsReplace, failed }

/// Состояние «Import JSON…» (spec app-settings «Импорт темы на странице»).
///
/// [name] — имя темы из файла (для диалога замены); [fileName] — имя
/// выбранного файла; [issue] — ошибка разбора с позицией (`failed`);
/// [writeFailed] — ошибка записи без текста исключения.
final class AppearanceImport {
  const AppearanceImport({
    this.status = AppearanceImportStatus.idle,
    this.name,
    this.fileName,
    this.issue,
    this.writeFailed = false,
    this.pickerFailed = false,
    this.sourceChanged = false,
  });

  final AppearanceImportStatus status;
  final String? name;
  final String? fileName;
  final ThemeIssue? issue;
  final bool writeFailed;

  /// Системный диалог выбора файла сбойнул (исключение порта): записи не было.
  final bool pickerFailed;

  /// Файл изменился между «нужна замена» и «Replace»: другая тема, замена не
  /// выполнена.
  final bool sourceChanged;
}

/// Состояние страницы «Appearance» (D13).
///
/// [loading] — каталог читается: карточки встроенных тем работают, на месте
/// пользовательских — индикатор; [cards] — встроенные, затем пользовательские в
/// порядке каталога; [selectedId] и [selection] — тема для превью и панели
/// проблем (по умолчанию действующая); [folder] — исход последнего «Open
/// folder».
final class AppearanceSettingsState {
  const AppearanceSettingsState({
    this.loading = true,
    this.cards = const [],
    this.selectedId,
    this.selection,
    this.import = const AppearanceImport(),
    this.folder,
    this.themesLabel,
    this.themesDirectoryLabel,
    this.catalogFailed = false,
  });

  final bool loading;
  final List<AppearanceThemeCard> cards;
  final String? selectedId;
  final AppearanceSelection? selection;
  final AppearanceImport import;
  final FolderOpenOutcome? folder;

  /// Путь каталога тем для показа: `~/.codelab/themes/*.json` (домашний
  /// каталог сокращён до `~`); `null` — каталог недоступен. Строит composition
  /// root: страница не знает окружения и `dart:io`.
  final String? themesLabel;

  /// Каталог тем для сообщений: `~/.codelab/themes` (с `~`, без маски).
  final String? themesDirectoryLabel;

  /// Порт каталога бросил исключение при чтении: встроенные темы работают,
  /// пользовательские не показаны, страница предлагает «Reload».
  final bool catalogFailed;

  AppearanceSettingsState copyWith({
    bool? loading,
    List<AppearanceThemeCard>? cards,
    String? selectedId,
    AppearanceSelection? selection,
    AppearanceImport? import,
    FolderOpenOutcome? folder,
    String? themesLabel,
    String? themesDirectoryLabel,
    bool? catalogFailed,
  }) => AppearanceSettingsState(
    loading: loading ?? this.loading,
    cards: cards ?? this.cards,
    selectedId: selectedId ?? this.selectedId,
    selection: selection ?? this.selection,
    import: import ?? this.import,
    folder: folder ?? this.folder,
    themesLabel: themesLabel ?? this.themesLabel,
    themesDirectoryLabel: themesDirectoryLabel ?? this.themesDirectoryLabel,
    catalogFailed: catalogFailed ?? this.catalogFailed,
  );
}

/// Cubit страницы «Appearance»: каталог тем, выбор для превью, импорт, «Open
/// folder» (D9, D11, D13).
///
/// Почему отдельно от [AppAppearanceCubit]: тот владеет ПРИМЕНЁННЫМ
/// оформлением на весь процесс, а этот — временным состоянием страницы
/// (выбранная карточка, чтение каталога, диалог замены); его создаёт
/// composition root на открытие страницы (`createAppearanceSettingsCubit`),
/// закрывает страница.
///
/// Для чего: выбор карточки НЕ применяет тему; применение — [useSelected] и
/// [resetSelected], которые вызывают [AppAppearanceCubit]. Чтение каталога
/// несёт номер: результат после нового [reload] или `close()` отбрасывается с
/// событием `appearance.catalog_discarded`. Импорт блокирует повторный до
/// завершения. Файл темы приложение не открывает — [openFolder] открывает
/// каталог через `LocalFolderOpener` (D11).
///
/// Как использовать: после создания страница зовёт [load]; нажатия страницы —
/// методы Cubit. Класс не `final`: тесты страницы подставляют наследника.
/// События журнала — spec app-settings «События журнала оформления»: имён
/// тем, путей и текстов исключений в них нет (D12).
class AppearanceSettingsCubit extends Cubit<AppearanceSettingsState> {
  AppearanceSettingsCubit({
    required ThemeLibrary library,
    required AppAppearanceCubit appearance,
    required ThemeFilePicker picker,
    required LocalFolderOpener folderOpener,
    required Brightness Function() systemBrightness,
    String? themesDirectory,
    String? themesLabel,
    String? themesDirectoryLabel,
    Logger? logger,
  }) : _library = library,
       _appearance = appearance,
       _picker = picker,
       _folderOpener = folderOpener,
       _systemBrightness = systemBrightness,
       _themesDirectory = themesDirectory,
       _logger = logger,
       super(
         AppearanceSettingsState(
           cards: [for (final id in kBuiltInThemeIds) _builtInCard(id)],
           themesLabel: themesLabel,
           themesDirectoryLabel: themesDirectoryLabel,
         ),
       );

  final ThemeLibrary _library;
  final AppAppearanceCubit _appearance;
  final ThemeFilePicker _picker;
  final LocalFolderOpener _folderOpener;
  final Brightness Function() _systemBrightness;
  final String? _themesDirectory;
  final Logger? _logger;

  /// Номер последнего чтения каталога: результат с меньшим номером отброшен.
  int _catalogToken = 0;

  /// Записи каталога по имени: текст и ошибка нужны панели проблем выбранной
  /// темы.
  Map<String, ThemeEntry> _entries = const {};

  /// Файл, выбранный в диалоге и ждущий «Replace».
  String? _pendingSource;

  /// Идёт импорт: повторный «Import JSON…» недоступен (spec).
  bool _importing = false;

  static AppearanceThemeCard _builtInCard(String id) {
    final file = builtInThemeFile(id);
    final theme = buildFluentTheme(file);
    return AppearanceThemeCard(
      id: id,
      kind: id == 'high-contrast'
          ? AppearanceThemeKind.builtIn
          : AppearanceThemeKind.builtInDefault,
      loaded: true,
      mode: id == 'light' ? Brightness.light : Brightness.dark,
      theme: theme,
      contrast: checkContrast(theme),
    );
  }

  /// Читает каталог и выбирает действующую тему для превью.
  Future<void> load() => _readCatalog(select: _activeId);

  /// «Reload»: перечитывает каталог; если выбранная тема назначена режиму,
  /// применяет её файл заново.
  Future<void> reload() async {
    final id = state.selectedId;
    await _readCatalog(select: id);
    if (isClosed || id == null || !id.startsWith(customThemeIdPrefix)) return;
    final name = id.substring(customThemeIdPrefix.length);
    final settings = _appearance.state;
    if (settings.lightTheme == name || settings.darkTheme == name) {
      await _appearance.reloadTheme(name);
    }
  }

  /// Режим, действующий сейчас: `Light`, `Dark` или режим системы при
  /// `Match system`.
  Brightness get _activeBrightness => switch (_appearance.state.mode) {
    AppearanceMode.light => Brightness.light,
    AppearanceMode.dark => Brightness.dark,
    AppearanceMode.system => _systemBrightness(),
  };

  /// Идентификатор карточки темы, действующей сейчас: тема режима `Light` или
  /// `Dark`, при `Match system` — режима системы.
  String get _activeId {
    final settings = _appearance.state;
    final name = _activeBrightness == Brightness.light
        ? settings.lightTheme
        : settings.darkTheme;
    return kBuiltInThemeIds.contains(name) ? name : customThemeId(name);
  }

  /// Встроенная тема по умолчанию действующего режима: выбор, когда
  /// действующая пользовательская тема не загрузилась (файл удалён).
  String get _activeDefaultId =>
      _activeBrightness == Brightness.light ? 'light' : 'dark';

  Future<void> _readCatalog({String? select}) async {
    final token = ++_catalogToken;
    List<ThemeEntry> entries;
    var failed = false;
    try {
      entries = await _library.list();
    } on Object catch (error) {
      // Сбой чтения каталога: встроенные темы остаются, страница показывает
      // InfoBar с «Reload»; в журнал — только класс ошибки, без пути.
      _logger?.warning(
        'appearance.catalog_failed',
        context: {
          'error_class': error.runtimeType.toString(),
          // Причина без пути: `notADirectory` или `unreadable`.
          if (error is ThemeCatalogException) 'failure': error.failure.name,
        },
      );
      entries = const [];
      failed = true;
    }
    if (isClosed) {
      _logger?.debug(
        'appearance.catalog_discarded',
        context: {'reason': 'closed'},
      );
      return;
    }
    if (token != _catalogToken) {
      _logger?.debug(
        'appearance.catalog_discarded',
        context: {'reason': 'reload'},
      );
      return;
    }
    _entries = {for (final entry in entries) customThemeId(entry.name): entry};
    final cards = [
      for (final id in kBuiltInThemeIds) _builtInCard(id),
      for (final entry in entries) _customCard(entry),
    ];
    // Выбор, сделанный пользователем, пока каталог читался, сохраняется.
    final wanted = state.selectedId ?? select;
    final id = cards.any((c) => c.id == wanted)
        ? wanted!
        : (cards.any((c) => c.id == select) ? select! : _activeDefaultId);
    emit(
      AppearanceSettingsState(
        loading: false,
        cards: cards,
        selectedId: id,
        selection: _selectionFor(cards, id),
        import: state.import,
        folder: state.folder,
        themesLabel: state.themesLabel,
        themesDirectoryLabel: state.themesDirectoryLabel,
        catalogFailed: failed,
      ),
    );
  }

  AppearanceThemeCard _customCard(ThemeEntry entry) {
    final text = entry.text;
    if (text == null) {
      return AppearanceThemeCard(
        id: customThemeId(entry.name),
        kind: AppearanceThemeKind.custom,
        loaded: false,
      );
    }
    switch (ThemeFile.parse('${entry.name}.json', text)) {
      case ThemeRejected():
        return AppearanceThemeCard(
          id: customThemeId(entry.name),
          kind: AppearanceThemeKind.custom,
          loaded: false,
        );
      case ThemeLoaded loaded:
        final theme = buildFluentTheme(loaded.theme);
        return AppearanceThemeCard(
          id: customThemeId(entry.name),
          kind: AppearanceThemeKind.custom,
          loaded: true,
          mode: loaded.theme.base == ThemeBase.light
              ? Brightness.light
              : Brightness.dark,
          extendsBase: loaded.theme.base.jsonName,
          theme: theme,
          contrast: checkContrast(theme),
          parseWarnings: loaded.warnings.length,
        );
    }
  }

  AppearanceSelection _selectionFor(
    List<AppearanceThemeCard> cards,
    String id,
  ) {
    final card = cards.singleWhere((c) => c.id == id);
    final entry = _entries[id];
    if (card.kind != AppearanceThemeKind.custom || entry == null) {
      return AppearanceSelection(card: card);
    }
    final text = entry.text;
    if (text == null) {
      return AppearanceSelection(card: card, readError: entry.error);
    }
    switch (ThemeFile.parse('${card.name}.json', text)) {
      case ThemeRejected(:final issue):
        return AppearanceSelection(card: card, fileText: text, error: issue);
      case ThemeLoaded loaded:
        final warnings = [...loaded.warnings]
          ..sort((a, b) {
            final byLine = a.line.compareTo(b.line);
            return byLine != 0 ? byLine : a.column.compareTo(b.column);
          });
        return AppearanceSelection(
          card: card,
          fileText: text,
          issues: [
            for (final warning in warnings) AppearanceParseIssue(warning),
            for (final check in card.contrast)
              if (!check.passes)
                AppearanceLowContrastIssue(check.role, check.ratio),
          ],
          // Роли, которых app не применяет (Q8), в справку не входят.
          unsetRoles: [
            for (final role in loaded.unsetRoles)
              if (role != ThemeRole.statusBg &&
                  role != ThemeRole.approvalBorder)
                role,
          ],
        );
    }
  }

  /// Выбирает карточку для превью и панели проблем; тему НЕ применяет.
  Future<void> select(String id) async {
    if (isClosed || !state.cards.any((c) => c.id == id)) return;
    emit(
      state.copyWith(selectedId: id, selection: _selectionFor(state.cards, id)),
    );
  }

  /// «Import JSON…»: диалог, импорт, превью импортированной темы.
  Future<void> importJson() async {
    if (isClosed || _importing) return;
    _importing = true;
    emit(
      state.copyWith(
        import: const AppearanceImport(
          status: AppearanceImportStatus.importing,
        ),
      ),
    );
    try {
      final String? path;
      try {
        path = await _picker.pickThemeFile();
      } on Object catch (error) {
        _logImport('failed', errorClass: error.runtimeType.toString());
        _finishImport(
          const AppearanceImport(
            status: AppearanceImportStatus.failed,
            pickerFailed: true,
          ),
        );
        return;
      }
      if (isClosed) return;
      if (path == null) {
        _logImport('cancelled');
        _finishImport(const AppearanceImport());
        return;
      }
      await _import(path, replace: false);
    } finally {
      _importing = false;
    }
  }

  /// «Replace» в диалоге замены.
  Future<void> confirmReplace() async {
    final path = _pendingSource;
    if (isClosed ||
        _importing ||
        path == null ||
        state.import.status != AppearanceImportStatus.needsReplace) {
      return;
    }
    _importing = true;
    _pendingSource = null;
    // Подтверждение относится к теме, которую показывали в диалоге: если
    // источник успел измениться, порт откажет (`ThemeImportSourceChanged`).
    final expected = state.import.name;
    emit(
      state.copyWith(
        import: const AppearanceImport(
          status: AppearanceImportStatus.importing,
        ),
      ),
    );
    try {
      await _import(path, replace: true, expectedName: expected);
    } finally {
      _importing = false;
    }
  }

  /// «Cancel» в диалоге замены: файл не меняется.
  void cancelReplace() {
    if (isClosed) return;
    _pendingSource = null;
    _logImport('cancelled');
    emit(state.copyWith(import: const AppearanceImport()));
  }

  Future<void> _import(
    String path, {
    required bool replace,
    String? expectedName,
  }) async {
    final fileName = p.basename(path);
    final ThemeImportResult result;
    try {
      result = await _library.import(
        path,
        replace: replace,
        expectedName: expectedName,
      );
    } on Object catch (error) {
      if (isClosed) return;
      _logImport('failed', errorClass: error.runtimeType.toString());
      _finishImport(
        AppearanceImport(
          status: AppearanceImportStatus.failed,
          fileName: fileName,
          writeFailed: true,
        ),
      );
      return;
    }
    if (isClosed) return;
    switch (result) {
      case ThemeImportImported(:final name):
        _logImport('imported');
        await _afterImport(name);
      case ThemeImportReplaced(:final name):
        _logImport('replaced');
        await _afterImport(name);
      case ThemeImportUnchanged(:final name):
        _logImport('unchanged');
        _finishImport(const AppearanceImport());
        await _selectAfterImport(customThemeId(name));
      case ThemeImportNeedsReplace(:final name):
        _pendingSource = path;
        emit(
          state.copyWith(
            import: AppearanceImport(
              status: AppearanceImportStatus.needsReplace,
              name: name,
              fileName: fileName,
            ),
          ),
        );
      case ThemeImportInvalid(:final issue):
        _logImport('invalid');
        _finishImport(
          AppearanceImport(
            status: AppearanceImportStatus.failed,
            fileName: fileName,
            issue: issue,
          ),
        );
      case ThemeImportSourceChanged():
        // Файл изменился после показа диалога: замены не было, нужен новый выбор.
        _logImport('source_changed');
        _finishImport(
          AppearanceImport(
            status: AppearanceImportStatus.failed,
            fileName: fileName,
            sourceChanged: true,
          ),
        );
      case ThemeImportFailed():
        _logImport('failed');
        _finishImport(
          AppearanceImport(
            status: AppearanceImportStatus.failed,
            fileName: fileName,
            writeFailed: true,
          ),
        );
    }
  }

  /// После записи файла: каталог перечитывается, тема выбирается для превью и
  /// НЕ применяется.
  Future<void> _afterImport(String name) async {
    _finishImport(const AppearanceImport());
    await _readCatalog(select: customThemeId(name));
    await _selectAfterImport(customThemeId(name));
  }

  Future<void> _selectAfterImport(String id) async {
    if (isClosed) return;
    if (!state.cards.any((c) => c.id == id)) {
      await _readCatalog(select: id);
    }
    await select(id);
  }

  void _finishImport(AppearanceImport value) {
    if (!isClosed) emit(state.copyWith(import: value));
  }

  void _logImport(String outcome, {String? errorClass}) => _logger?.info(
    'appearance.theme_imported',
    context: {'outcome': outcome, 'error_class': ?errorClass},
  );

  /// «Open folder»: каталог тем через `LocalFolderOpener` (`create: true`);
  /// файл темы не открывается (D11).
  Future<void> openFolder() async {
    final directory = _themesDirectory;
    if (isClosed) return;
    if (directory == null) {
      emit(state.copyWith(folder: FolderOpenOutcome.failed));
      return;
    }
    final outcome = await _folderOpener.open(directory, create: true);
    if (!isClosed) emit(state.copyWith(folder: outcome));
  }

  /// «Use `<name>`»: назначает выбранную тему её режиму.
  Future<void> useSelected() async {
    final card = state.selection?.card;
    if (isClosed || card == null || !card.loaded) return;
    // Оформлению нужно имя темы, а не идентификатор карточки.
    await _appearance.useTheme(card.name);
  }

  /// «Reset»: возвращает режиму выбранной темы встроенную по умолчанию и
  /// выбирает её для превью.
  Future<void> resetSelected() async {
    final mode = state.selection?.card.mode;
    if (isClosed || mode == null) return;
    await _appearance.resetTheme(mode);
    await select(mode == Brightness.light ? 'light' : 'dark');
  }
}
