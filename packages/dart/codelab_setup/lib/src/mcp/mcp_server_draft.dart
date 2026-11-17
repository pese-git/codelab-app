/// Черновик MCP-сервера для формы добавления и правки (`dart-agent-and-clients`
/// §12.4.6, шаг 3; design.md change `add-provider-setup-ui`, D11; SETUP-1,
/// SETUP-5).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show
        ConfigEdit,
        SecretNames,
        UpsertMcpServer,
        isValidMcpServerName,
        soleSecretReference;

import '../secret/secret_value.dart';
import 'mcp_masking.dart';
import 'mcp_transport_kind.dart';

/// Значение `env` или `headers` в форме.
///
/// Почему три вида: значение, вписанное пользователем, остаётся текстом в
/// конфиге; значение с флажком «Secret» уходит в хранилище, а в конфиг пишется
/// ссылка; уже сохранённый секрет при правке показывается как `stored`, а
/// «не менять» оставляет ссылку (D11). `toString()` значений не печатает.
sealed class McpValueDraft {
  const McpValueDraft();

  /// Текст как есть: литерал, `${VAR}` или `Bearer ${secret:…}` со своей
  /// ссылкой. Секретное литеральное значение писатель конфига отклонит
  /// (`ConfigInlineSecret`).
  const factory McpValueDraft.text(String value) = McpTextValue;

  /// Новое секретное значение: в хранилище под `SecretNames.forMcp`, в
  /// конфиг — `${secret:<имя>}`.
  const factory McpValueDraft.secret(SecretValue value) = McpNewSecret;

  /// Уже сохранённый секрет, значение «не менять»: [reference] — ссылка
  /// `${secret:<имя>}` из файла.
  const factory McpValueDraft.stored(String reference) = McpStoredSecret;
}

/// См. [McpValueDraft.text].
final class McpTextValue extends McpValueDraft {
  const McpTextValue(this.value);

  final String value;

  @override
  String toString() => 'McpTextValue';
}

/// См. [McpValueDraft.secret].
final class McpNewSecret extends McpValueDraft {
  const McpNewSecret(this.value);

  final SecretValue value;

  @override
  String toString() => 'McpNewSecret';
}

/// См. [McpValueDraft.stored].
final class McpStoredSecret extends McpValueDraft {
  const McpStoredSecret(this.reference);

  final String reference;

  /// Имя секрета из ссылки.
  String? get name => soleSecretReference(reference);

  @override
  String toString() => 'McpStoredSecret';
}

/// Поле формы, к которому относится проблема.
enum McpDraftField { name, command, url, env, headers }

/// Проблема черновика до записи: [message] — готовый текст без значений.
final class McpDraftProblem {
  const McpDraftProblem(this.field, this.message);

  final McpDraftField field;
  final String message;

  @override
  String toString() => 'McpDraftProblem(${field.name}: $message)';
}

/// Форма сервера `mcp.servers`: проверка, правка и секреты к записи.
///
/// Почему отдельный тип: форма app и CLI проверяет одно и то же до записи, а
/// `UpsertMcpServer` заменяет элемент целиком (ключи, которых нет в карте,
/// удаляются), поэтому правка строится из СЫРОГО элемента слоя
/// ([McpServerDraft.fromElement]) и сохраняет неизвестные ему ключи
/// (`call_timeout` и др.).
///
/// Для чего: `validate()` — проблемы до записи (имя по правилу ядра
/// `isValidMcpServerName`, общему с `codelab mcp add`; уникальность; команда
/// или URL без userinfo; непустые ключи); `toEdits()` — одна правка
/// `UpsertMcpServer`; `secretsToWrite()` — значения для хранилища. Порядок
/// «секрет → конфиг → откат» — у `McpServerCommitter`.
///
/// Как использовать: новый сервер — конструктор; правка — `fromElement(сырой
/// элемент слоя)` и `copyWith`. `toString()` значений не печатает (SETUP-1).
final class McpServerDraft {
  McpServerDraft({
    required this.name,
    required this.kind,
    this.command = '',
    this.args = const [],
    this.url = '',
    this.env = const {},
    this.headers = const {},
    this.enabled = true,
  }) : originalName = null,
       _extra = const {};

  McpServerDraft._({
    required this.name,
    required this.kind,
    required this.command,
    required this.args,
    required this.url,
    required this.env,
    required this.headers,
    required this.enabled,
    required this.originalName,
    required Map<String, Object?> extra,
  }) : _extra = extra;

