/// Правило «секретных» имён заголовков и переменных конфига (design.md change
/// `add-config-writer-and-reload`, D5; CFG-9, CFG-12; D8, R0-4).
///
/// Почему в ядре: правило нужно и писателю конфига, предконфигурации и
/// маскированию вывода в `codelab_agent_io`, и перезагрузке в ядре — «провайдер
/// с ключом» определяется в том числе по литеральному секретному заголовку
/// (R0-4). Две копии правила расходились бы: запись приняла бы токен, который
/// перезагрузка не сочла бы секретом, или наоборот.
///
/// Для чего: отличить заголовок или переменную, значение которых — секрет, от
/// обычных (`X-Team`). Имя нормализуется (нижний регистр, без `-` и `_`), чтобы
/// `X-API-KEY`, `x_api_key` и `ApiKey` не обходили правило.
///
/// Как использовать: `isSecretLikeName(name) && !hasSecretReference(value)` —
/// значение литеральный секрет. Ложное срабатывание (`X-Keyboard-Layout`)
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

/// Секретное ли имя для нестрокового значения (число, булево) — то же
/// правило, что у писателя конфига и у вывода (R0-2): запись и показ не
/// расходятся в том, что считать секретным числом.
///
/// Подстрока `token`/`key` дала бы ложные срабатывания на счётчиках
/// (`max_tokens`, `X-Max-Tokens`), поэтому смотрится последнее слово имени
/// (по `-`, `_`, пробелу и границе camelCase) и имя целиком для
/// множественного числа (`keys`, `tokens`).
bool isSecretScalarName(String name) {
  final words = name
      .split(RegExp(r'[-_\s]+|(?<=[a-z0-9])(?=[A-Z])'))
      .where((w) => w.isNotEmpty)
      .map((w) => w.toLowerCase())
      .toList();
  if (words.isEmpty) {
    return false;
  }
  final normalized = name.toLowerCase().replaceAll(RegExp('[-_]'), '');
  return _scalarSecretWords.contains(words.last) ||
      _scalarSecretWords.contains(normalized) ||
      _pluralSecretNames.contains(normalized);
}

const _scalarSecretWords = {
  'token',
  'key',
  'apikey',
  'auth',
  'cookie',
  'secret',
  'password',
  'privatetoken',
  'accesstoken',
};

const _pluralSecretNames = {'keys', 'tokens', 'secrets', 'passwords'};
