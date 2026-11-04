import 'package:codelab_client_core/codelab_client_core.dart'
    show ConnectionProfile;

/// Профиль хоста встроенного агента в приложении (design.md change
/// `add-embedded-agent-mode`, D9): локальное исполнение, режим разрешений
/// из конфигурации агента.
const embeddedHostProfile = 'embedded-app-desktop';

/// Id встроенного агента среди профилей страницы «Connection»; в
/// `profiles.json` он не пишется и как id профиля зарезервирован
/// (`reservedProfileIds`, design.md change `add-app-settings-shell`, D21).
const embeddedProfileId = 'embedded';

/// Встроенный агент как профиль подключения.
///
/// Почему здесь: профиль нужен и странице «Connection» (первая строка списка),
/// и рабочему месту (профиль по умолчанию, когда выбора нет — D5), а
/// `features/settings/application` — их общая точка, не требующая
/// зависимости рабочего места от страницы.
///
/// Как использовать: передавать в `ClientWorkspace.connect`; транспорт ему
/// даёт `EmbeddedTransportResolver` composition root.
const embeddedConnectionProfile = ConnectionProfile.embedded(
  id: embeddedProfileId,
  label: 'Embedded agent',
  hostProfile: embeddedHostProfile,
);