  /// Черновик правки по сырому элементу слоя (как в файле): значение, равное
  /// ровно `${secret:<имя>}`, — [McpStoredSecret], прочие — текст.
  factory McpServerDraft.fromElement(Map<String, Object?> element) {
    McpValueDraft valueOf(Object? raw) {
      final text = '$raw';
      return soleSecretReference(text) != null
          ? McpStoredSecret(text)
          : McpTextValue(text);
    }

    Map<String, McpValueDraft> table(Object? raw) =>
        raw is Map<Object?, Object?>
        ? {for (final e in raw.entries) '${e.key}': valueOf(e.value)}
        : const {};

    final url = element['url'];
    final command = element['command'];
    final rawArgs = element['args'];
    return McpServerDraft._(
      name: '${element['name']}',
      kind: mcpTransportKindOf(element),
      command: command is String ? command : '',
      args: rawArgs is List<Object?>
          ? [for (final a in rawArgs) '$a']
          : const [],
      url: url is String ? url : '',
      env: table(element['env']),
      headers: table(element['headers']),
      enabled: element['enabled'] != false,
      originalName: '${element['name']}',
      extra: {
        for (final e in element.entries)
          if (!_known.contains(e.key)) e.key: e.value,
      },
    );
  }

  static const _known = {
    'name',
    'type',
    'command',
    'args',
    'env',
    'url',
    'headers',
    'enabled',
  };

  final String name;
  final McpTransportKind kind;
  final String command;
  final List<String> args;
  final String url;
  final Map<String, McpValueDraft> env;
  final Map<String, McpValueDraft> headers;
  final bool enabled;

  /// Имя правимого сервера; `null` у нового. Своё имя при проверке
  /// уникальности не считается занятым.
  final String? originalName;

  /// Ключи элемента, которых форма не знает: сохраняются при записи.
  final Map<String, Object?> _extra;

  McpServerDraft copyWith({
    String? name,
    McpTransportKind? kind,
    String? command,
    List<String>? args,
    String? url,
    Map<String, McpValueDraft>? env,
    Map<String, McpValueDraft>? headers,
    bool? enabled,
  }) => McpServerDraft._(
    name: name ?? this.name,
    kind: kind ?? this.kind,
    command: command ?? this.command,
    args: args ?? this.args,
    url: url ?? this.url,
    env: env ?? this.env,
    headers: headers ?? this.headers,
    enabled: enabled ?? this.enabled,
    originalName: originalName,
    extra: _extra,
  );

  /// Ключи, чьи значения список маскирует: `command`, `url`, `args`,
  /// `env.<KEY>`, `headers.<KEY>` (независимо от активного типа). Правило общее со строкой списка
  /// (`McpServerEntryView`, `mcp_masking.dart`).
  ///
  /// Почему: черновик хранит сырое значение (запись пишет элемент целиком, и
  /// маска стёрла бы его), а форма не должна показывать то, что список
  /// скрыл. App по этому набору выводит маску «пусто = не менять» вместо
  /// значения. Секреты (`McpNewSecret`, `McpStoredSecret`) маскируются формой
  /// всегда и в набор не входят.
  Set<String> get maskedValues {
    // Все поля независимо от активного типа: переключение stdio ↔ http не
    // должно открывать то, что строка списка скрывает.
    final out = <String>{};
    if (command.isNotEmpty &&
        mcpDisplayValue(name, 'command', command) != command) {
      out.add('command');
    }
    if (url.isNotEmpty && mcpDisplayValue(name, 'url', url) != url) {
      out.add('url');
    }
    if (args.isNotEmpty &&
        mcpDisplayArgs(args).join('\u0000') != args.join('\u0000')) {
      out.add('args');
    }
    for (final MapEntry(:key, :value) in env.entries) {
      if (value is McpTextValue &&
          mcpDisplayValue(name, 'env.${mcpKeySegment(key)}', value.value) !=
              value.value) {
        out.add('env.$key');
      }
    }
    for (final MapEntry(:key, :value) in headers.entries) {
      if (value is McpTextValue &&
          mcpDisplayHeader(value.value) != value.value) {
        out.add('headers.$key');
      }
    }
    return out;
  }

  /// Проблемы до записи; пусто — черновик годится. [existingNames] — имена
  /// серверов эффективного конфига (уникальность).
  List<McpDraftProblem> validate({Set<String> existingNames = const {}}) {
    final out = <McpDraftProblem>[];
    if (!isValidMcpServerName(name)) {
      out.add(
        const McpDraftProblem(
          McpDraftField.name,
          'Use a name without spaces, [, ] or ".',
        ),
      );
    } else if (originalName != null && name != originalName) {
      // Переименование не записывается: `UpsertMcpServer` заменил бы элемент
      // по новому имени, а старый остался бы, и секреты `codelab/mcp/<имя>/`
      // потеряли бы владельца. Решение пользователя (ревью 5a).
      out.add(
        const McpDraftProblem(
          McpDraftField.name,
          'Remove the server and add it again to rename it.',
        ),
      );
    } else if (name != originalName && existingNames.contains(name)) {
      out.add(
        const McpDraftProblem(
          McpDraftField.name,
          'A server with this name already exists.',
        ),
      );
    }
    switch (kind) {
      case McpTransportKind.stdio:
        if (command.trim().isEmpty) {
          out.add(
            const McpDraftProblem(McpDraftField.command, 'Enter the command.'),
          );
        }
        _tableProblems(env, McpDraftField.env, out);
      case McpTransportKind.http:
        if (_urlProblem() case final problem?) {
          out.add(McpDraftProblem(McpDraftField.url, problem));
        }
        _tableProblems(headers, McpDraftField.headers, out);
    }
    return out;
  }

