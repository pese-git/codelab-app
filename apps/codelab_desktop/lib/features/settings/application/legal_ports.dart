import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;

import '../../../core/platform/external_link_opener.dart';
import 'package_license_search.dart';

/// Реестр лицензий пакетов: список по имени и признак сбоя потока (D10).
typedef CollectedLicenses = ({List<PackageLicense> packages, bool failed});

/// Всё, что нужно странице «Legal» от composition root (design.md change
/// `add-app-legal-page`, D7, D10).
///
/// Почему набор портов: Cubit не знает ни `rootBundle`, ни `LicenseRegistry`
/// (AGENTS.md §6, §11); тест подставляет двойники.
///
/// Как использовать: composition root собирает один раз
/// (`CodeLabDependencies.legalPorts`, `buildLegalPorts`); Cubit читает
/// ресурсы и реестр лениво.
final class LegalPorts {
  const LegalPorts({
    required this.readAsset,
    required this.packageLicenses,
    required this.externalLinks,
    this.logger,
  });

  /// Текст ресурса по пути (`legalAssetOf`); ошибка чтения — исключение.
  final Future<String> Function(String asset) readAsset;

  /// Реестр лицензий одним вызовом; сбой потока не бросает, а даёт
  /// `failed: true` с тем, что собрано.
  final Future<CollectedLicenses> Function() packageLicenses;

  /// Открытие внешних ссылок документов (схема `https`).
  final ExternalLinkOpener externalLinks;

  /// События `legal.*` (D11): без запроса поиска, путей и адресов.
  final Logger? logger;
}
