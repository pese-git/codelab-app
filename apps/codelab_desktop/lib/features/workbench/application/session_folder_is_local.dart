import 'package:codelab_client_core/codelab_client_core.dart'
    show ConnectionProfile, EmbeddedProfile, StdioProfile, WebSocketProfile;

/// Лежит ли папка сессии на этой машине для подключения по [profile].
///
/// Почему: панели, которые читают или запускают что-то в папке сессии
/// (Files, позже Terminal), имеют смысл, только если агент видит ту же
/// файловую систему, что и клиент. Встроенный агент работает в нашем
/// процессе, stdio-агент — дочерний процесс этой машины; WebSocket-агент
/// может быть где угодно, и путь его `cwd` на нашей машине ничего не значит
/// (spec workspace-file-browser «Панель Files в доке инструментов», Q8, Q10;
/// design.md change `add-file-preview-and-tree`, D7, D9).
///
/// Для чего: единственный предикат «папка сессии здесь» — его же использует
/// терминальный change (`add-integrated-terminal`, A16 шаг 6). Решение о
/// профиле принимает application, виджеты спрашивают готовый ответ (AGENTS.md
/// §10 по духу: presentation не решает политику).
///
/// Как использовать: передать профиль окна (`WindowConnectionState.profile`).
/// Web и устройства без папок этим предикатом не покрываются: там просто нет
/// привязки `ProjectFiles`, и панель не предлагается.
bool sessionFolderIsLocal(ConnectionProfile profile) => switch (profile) {
  EmbeddedProfile() || StdioProfile() => true,
  WebSocketProfile() => false,
};
