import '../loop/agent_events.dart';
import '../util/clock.dart';
import '../util/ids.dart';

/// Алфавит ULID (Crockford base32): без `I`, `L`, `O`, `U`, порядок символов
/// совпадает с порядком кодов, поэтому строки сортируются как числа.
const crockfordAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Алфавит id записей журнала (§8.4).
const recordIdAlphabet = '0123456789abcdefghijklmnopqrstuvwxyz';

/// Новый `SessionId` в формате ULID (§8.4).
///
/// Почему ULID: время в начале даёт сортировку файлов журнала по созданию
/// без чтения, случайный хвост исключает коллизии между процессами. Тот же
/// id уходит в ACP как `sessionId`.
///
/// Как использовать: сессия вызывает при создании; время — по [clock]
/// хоста, хвост — 16 символов [ids] (design.md, D3).
SessionId newSessionId(Clock clock, IdGenerator ids) {
  var ms = clock.now().millisecondsSinceEpoch;
  final time = List.filled(10, '0');
  for (var i = 9; i >= 0; i--) {
    time[i] = crockfordAlphabet[ms % 32];
    ms ~/= 32;
  }
  return SessionId('${time.join()}${ids.nextChars(16, crockfordAlphabet)}');
}

/// Новый id записи журнала, которого нет среди [taken] (§8.4).
///
/// Почему короткий: id стоит в каждой строке (`parentId`, ссылки сжатия), а
/// уникальность нужна только внутри одного файла. 8 символов дают 36^8
/// вариантов; совпадение — повтор, не больше 16 раз, затем 12 символов.
///
/// Как использовать: писатель журнала передаёт проверку по `byId` снимка.
String newRecordId(IdGenerator ids, bool Function(String id) taken) {
  for (var attempt = 0; attempt <= 16; attempt++) {
    final id = ids.nextChars(8, recordIdAlphabet);
    if (!taken(id)) {
      return id;
    }
  }
  while (true) {
    final id = ids.nextChars(12, recordIdAlphabet);
    if (!taken(id)) {
      return id;
    }
  }
}
