/// Правило литеральных секретов в заголовках и переменных окружения конфига
/// (design.md change `add-config-writer-and-reload`, D5; CFG-9, CFG-12).
///
/// Почему отдельный файл: одно и то же правило имён нужно предконфигурации
/// провайдера (D3, итерация 1), записи конфига `ConfigWriter` (D5, итерация 3)
/// и маскированию вывода `config get` / `provider list` (D6, R0-2). Если оно
/// разойдётся, CLI запишет токен, который загрузчик отклонил бы, или наоборот.
///
/// Для чего: отличить заголовок или переменную, значение которых — секрет, от
/// обычных (`X-Team`). Имя нормализуется (нижний регистр, без `-` и `_`), чтобы
/// `X-API-KEY`, `x_api_key` и `ApiKey` не обходили правило.
///
/// Как использовать: `isSecretLikeName(name) && !hasSecretReference(value)` —
/// значение литеральный секрет, его нельзя записывать в конфиг (нужна ссылка
/// `${secret:…}` или `${VAR}`). Ложное срабатывание (`X-Keyboard-Layout`)
/// обходится ссылкой `${VAR}`: отказ дешевле, чем записанный токен.
library;

/// Корни секретных имён после нормализации (D5). `apikey` и `privatetoken`
/// избыточны (покрыты `key` и `token`) и оставлены ради дословной сверки
/// со списком D5.
const _secretNameParts = [
  'token',
  'secret',
  'password',
  'apikey',
  'auth',
  'cookie',
  'key',
  'privatetoken',
];

/// Секретное ли имя заголовка или переменной (`Authorization`,
/// `Proxy-Authorization`, `X-Api-Key`, `GITHUB_TOKEN`, `Cookie`).
bool isSecretLikeName(String name) {
  final normalized = name.toLowerCase().replaceAll(RegExp('[-_]'), '');
  return _secretNameParts.any(normalized.contains);
}

final _reference = RegExp(r'\$\{[^}]+\}');

/// Есть ли в значении ссылка `${secret:…}` или `${VAR}`.
///
/// Известная граница до 8.11 (D5, R1-1): смешанное значение
/// `Bearer sk-… ${X}` содержит ссылку и поэтому проходит; пункты 2–3 CFG-9
/// по шаблонам §12.4 остаются за 8.11.
bool hasSecretReference(String value) => _reference.hasMatch(value);
