/// Маскирование адресов для показа (R0-2, R4-5; design.md changes
/// `add-config-writer-and-reload`, D6, и `add-provider-setup-ui`, D17).
///
/// Почему в ядре: правило «адрес без userinfo и секретных параметров» нужно и
/// выводу `config get`/`provider list` (`codelab_agent_io`), и строкам
/// `/settings` клиентов (`codelab_setup`, web-безопасный). Две копии разошлись
/// бы, и один из выводов печатал бы то, что другой скрывает. Чистый Dart
/// (PKG-1).
///
/// Как использовать: `maskUrl(raw)` перед печатью значения `base_url`/`url`.
library;

import 'config_issue.dart' show inlineSecretKeys;
import 'inline_secrets.dart';
import 'key_path.dart';
import 'secret_name_rule.dart';
import 'settings_registry.dart';

/// Замена значения секретного листа без ссылки (R0-2).
const redactedMask = '<redacted>';

/// Замена непрозрачного поддерева схемы (R0-2): схемы его листьев в этой
/// сборке нет, и правило имён не гарантирует, что секрет не лежит под
/// безобидным именем.
const opaqueMask = '<opaque: edit the file>';

final _reference = RegExp(r'\$\{[^}]+\}');
final _refToken = RegExp(r'refx(\d+)x');

/// Адрес для вывода: без userinfo, со скрытыми значениями секретных
/// query-параметров (R4-5; design.md change `add-config-writer-and-reload`,
/// D6).
///
/// Почему разбор `Uri`, а не регулярное выражение: userinfo с `@`, `%40` или
/// `/` в пароле обходит шаблон «до первого `@`» и оставляет часть секрета в
/// выводе. Правила: адрес, который `Uri.tryParse` не разбирает, или в
/// котором после удаления userinfo в авторитете остался `@`, →
/// [redactedMask] (fail closed), как и адрес с `@` без авторитета
/// (`user:pass@host`); значение параметра query, фрагмента (`#a=b`) и
/// matrix-параметра пути (`;a=b`), чьё имя секретное по общему правилу
/// ([isSecretLikeName], как у листьев), → [redactedMask];
/// ссылки `${…}` остаются как есть (они не значения), поэтому адрес целиком
/// из ссылки не меняется. Адрес без userinfo и секретных параметров
/// возвращается байт в байт.
///
/// Как использовать: значение `base_url`/`url` из слоя; результат безопасен
/// для печати. Исходный адрес в исключения и логи не попадает.
String maskUrl(String raw) {
  // Ссылки заменяются безопасными токенами, чтобы `Uri` разобрал адрес
  // вроде `https://${U}:${P}@h/${PATH}`; после сборки они возвращаются.
  final refs = <String>[];
  final guarded = raw.replaceAllMapped(_reference, (match) {
    refs.add(match.group(0)!);
    return 'refx${refs.length - 1}x';
  });
  final uri = Uri.tryParse(guarded);
  if (uri == null) {
    return redactedMask;
  }
  // `@` без авторитета: `Uri` принял `user:pass@host` за схему `user`, и
  // userinfo остался бы в пути. Fail closed.
  if (!uri.hasAuthority && guarded.contains('@')) {
    return redactedMask;
  }
  var changed = uri.userInfo.isNotEmpty;
  String maskPairs(String text, String separator) {
    final parts = text.split(separator);
    final masked = <String>[];
    for (final part in parts) {
      final eq = part.indexOf('=');
      final value = eq < 0 ? '' : part.substring(eq + 1);
      var name = eq < 0 ? part : part.substring(0, eq);
      try {
        name = Uri.decodeQueryComponent(name);
      } on Object {
        // Имя с неверным процентным кодированием проверяется как есть.
      }
      if (eq >= 0 &&
          value.isNotEmpty &&
          isSecretLikeName(name) &&
          !_hasRefToken(value, refs.length)) {
        masked.add('${part.substring(0, eq)}=$redactedMask');
        changed = true;
      } else {
        masked.add(part);
      }
    }
    return masked.join(separator);
  }

  final maskedQuery = uri.hasQuery ? maskPairs(uri.query, '&') : '';
  final maskedFragment = uri.hasFragment ? maskPairs(uri.fragment, '&') : '';
  // Matrix-параметры `;имя=значение` внутри сегментов пути.
  final maskedPath = uri.path
      .split('/')
      .map((segment) {
        final semi = segment.indexOf(';');
        if (semi < 0) {
          return segment;
        }
        return '${segment.substring(0, semi + 1)}'
            '${maskPairs(segment.substring(semi + 1), ';')}';
      })
      .join('/');
  if (!changed) {
    return raw;
  }
  final authority = StringBuffer();
  if (uri.hasAuthority) {
    authority
      ..write('//')
      ..write(uri.host.contains(':') ? '[${uri.host}]' : uri.host);
    if (uri.hasPort) {
      authority.write(':${uri.port}');
    }
  }
  if (authority.toString().contains('@')) {
    return redactedMask;
  }
  final rebuilt = StringBuffer()
    ..write(uri.scheme.isEmpty ? '' : '${uri.scheme}:')
    ..write(authority)
    ..write(maskedPath);
  if (uri.hasQuery) {
    rebuilt.write('?$maskedQuery');
  }
  if (uri.hasFragment) {
    rebuilt.write('#$maskedFragment');
  }
  return _restore(rebuilt.toString(), refs);
}

