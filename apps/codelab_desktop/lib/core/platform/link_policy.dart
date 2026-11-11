/// Политика ссылок и изображений ответа агента.
///
/// Почему: ответ агента — недоверенный текст (prompt injection), а решение
/// «опасно ли открыть ссылку или загрузить изображение» принимает app, а не
/// виджет (`AGENTS.md` §10, вложенный `AGENTS.md` пакета `codelab_ui` §2).
/// Правила — чистые функции, чтобы таблица схем была и спецификацией, и
/// тестом (change `add-desktop-markdown`, D2, D5, D6; DSK-7).
///
/// Для чего: `isOpenableLink` решает, станет ли ссылка активной и может ли
/// `CodeLabShellCubit.openExternalLink` передать её порту платформы;
/// `isLoadableImage` — предлагать ли «Show image». Всё остальное
/// (`file:`, `javascript:`, `data:`, `vscode:`, `xmpp:`, protocol-relative
/// `//host`, относительные пути) — обычный текст.
///
/// Как использовать: `isOpenableLink(uri)` в `CodeLabMarkdownScope.canOpenLink`
/// и повторно в Cubit перед вызовом порта; `isLoadableImage(uri)` в
/// `CodeLabMarkdownScope.canLoadImage` и в `CodeLabShellCubit.showImage`.
library;

/// Ссылку можно открыть по клику: `http` или `https` с непустым хостом либо
/// `mailto` с непустым адресом.
///
/// Адрес с `userinfo` (`https://good.com@evil.com`) отклоняется: `good.com`
/// там приманка, настоящий хост — после `@` (решение пользователя
/// 2026-11-11). Локальная сеть и числовые IP политикой не режутся — принятый
/// риск R4.
bool isOpenableLink(Uri uri) {
  final scheme = uri.scheme;
  if (scheme == 'http' || scheme == 'https') {
    return uri.hasAuthority && uri.host.isNotEmpty && uri.userInfo.isEmpty;
  }
  if (scheme == 'mailto') {
    return mailtoRecipients(uri).isNotEmpty;
  }
  return false;
}

/// Адресаты `mailto:` — только простые `local@domain`.
///
/// Почему: путь `mailto:a@b%3Fbcc=evil@x.com` после раскодирования прячет
/// параметры, а `%0D%0A` — заголовки письма (ревью итерации 4). Поэтому путь
/// раскодируется, делится по `,` и каждый адрес проверяется: без пробелов,
/// CR/LF, `?`, `&`, `%`, кавычек, скобок, `:`/`;`, косых черт и второго `@`.
///
/// Для чего: пустой список — ссылка неактивна (`isOpenableLink` ложно);
/// непустой — основа для [externalLinkTarget].
List<String> mailtoRecipients(Uri uri) {
  final String decoded;
  try {
    decoded = Uri.decodeComponent(uri.path);
  } on FormatException {
    return const [];
  }
  // Управляющие и невидимые символы (набор `escapeForDisplay` кита: C0/C1,
  // U+061C, U+200B–U+200F, U+2028/2029, U+202A–U+202E, U+2066–U+2069, U+FEFF):
  // адрес с ними выглядел бы иначе, чем он есть.
  if (decoded.runes.any(_isInvisibleOrControl)) {
    return const [];
  }
  final recipients = decoded.split(',');
  final simple = RegExp(r'^[^\s?&%<>"\x27;:\\/@]+@[^\s?&%<>"\x27;:\\/@]+$');
  if (recipients.isEmpty || !recipients.every(simple.hasMatch)) {
    return const [];
  }
  return recipients;
}

/// Изображение можно загрузить после явного действия пользователя: только
/// `https` с непустым хостом. `http` читается и подменяется в пути, `data:` и
/// `file:` не нужны ответу агента.
bool isLoadableImage(Uri uri) =>
    uri.scheme == 'https' &&
    uri.hasAuthority &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty;

/// Адрес, который уходит в платформу.
///
/// Почему: `mailto:` умеет прикладывать файлы и скрытых получателей
/// (`attach`, `bcc`), а ссылка пришла из недоверенного текста. Вложение с
/// путём и скрытая копия не должны попадать в почтовый клиент из ответа
/// агента (решение пользователя 2026-11-11).
///
/// Для чего: у `mailto:` остаются адресаты из пути и `subject`, прочие
/// параметры (`cc`, `bcc`, `body`, `attach`…) отбрасываются; `http` и `https`
/// возвращаются как есть.
///
/// Как использовать: после `isOpenableLink`, перед вызовом порта.
Uri externalLinkTarget(Uri uri) {
  if (uri.scheme != 'mailto') {
    return uri;
  }
  String? subject;
  try {
    subject = uri.queryParameters['subject'];
  } on FormatException {
    // Битый %-escape в query: тему отбрасываем, письмо остаётся.
    subject = null;
  }
  final recipients = mailtoRecipients(uri).join(',');
  return Uri.parse(
    subject == null || subject.isEmpty
        ? 'mailto:$recipients'
        : 'mailto:$recipients?subject=${Uri.encodeComponent(subject)}',
  );
}

bool _isInvisibleOrControl(int unit) =>
    unit < 0x20 ||
    (unit >= 0x7F && unit <= 0x9F) ||
    unit == 0x061C ||
    (unit >= 0x200B && unit <= 0x200F) ||
    unit == 0x2028 ||
    unit == 0x2029 ||
    (unit >= 0x202A && unit <= 0x202E) ||
    (unit >= 0x2066 && unit <= 0x2069) ||
    unit == 0xFEFF;
