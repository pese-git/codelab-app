import 'package:codelab_desktop/core/platform/external_link_opener.dart';

/// Двойник порта [ExternalLinkOpener] для тестов app.
///
/// Почему: настоящий `url_launcher` открывал бы браузер разработчика, а тест
/// ссылок терминала проверяет только то, КАКОЙ адрес и СКОЛЬКО раз
/// presentation передал порту (`add-integrated-terminal`, D3 «Ссылки OSC 8»,
/// D11).
///
/// Для чего: журнал [opened] всех вызовов `open` и настраиваемый [outcome].
///
/// Как использовать: `createCodeLabRootScope(externalLinkOpener: fake)` или
/// `CodeLabTestBinding(externalLinkOpener: fake)`; после жеста пользователя
/// проверять `fake.opened`.
final class FakeExternalLinkOpener implements ExternalLinkOpener {
  FakeExternalLinkOpener({this.outcome = ExternalLinkOutcome.opened});

  /// Исход, который вернёт следующий `open`.
  ExternalLinkOutcome outcome;

  /// Адреса всех вызовов `open` в порядке вызова.
  final List<Uri> opened = [];

  @override
  Future<ExternalLinkOutcome> open(Uri uri) async {
    opened.add(uri);
    return outcome;
  }
}
