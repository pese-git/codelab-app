/// Признаки элемента `skills.extra_roots` как он записан в конфиге (design.md
/// change `add-agent-skills`, D3, Q41; `add-app-skills-page`, D5).
///
/// Почему в ядре: загрузчик навыков (`codelab_agent_io`) и мост настроек
/// (`codelab_setup`, web-безопасный) решают по одному признаку, читать ли
/// относительный корень у недоверенного проекта; два экземпляра правила
/// разошлись бы тихо (`AGENTS.md` §14). Функции чистые, без `dart:io`
/// (PKG-1).
///
/// Как использовать: передавать строку элемента как записана; раскрытие `~` и
/// путь от `cwd` делает хост.
library;

/// Элемент — абсолютный путь: `/…` или с буквой диска (`C:\…`, `C:/…`).
bool isAbsoluteSkillRoot(String raw) =>
    raw.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(raw);

/// Элемент — `~` или `~/…` (домашний каталог пользователя).
bool isHomeSkillRoot(String raw) => raw == '~' || raw.startsWith('~/');

/// Элемент — относительный путь от `cwd` сессии: не абсолютный, не `~…` и не
/// `<scheme>://…`. Остальное — путь хоста либо не корень.
bool isRelativeSkillRoot(String raw) =>
    !isAbsoluteSkillRoot(raw) && !raw.startsWith('~') && !raw.contains('://');
