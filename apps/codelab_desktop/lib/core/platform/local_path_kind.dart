import 'dart:io';

/// Вид локального пути: что лежит по нему на диске.
///
/// Почему: перетаскивание из ОС отдаёт пути, а «можно ли открыть это как
/// проект» решает application по виду пути (design.md change
/// `add-empty-project-screen`, D4). `DirectoryExists` из `codelab_client_io` не
/// подходит: он не отличает файл от пропавшего пути.
///
/// Для чего: закрытый набор значений вместо исключений файловой системы.
/// [other] — устройство, сокет, канал и ошибка проверки.
enum LocalPathKind { directory, file, missing, other }

/// Порт «какой вид у пути» — шов application и файловой системы.
///
/// Как использовать: `SettingsCubit` получает порт конструктором, реализация
/// по умолчанию — [ioLocalPathKind]; тесты подставляют двойник. Порт НЕ
/// ДОЛЖЕН бросать: любая ошибка проверки — [LocalPathKind.other].
typedef LocalPathKindOf = Future<LocalPathKind> Function(String path);

/// Реализация [LocalPathKindOf] на `dart:io`.
///
/// Ссылки раскрываются только при проверке вида (`followLinks: true`): ссылка
/// на папку — [LocalPathKind.directory], битая ссылка — [LocalPathKind.missing].
/// Сам путь вызывающий не канонизирует: как у «Open folder…», containment
/// обеспечивает агент (D4).
Future<LocalPathKind> ioLocalPathKind(String path) async {
  try {
    return switch (await FileSystemEntity.type(path)) {
      FileSystemEntityType.directory => LocalPathKind.directory,
      FileSystemEntityType.file => LocalPathKind.file,
      FileSystemEntityType.notFound => LocalPathKind.missing,
      _ => LocalPathKind.other,
    };
  } on Object {
    // Контракт порта: исключения наружу не выходят (путь с недопустимым
    // символом, сбой ОС).
    return LocalPathKind.other;
  }
}
