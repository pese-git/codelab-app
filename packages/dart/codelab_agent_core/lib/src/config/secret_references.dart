/// Ссылки `${secret:<имя>}` в значениях конфига (design.md change
/// `add-provider-setup-ui`, D11, решение Q22).
library;

import 'interpolate.dart';

/// Имена секретов из ссылок `${secret:<имя>}` в [value], по порядку и без
/// повторов (design.md change `add-provider-setup-ui`, D11, решение Q22).
///
/// Почему в ядре: имена ссылок нужны мосту `codelab_setup` (удаление
/// MCP-сервера, форма) так же, как загрузке конфига, и разбор должен быть
/// один: `$${secret:x}` — литерал, а не ссылка, `${ghp_…}` (токен вместо
/// имени) — не ссылка и в список не попадает. Свои регулярные выражения
/// клиентов расходились бы с этим разбором.
///
/// Как использовать: `secretReferencesIn(headers['Authorization'])`;
/// значение в результат не попадает, имена секретами не являются.
List<String> secretReferencesIn(String value) =>
    expandEnvironment(value, const {}).template.names;

/// Имя секрета, если [value] — ровно одна ссылка `${secret:<имя>}` без текста
/// вокруг и без `${VAR}`; иначе `null`.
///
/// Для чего: форма MCP-сервера отличает «хранимый секрет» (значение «не
/// менять») от текста пользователя, а вид — чистую ссылку от значения с
/// литеральной частью. Разбор тот же, что у [secretReferencesIn].
String? soleSecretReference(String value) {
  final expansion = expandEnvironment(value, const {});
  final names = expansion.template.names;
  if (names.length == 1 &&
      expansion.missing.isEmpty &&
      value == '\${secret:${names.single}}') {
    return names.single;
  }
  return null;
}
