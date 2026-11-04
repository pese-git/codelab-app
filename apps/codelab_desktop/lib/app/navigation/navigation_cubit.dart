import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app_destination.dart';
import 'settings_page.dart';
import 'settings_page_store.dart';

/// Откуда пользователь открыл настройки; поле события `settings.opened`
/// (design.md change `add-app-settings-shell`, D17).
enum SettingsOpenSource { shortcut, sidebar, banner }

/// Переходы между рабочим местом и настройками codelab-app.
///
/// Почему: навигация — состояние приложения, на которое реагирует UI, а не
/// маршрут `Navigator` (`state-management.md`; `dart-agent-and-clients` §12.3
/// A13, DSK-24). Cubit не знает `BuildContext`; экран рисует
/// `CodeLabAppWidget` по его состоянию (design.md change
/// `add-app-settings-shell`, D1, D2).
///
/// Для чего: единственный владелец вопроса «какой экран открыт» и «какая
/// страница настроек выбрана». Рабочее место при уходе остаётся
/// смонтированным и Cubit-ы сессий не закрываются.
///
/// Как использовать: composition root создаёт один экземпляр. [openSettings]
/// открывает [page] или последнюю сохранённую видимую страницу, а при её
/// отсутствии, скрытой или неизвестной — «Connection» (если она не видна —
/// первую видимую); [back] возвращает на рабочее место.
/// [activeSessionId] даёт идентификатор активной сессии для `returnTo`;
/// [selectSessionIfOpen] активирует сессию и возвращает `false`, если она
/// уже не открыта. Сбой [store] даёт предупреждение без текста ошибки (в нём
/// может быть что угодно) и не мешает переходу.
class NavigationCubit extends Cubit<AppDestination> {
  NavigationCubit({
    required SettingsPageStore store,
    required SettingsPages pages,
    required String? Function() activeSessionId,
    required bool Function(String sessionId) selectSessionIfOpen,
    Logger? logger,
  }) : _store = store,
       _pages = pages,
       _activeSessionId = activeSessionId,
       _selectSessionIfOpen = selectSessionIfOpen,
       _logger = logger,
       super(const WorkbenchDestination());

  final SettingsPageStore _store;
  final SettingsPages _pages;
  final String? Function() _activeSessionId;
  final bool Function(String sessionId) _selectSessionIfOpen;
  final Logger? _logger;

  /// Номер попытки: растёт с каждым [openSettings] и [selectSettingsPage].
  /// Результат чтения `last_page`, пришедший после более новой попытки,
  /// отбрасывается (AGENTS.md §12, поздний результат; design.md D2).
  var _attempt = 0;

  /// Открывает настройки на [page] или на последней сохранённой странице.
  ///
  /// На экране настроек вызов ничего не делает: Cmd/Ctrl+, там не привязано
  /// и `returnTo` не меняется (D2). При пустом наборе страниц состояние не
  /// меняется — пустого экрана быть не должно (SETUP-17).
  Future<void> openSettings({
    SettingsPage? page,
    required SettingsOpenSource source,
  }) async {
    if (state is SettingsDestination) {
      return;
    }
    final visible = _pages.visible;
    if (visible.isEmpty) {
      _logger?.debug('settings.open_skipped');
      return;
    }
    final attempt = ++_attempt;
    // Сессию запоминаем до `await`: вызов — момент ухода пользователя.
    final returnTo = _activeSessionId();
    final target = page != null && _pages.isVisible(page)
        ? page
        : await _lastPage();
    if (isClosed || attempt != _attempt || state is SettingsDestination) {
      return;
    }
    emit(SettingsDestination(target, returnTo: returnTo));
    _logger?.info(
      'settings.opened',
      context: {'page': target.slug, 'source': source.name},
    );
    if (page != null) {
      await _savePage(target);
    }
  }

  /// Переключает страницу на экране настроек; скрытая или уже выбранная
  /// страница игнорируется.
  Future<void> selectSettingsPage(SettingsPage page) async {
    final current = state;
    if (current is! SettingsDestination ||
        current.page == page ||
        !_pages.isVisible(page)) {
      return;
    }
    _attempt++;
    emit(SettingsDestination(page, returnTo: current.returnTo));
    _logger?.debug('settings.page_selected', context: {'page': page.slug});
    await _savePage(page);
  }

  /// Возвращает на рабочее место (Esc, «Back» и кнопка InfoBar одобрения).
  ///
  /// Без [toSession] активируется сессия `returnTo`, если она ещё открыта;
  /// иначе остаётся текущая активная — другую `back` не подбирает (D2).
  /// [toSession] передаёт только InfoBar ожидающего одобрения: он
  /// перекрывает `returnTo` и активирует сессию с запросом.
  void back({String? toSession}) {
    final current = state;
    if (current is! SettingsDestination) {
      return;
    }
    final target = toSession ?? current.returnTo;
    if (target != null) {
      _selectSessionIfOpen(target);
    }
    emit(const WorkbenchDestination());
    if (toSession != null) {
      _logger?.info('settings.back_to_approval');
    }
    _logger?.debug('settings.closed', context: {'page': current.page.slug});
  }

  /// Пишет, что InfoBar одобрения появился; [sessions] — число сессий с
  /// запросом. Вызывает UI один раз при появлении, id запросов в журнал не
  /// идут (D17).
  void pendingApprovalShown({required int sessions}) => _logger?.info(
    'settings.pending_approval_shown',
    context: {'sessions': sessions},
  );

  /// Последняя сохранённая видимая страница, иначе «Connection», иначе первая
  /// видимая.
  Future<SettingsPage> _lastPage() async {
    SettingsPage? saved;
    try {
      saved = SettingsPage.fromSlug(await _store.load());
    } on Object catch (error) {
      // Без `error.toString()`: текст исключения не должен попасть в журнал
      // (design.md change `add-app-settings-shell`, D17).
      _logger?.warning(
        'settings.last_page_load_failed',
        context: {'error_type': error.runtimeType.toString()},
      );
    }
    if (saved != null && _pages.isVisible(saved)) {
      return saved;
    }
    return _pages.isVisible(SettingsPage.connection)
        ? SettingsPage.connection
        : _pages.visible.first;
  }

  Future<void> _savePage(SettingsPage page) async {
    try {
      await _store.save(page.slug);
    } on Object catch (error) {
      _logger?.warning(
        'settings.last_page_save_failed',
        context: {'error_type': error.runtimeType.toString()},
      );
    }
  }
}