/// В [value] есть токен-заменитель реально существующей ссылки (номер меньше
/// [count]); литерал вида `refx7x` без ссылки с таким номером ссылкой не
/// считается, иначе им прикрывался бы секрет.
bool _hasRefToken(String value, int count) => _refToken
    .allMatches(value)
    .any((match) => int.parse(match.group(1)!) < count);

/// Возвращает на место ссылки `${…}`, заменённые токенами `refxNx`.
String _restore(String text, List<String> refs) =>
    text.replaceAllMapped(_refToken, (match) {
      final index = int.parse(match.group(1)!);
      // Литерал, похожий на токен, но без ссылки с таким номером, остаётся.
      return index < refs.length ? refs[index] : match.group(0)!;
    });

String _decoded(String part) {
  try {
    return Uri.decodeComponent(part);
  } on ArgumentError {
    return part;
  }
}

/// Несёт ли адрес (уже после [maskUrl]) токен в пути, значении параметра
/// запроса или фрагменте. Части проверяются порознь и после
/// percent-декодирования: строка запроса целиком (`a=1&b=2`) совпала бы с
/// «присваиванием секрета» без всякого секрета, а `sk%2Dtest…` обходил бы
/// шаблон.
bool _urlCarriesSecret(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    return false;
  }
  final parts = [
    _decoded(uri.path),
    _decoded(uri.fragment),
    for (final values in uri.queryParametersAll.values) ...values,
  ];
  // Участки, уже скрытые `maskUrl`, не считаются (`token=<redacted>` иначе
  // совпало бы с «присваиванием секрета»).
  return parts.any((p) => hasInlineSecret(p.replaceAll(redactedMask, '')));
}

/// Значение листа конфига для показа человеку (R0-2; design.md change
/// `add-provider-setup-ui`, D17).
///
/// Почему одна функция в ядре: `config get`, `provider list`
/// (`codelab_agent_io`) и строки `/settings` (`codelab_setup`) печатают
/// значения, а файл мог быть правлен руками до редакции секретов. Две копии
/// правила разошлись бы, и один вывод печатал бы то, что другой скрывает.
///
/// Для чего: правила листа — литерал по шаблону секрета в строке скрыт
/// независимо от имени (`api_key_env`/`api_key_secret` проверяются как имена,
/// `sk-` внутри слова не секрет); адрес (`base_url`, `url`) проходит
/// [maskUrl], а токен в пути, фрагменте или параметре query под безобидным
/// именем скрывает весь адрес; лист, описанный реестром, хранит имя секрета
/// или переменной, число или перечисление и печатается как есть, кроме
/// `api_key` и значений по шаблону; лист с секретным именем без ссылки
/// `${…}` → [redactedMask]. Ссылки `${VAR}` и `${secret:x}` печатаются как
/// есть.
///
/// Как использовать: [path] — путь листа в формате `KeyPath`
/// (`providers.gw.base_url`, `mcp.servers[gh].url`); имя листа берётся из
/// последнего сегмента-имени. [value] — скаляр; отображения и списки
/// маскирует вызывающий поэлементно. Источник значения (окружение, флаги) и
/// маскирование `args` — дело вызывающего.
Object? displaySafeConfigValue(String path, Object? value) {
  if (value == null) {
    return null;
  }
  var name = '';
  if (splitKeyPath(path) case final segments?) {
    for (final segment in segments.reversed) {
      if (!segment.isElement) {
        name = segment.value;
        break;
      }
    }
  }
  final isUrl = name == 'base_url' || name == 'url';
  if (value is String && !isUrl) {
    final isName = name == 'api_key_env' || name == 'api_key_secret';
    final hidden = isName
        ? literalSecretTag(value, asName: true) != null
        : hasInlineSecret(value);
    if (hidden) {
      return redactedMask;
    }
  }
  final shown = value is String && isUrl ? maskUrl(value) : value;
  if (shown is String && isUrl && _urlCarriesSecret(shown)) {
    return redactedMask;
  }
  final d = SettingsRegistry.lookup(path);
  if (d != null && d.type != SettingType.map && d.type != SettingType.mapList) {
    // Исключение — `providers.*.api_key`: лист реестра, но его значение —
    // сам ключ (литерал файла, R8-4).
    if (inlineSecretKeys.contains(name) &&
        value is String &&
        value.isNotEmpty &&
        (!hasSecretReference(value) || literalSecretTag(value) != null)) {
      return redactedMask;
    }
    return shown;
  }
  final secretName =
      inlineSecretKeys.contains(name) ||
      (value is String ? isSecretLikeName(name) : isSecretScalarName(name));
  final empty = value is String && value.isEmpty;
  if (secretName && !empty && !(value is String && hasSecretReference(value))) {
    return redactedMask;
  }
  return shown;
}

