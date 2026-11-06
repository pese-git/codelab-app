/// Адрес провайдера для экрана и журнала (client-agent-setup «Состав моста»;
/// design.md change `add-provider-setup-ui`, D6, Q11).
library;

/// Адрес без userinfo, query и fragment: схема, хост, порт и путь.
///
/// Почему: в `base_url` могут быть пароль в userinfo и ключ в query (у Azure
/// OpenAI `api-version` штатный), и на экран, в журнал и в сводку мастера
/// адрес целиком выводить нельзя (SETUP-1).
///
/// Для чего: единственная реализация правила для `ProviderDraft`,
/// `ProviderEntryView`, мастера и CLI; строки `/settings` маскируют адрес
/// общим правилом ядра (`maskUrl`).
///
/// Как использовать: `displayBaseUrl(provider.baseUrl)`. `null`, пустая
/// строка, адрес без схемы или хоста и неразбираемый адрес дают `null`.
String? displayBaseUrl(String? url) {
  final uri = url == null ? null : Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty || uri.scheme.isEmpty) {
    return null;
  }
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  ).toString();
}
