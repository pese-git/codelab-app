import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/platform/external_link_opener.dart';
import 'legal_documents.dart';
import 'legal_page_state.dart';
import 'legal_ports.dart';

/// Состояние и переходы страницы «Legal» (design.md change
/// `add-app-legal-page`, D7, D8, D10, D11).
///
/// Почему Cubit: есть асинхронные данные (ресурсы и реестр лицензий), сбои с
/// журналом, вкладка, которую задают снаружи, и смена языка во время
/// загрузки; такие переходы проверяются отдельно от виджетов (AGENTS.md §8,
/// §12).
///
/// Для чего: хранит вкладку, язык, запрос и кэш документов; читает ресурс при
/// первом показе вкладки, реестр лицензий собирает один раз. Запрос поиска,
/// пути ресурсов, адреса и тексты исключений в журнал не пишутся (D11).
///
/// Как использовать: страница создаёт Cubit на каждое открытие и сразу
/// вызывает [open]; смену языка интерфейса передаёт [setLanguage]. Закрытие
/// отбрасывает поздние результаты (`isClosed`), состояние не переживает
/// страницу.
final class LegalPageCubit extends Cubit<LegalPageState> {
  LegalPageCubit({required LegalPorts ports})
    : _ports = ports,
      super(const LegalPageState());

  final LegalPorts _ports;

  /// Открывает страницу на вкладке [initial] (по умолчанию «Privacy policy»)
  /// на языке [languageCode]; завершается, когда прочитан документ вкладки.
  /// Сбор реестра лицензий не ожидается: поле поиска доступно сразу.
  Future<void> open(LegalTab? initial, String languageCode) {
    final tab = initial ?? LegalTab.privacyPolicy;
    emit(state.copyWith(tab: tab, languageCode: languageCode, clearNote: true));
    _logTab(tab, 'open');
    return _show(tab);
  }

  /// Переключает вкладку; та же вкладка — ничего не меняет.
  Future<void> selectTab(LegalTab tab, {String source = 'tab'}) {
    if (tab == state.tab) {
      return Future.value();
    }
    emit(state.copyWith(tab: tab, clearNote: true));
    _logTab(tab, source);
    return _show(tab);
  }

  /// Язык интерфейса сменился: вкладка и запрос остаются, показывается
  /// редакция нового языка.
  Future<void> setLanguage(String languageCode) {
    if (languageCode == state.languageCode) {
      return Future.value();
    }
    emit(state.copyWith(languageCode: languageCode));
    return _loadDocument(state.tab, state.shownAsset);
  }

  /// Запрос поиска; поиск синхронный (D7), в журнал не пишется (D11).
  void setQuery(String query) {
    if (query != state.query) {
      emit(state.copyWith(query: query));
    }
  }

  void clearQuery() => setQuery('');

  /// Ссылка внутри документа: вкладка, внешний адрес или ничего (D8).
  Future<void> onDocumentLink(Uri uri) async {
    switch (legalLinkOf(uri)) {
      case LegalLinkNone():
        return;
      case LegalLinkTab(:final tab):
        // Переход на вкладку всегда удаётся: исход фиксирован (D11).
        _ports.logger?.info(
          'legal.link_opened',
          context: {'target': 'tab', 'outcome': 'opened'},
        );
        await selectTab(tab, source: 'link');
      case LegalLinkExternal(:final uri):
        final outcome = await _ports.externalLinks.open(uri);
        if (isClosed) {
          return;
        }
        // Адрес в журнал не идёт: только исход в `snake_case` (D11).
        _ports.logger?.info(
          'legal.link_opened',
          context: {
            'target': 'external',
            'outcome': switch (outcome) {
              ExternalLinkOutcome.opened => 'opened',
              ExternalLinkOutcome.failed => 'failed',
              ExternalLinkOutcome.rejectedScheme => 'rejected_scheme',
            },
          },
        );
        emit(
          outcome == ExternalLinkOutcome.opened
              ? state.copyWith(clearNote: true)
              : state.copyWith(note: LegalNote.linkFailed),
        );
    }
  }

  Future<void> _show(LegalTab tab) {
    // Реестр стартует первым и не ожидается: завершение `open` не должно
    // зависеть от длинного обхода `LicenseRegistry`.
    if (tab == LegalTab.thirdPartyNotices) {
      unawaited(_ensurePackages());
    }
    return _loadDocument(tab, state.shownAsset);
  }

  void _logTab(LegalTab tab, String source) => _ports.logger?.debug(
    'legal.tab_selected',
    context: {'tab': tab.logName, 'source': source},
  );

  void _putDocument(String asset, DocumentLoad load) {
    if (!isClosed) {
      emit(state.copyWith(documents: {...state.documents, asset: load}));
    }
  }

  Future<void> _loadDocument(LegalTab tab, String asset) async {
    if (state.documents.containsKey(asset)) {
      return;
    }
    _putDocument(asset, const DocumentLoading());
    try {
      final text = await _ports.readAsset(asset);
      _putDocument(asset, DocumentLoaded(text));
    } on Object catch (error) {
      if (isClosed) {
        return;
      }
      // Только имя типа: текст исключения может содержать путь (D11).
      _ports.logger?.warning(
        'legal.document_load_failed',
        context: {
          'tab': tab.logName,
          'error_type': error.runtimeType.toString(),
        },
      );
      _putDocument(asset, const DocumentFailed());
    }
  }

  Future<void> _ensurePackages() async {
    if (state.packages is! PackagesNotRequested) {
      return;
    }
    emit(state.copyWith(packages: const PackagesCollecting()));
    PackagesCollected collected;
    try {
      final result = await _ports.packageLicenses();
      collected = PackagesCollected(result.packages, failed: result.failed);
    } on Object {
      // Порт не бросает по контракту; защита не даёт потерять ошибку
      // fire-and-forget (AGENTS.md §12).
      collected = const PackagesCollected([], failed: true);
    }
    if (isClosed) {
      return;
    }
    emit(state.copyWith(packages: collected));
    _ports.logger?.info(
      'legal.licenses_collected',
      context: {'packages': collected.list.length, 'failed': collected.failed},
    );
  }
}