final _leadingDashes = RegExp(r'^-+');

/// Остаётся ли в [value] что-то, кроме ссылок `${…}`: пустое значение и чистая
/// ссылка литерала не несут (R8-8); `${X}literal` — несёт (fail closed).
bool hidesConfigLiteral(String value) =>
    value.replaceAll(_reference, '').isNotEmpty;

/// Маскирует элементы `mcp.servers[*].args` для показа (R4-6, OQ3; design.md
/// changes `add-config-literal-secrets-and-migrate`, D5, и
/// `add-provider-setup-ui`, D11).
///
/// Почему отдельно от листьев: аргументы — плоский список строк, имени у
/// элемента нет, а токен приходит парой `--token <значение>` или
/// `--token=<значение>`. Одна функция на `config get` (`codelab_agent_io`) и
/// строку MCP-сервера моста `codelab_setup`: две копии разошлись бы.
///
/// Правила по порядку для элемента:
/// - литерал по шаблону §12.4 ([literalSecretTag]) → [redactedMask];
/// - элемент (любого типа) после флага `-…` с секретным именем (то же
///   правило, что у заголовков, [isSecretLikeName]; ложные срабатывания
///   вроде `--max-tokens` допустимы: скрыть лишнее дешевле) →
///   [redactedMask]; исключения: следующий `--флаг` и чистая ссылка `${…}`
///   без литеральной части ([hidesConfigLiteral]);
/// - `--<секретное имя>=<значение>` → `--<имя>=<redacted>` с теми же
///   исключениями;
/// - вложенный список или отображение (невалидный `args` ручной правки) →
///   [opaqueMask];
/// - прочее, включая ссылки и несекретные флаги, — как есть.
/// Граница: короткие флаги (`-p hunter2`) не маскируются — по имени `p`
/// секретность не определить.
///
/// Как использовать: [args] — значение списка из слоя; метка источника без
/// файла (окружение, флаги) — дело вызывающего.
List<Object?> maskMcpArgs(List<Object?> args) {
  final result = <Object?>[];
  var afterSecretFlag = false;
  for (final item in args) {
    final wasSecretFlag = afterSecretFlag;
    afterSecretFlag = false;
    if (item is Map || item is List) {
      result.add(opaqueMask);
      continue;
    }
    if (item is! String) {
      result.add(wasSecretFlag ? redactedMask : item);
      continue;
    }
    if (literalSecretTag(item) != null) {
      result.add(redactedMask);
      continue;
    }
    // Значение после секретного флага: не `--флаг`, не пусто и не чистая
    // ссылка. Один дефис (`-s3cr3t`) значение, а не флаг известной формы.
    if (wasSecretFlag && !item.startsWith('--')) {
      result.add(hidesConfigLiteral(item) ? redactedMask : item);
      continue;
    }
    if (!item.startsWith('-')) {
      result.add(item);
      continue;
    }
    final eq = item.indexOf('=');
    final flagName = (eq < 0 ? item : item.substring(0, eq)).replaceFirst(
      _leadingDashes,
      '',
    );
    final secretFlag = isSecretLikeName(flagName);
    if (eq < 0) {
      afterSecretFlag = secretFlag;
      result.add(item);
    } else if (secretFlag && hidesConfigLiteral(item.substring(eq + 1))) {
      result.add('${item.substring(0, eq)}=$redactedMask');
    } else {
      result.add(item);
    }
  }
  return result;
}
