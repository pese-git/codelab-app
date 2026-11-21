import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:flutter/foundation.dart' show LicenseEntry, LicenseRegistry;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../core/platform/external_link_opener.dart';
import '../features/settings/application/legal_ports.dart';
import '../features/settings/application/package_license_search.dart';

// Тип записи реестра нужен вызывающему сборщика (тест подставляет свой поток).
export 'package:flutter/foundation.dart' show LicenseEntry;

/// Собирает [LegalPorts] страницы «Legal» (design.md change
/// `add-app-legal-page`, D7, D10).
///
/// Почему в composition root: это единственное место страницы, которое знает
/// `rootBundle` и `LicenseRegistry`; Cubit и виджеты получают готовые порты
/// (AGENTS.md §6, §11).
///
/// Как использовать: [bundle] и [licenses] — швы тестов; без них ресурсы идут
/// из `rootBundle`, реестр — из `LicenseRegistry.licenses`. Реестр собирается
/// один раз и лениво, повторные вызовы возвращают тот же результат.
LegalPorts buildLegalPorts({
  required ExternalLinkOpener externalLinks,
  AssetBundle? bundle,
  Stream<LicenseEntry>? licenses,
  Logger? logger,
}) {
  Future<CollectedLicenses>? cached;
  return LegalPorts(
    readAsset: (asset) => (bundle ?? rootBundle).loadString(asset),
    packageLicenses: () =>
        cached ??= collectPackageLicenses(licenses ?? LicenseRegistry.licenses),
    externalLinks: externalLinks,
    logger: logger,
  );
}

/// Складывает записи реестра в пакеты по имени (D5, D10).
///
/// Почему: `LicenseEntry` относит один текст сразу к нескольким пакетам — он
/// добавляется каждому из них. Список упорядочен по имени.
///
/// Как использовать: принимает поток, а не читает реестр сам, чтобы тест
/// подставлял свой. Ошибка потока не бросается: возвращается собранное и
/// `failed: true`, чтобы сбой не прятал уведомления (D13 `add-app-general-page`).
Future<CollectedLicenses> collectPackageLicenses(
  Stream<LicenseEntry> entries,
) async {
  final byName = <String, List<String>>{};
  var failed = false;
  try {
    await for (final entry in entries) {
      final text = entry.paragraphs.map((p) => p.text).join('\n');
      for (final name in entry.packages) {
        (byName[name] ??= []).add(text);
      }
    }
  } on Object {
    failed = true;
  }
  final names = byName.keys.toList()..sort();
  return (
    packages: [
      for (final name in names)
        PackageLicense(name: name, licenses: byName[name]!),
    ],
    failed: failed,
  );
}