  /// Текст проблемы адреса без самого адреса: в нём может быть пароль.
  String? _urlProblem() {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return 'Enter an http or https URL.';
    }
    if (uri.host.isEmpty) {
      return 'Enter an http or https URL.';
    }
    if (uri.userInfo.isNotEmpty) {
      return 'Remove the user name and password from the URL.';
    }
    return null;
  }

  void _tableProblems(
    Map<String, McpValueDraft> table,
    McpDraftField field,
    List<McpDraftProblem> out,
  ) {
    // Имена секретов после нормализации `SecretNames.forMcp` (нижний регистр,
    // недопустимые символы — `-`) могут совпасть у разных ключей: второй
    // секрет затёр бы первый.
    // Хранимые ссылки других ключей занимают свои имена заранее: новое
    // значение под таким именем затёрло бы чужой секрет.
    final taken = <String>{
      for (final value in table.values)
        if (value is McpStoredSecret && value.name != null) value.name!,
    };
    // Ключи, равные после `trim`, — один и тот же ключ для человека: молча
    // схлопнуть нельзя, пользователь выбирает, какое значение оставить.
    final seen = <String>{};
    for (final MapEntry(:key, :value) in table.entries) {
      if (key.trim().isNotEmpty && key != key.trim()) {
        // Пробелы по краям попали бы в имя переменной или заголовка как есть.
        out.add(McpDraftProblem(field, 'Remove spaces around the name $key.'));
        continue;
      }
      if (key.trim().isNotEmpty && !seen.add(key.trim())) {
        out.add(McpDraftProblem(field, 'Two values are named ${key.trim()}.'));
        continue;
      }
      if (key.trim().isEmpty) {
        out.add(McpDraftProblem(field, 'Enter a name for every value.'));
      } else if (value is McpNewSecret && value.value.reveal().isEmpty) {
        out.add(McpDraftProblem(field, 'Enter the secret value for $key.'));
      } else if (value is McpNewSecret &&
          !taken.add(SecretNames.forMcp(name, key))) {
        out.add(
          McpDraftProblem(
            field,
            'Two secret values get the same secret name; rename $key.',
          ),
        );
      }
    }
  }

  /// Одна правка `UpsertMcpServer` с элементом целиком; для недопустимого
  /// черновика ([validate] без проверки уникальности) — пусто.
  List<ConfigEdit> toEdits() {
    if (validate().isNotEmpty) {
      return const [];
    }
    String render(String key, McpValueDraft value) => switch (value) {
      McpTextValue(:final value) => value,
      McpStoredSecret(:final reference) => reference,
      McpNewSecret() => '\${secret:${SecretNames.forMcp(name, key)}}',
    };
    Map<String, Object?> table(Map<String, McpValueDraft> source) => {
      for (final MapEntry(:key, :value) in source.entries)
        key: render(key, value),
    };
    final element = <String, Object?>{
      'name': name,
      'type': kind.name,
      ...switch (kind) {
        McpTransportKind.stdio => {
          'command': command,
          if (args.isNotEmpty) 'args': args,
          if (env.isNotEmpty) 'env': table(env),
        },
        McpTransportKind.http => {
          'url': url,
          if (headers.isNotEmpty) 'headers': table(headers),
        },
      },
      if (!enabled) 'enabled': false,
      ..._extra,
    };
    return [UpsertMcpServer(element)];
  }

  /// Секреты к записи в хранилище: имя `SecretNames.forMcp(name, key)` →
  /// значение. Только таблица активного типа (stdio — `env`, http —
  /// `headers`): значения неактивной в элемент не попадают, и секрет без
  /// ссылки остался бы сиротой. «Не менять» (хранимый секрет) сюда не
  /// попадает.
  Map<String, SecretValue> secretsToWrite() => {
    for (final MapEntry(:key, :value)
        in (kind == McpTransportKind.stdio ? env : headers).entries)
      if (value is McpNewSecret) SecretNames.forMcp(name, key): value.value,
  };

  // Значения (в том числе текстовые: в них бывают токены) не печатаются.
  @override
  String toString() => 'McpServerDraft($name, ${kind.name})';
}
