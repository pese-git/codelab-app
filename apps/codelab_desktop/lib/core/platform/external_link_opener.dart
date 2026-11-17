import 'package:url_launcher/url_launcher.dart';

import 'link_policy.dart';

/// Исход попытки открыть внешнюю ссылку (D12).
///
/// [rejectedScheme] — схема вне политики, платформа не вызывалась; [failed] —
/// платформа отказала или не нашла обработчик.
enum ExternalLinkOutcome { opened, failed, rejectedScheme }

/// Порт открытия внешней ссылки в приложении ОС.
///
/// Почему: открытие URL — platform concern (`AGENTS.md` §11,
/// `platform-integration.md`): виджеты и Cubit не вызывают плагин напрямую, а
/// тест подставляет двойник (образец — `ProjectFolderPicker`).
///
/// Для чего: единственная точка, откуда ссылка из ответа агента попадает в
/// систему. Начинается только с клика пользователя (DSK-7).
///
/// Как использовать: привязан в `app_scope.dart`; вызывает
/// `CodeLabShellCubit.openExternalLink` после проверки политики.
abstract interface class ExternalLinkOpener {
  Future<ExternalLinkOutcome> open(Uri uri);
}

/// Реализация на `url_launcher` (единственное место его импорта, D10).
///
/// Схему проверяет повторно — вторая линия защиты на случай ошибки вызывающего:
/// адрес вне политики до платформы не доходит. Исключение платформы даёт
/// [ExternalLinkOutcome.failed].
final class UrlLauncherExternalLinkOpener implements ExternalLinkOpener {
  const UrlLauncherExternalLinkOpener({Future<bool> Function(Uri uri)? launch})
    : _launch = launch;

  /// Шов тестов; по умолчанию внешнее приложение ОС.
  final Future<bool> Function(Uri uri)? _launch;

  @override
  Future<ExternalLinkOutcome> open(Uri uri) async {
    if (!isOpenableLink(uri)) {
      return ExternalLinkOutcome.rejectedScheme;
    }
    try {
      final launch =
          _launch ??
          (Uri target) =>
              launchUrl(target, mode: LaunchMode.externalApplication);
      return await launch(uri)
          ? ExternalLinkOutcome.opened
          : ExternalLinkOutcome.failed;
    } on Object {
      // Текст исключения платформы может содержать адрес целиком — наружу
      // идёт только исход (`AGENTS.md` §16).
      return ExternalLinkOutcome.failed;
    }
  }
}
