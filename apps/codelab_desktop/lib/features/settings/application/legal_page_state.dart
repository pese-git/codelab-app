import 'package:flutter/foundation.dart' show listEquals, mapEquals;

import 'legal_documents.dart';
import 'package_license_search.dart';

/// Загрузка ресурса документа (D7).
sealed class DocumentLoad {
  const DocumentLoad();
}

final class DocumentLoading extends DocumentLoad {
  const DocumentLoading();

  @override
  bool operator ==(Object other) => other is DocumentLoading;

  @override
  int get hashCode => 0;
}

final class DocumentLoaded extends DocumentLoad {
  const DocumentLoaded(this.text);

  final String text;

  @override
  bool operator ==(Object other) =>
      other is DocumentLoaded && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

/// Ресурс не прочитан; причина в журнале (`legal.document_load_failed`), не в
/// состоянии: текст исключения может содержать путь.
final class DocumentFailed extends DocumentLoad {
  const DocumentFailed();

  @override
  bool operator ==(Object other) => other is DocumentFailed;

  @override
  int get hashCode => 1;
}

/// Сбор реестра лицензий (D10).
sealed class PackagesLoad {
  const PackagesLoad();
}

final class PackagesNotRequested extends PackagesLoad {
  const PackagesNotRequested();

  @override
  bool operator ==(Object other) => other is PackagesNotRequested;

  @override
  int get hashCode => 0;
}

final class PackagesCollecting extends PackagesLoad {
  const PackagesCollecting();

  @override
  bool operator ==(Object other) => other is PackagesCollecting;

  @override
  int get hashCode => 1;
}

/// [list] — пакеты по имени, [failed] — поток реестра оборвался.
final class PackagesCollected extends PackagesLoad {
  const PackagesCollected(this.list, {required this.failed});

  final List<PackageLicense> list;
  final bool failed;

  @override
  bool operator ==(Object other) =>
      other is PackagesCollected &&
      other.failed == failed &&
      listEquals(other.list, list);

  @override
  int get hashCode => Object.hash(failed, list.length);
}

/// Заметка страницы; текст берёт презентация из ARB.
enum LegalNote { linkFailed }

/// Состояние страницы «Legal» (design.md change `add-app-legal-page`, D7).
///
/// Почему адресация ресурсом: [documents] — кэш по пути, а на экране
/// `documents[shownAsset]`; поздний ответ для прежнего языка заполняет кэш,
/// но не попадает на экран, и номер попытки не нужен.
///
/// Для чего: неизменяемый снимок вкладки, языка, запроса и загруженного;
/// [search] и [shownAsset] — производные.
final class LegalPageState {
  const LegalPageState({
    this.tab = LegalTab.privacyPolicy,
    this.languageCode = 'en',
    this.documents = const {},
    this.packages = const PackagesNotRequested(),
    this.query = '',
    this.note,
  });

  final LegalTab tab;
  final String languageCode;
  final Map<String, DocumentLoad> documents;
  final PackagesLoad packages;
  final String query;
  final LegalNote? note;

  /// Ресурс, показываемый сейчас.
  String get shownAsset => legalAssetOf(tab, languageCode);

  /// Выдача поиска по текущему списку пакетов; пока реестр не собран —
  /// пустая (запрос применится, когда список придёт).
  PackageSearch get search => switch (packages) {
    PackagesCollected(:final list) => searchPackageLicenses(list, query),
    _ => PackageSearch.empty,
  };

  LegalPageState copyWith({
    LegalTab? tab,
    String? languageCode,
    Map<String, DocumentLoad>? documents,
    PackagesLoad? packages,
    String? query,
    LegalNote? note,
    bool clearNote = false,
  }) => LegalPageState(
    tab: tab ?? this.tab,
    languageCode: languageCode ?? this.languageCode,
    documents: documents ?? this.documents,
    packages: packages ?? this.packages,
    query: query ?? this.query,
    note: clearNote ? null : (note ?? this.note),
  );

  @override
  bool operator ==(Object other) =>
      other is LegalPageState &&
      other.tab == tab &&
      other.languageCode == languageCode &&
      other.packages == packages &&
      other.query == query &&
      other.note == note &&
      mapEquals(other.documents, documents);

  @override
  int get hashCode =>
      Object.hash(tab, languageCode, packages, query, note, documents.length);
}
