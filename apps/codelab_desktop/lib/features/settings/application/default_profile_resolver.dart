import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:codelab_client_core/codelab_client_core.dart'
    show ConnectionProfile, ProfileStore, usableStoredProfiles;

import '../../../core/platform/connection_preferences.dart';
import 'embedded_profile.dart';

/// Выбор профиля по умолчанию: сохранённый id или встроенный агент.
///
/// Почему отдельный класс: правило D5 нужно и рабочему месту (профиль до
/// первого подключения, «Connect on start»), и странице «Connection»; одно
/// правило в одном месте не даёт им разойтись. Без явного выбора
/// (`codelab.connection.default_profile`) профиль по умолчанию — встроенный
/// агент, как у CLI без `--agent` (решение Q1; design.md change
/// `add-app-settings-shell`, D5, D21).
///
/// Для чего: [resolve] читает сохранённый id и ищет профиль среди пригодных
/// записей `profiles.json` (`usableStoredProfiles`: запись `default` не
/// участвует). Файл читается только когда id задан, поэтому новая установка
/// не трогает диск.
///
/// Как использовать: [resolve] не бросает исключений. Сбой чтения файла или
/// настроек — тоже встроенный агент: подключаться при этом можно, а правка
/// файла и сброс ключа — только явное действие пользователя на странице.
/// Исключение — id, которого в читаемом файле больше нет: ключ удаляется
/// (spec app-settings «Список профилей на странице «Connection»»). Оба
/// случая пишутся в журнал: `connection_profile.default_reset` (info) и
/// `connection_profile.default_unresolved` (warning, только имя типа
/// ошибки; D17, AGENTS.md §16).
final class DefaultProfileResolver {
  DefaultProfileResolver({
    required ProfileStore store,
    required ConnectionPreferences preferences,
    Logger? logger,
  }) : _store = store,
       _preferences = preferences,
       _logger = logger;

  final ProfileStore _store;
  final ConnectionPreferences _preferences;
  final Logger? _logger;

  Future<ConnectionProfile> resolve() async {
    try {
      final id = await _preferences.loadDefaultProfileId();
      if (id == null || id == embeddedProfileId) {
        return embeddedConnectionProfile;
      }
      final stored = usableStoredProfiles(await _store.load()).usable;
      for (final profile in stored) {
        if (profile.id == id) {
          return profile;
        }
      }
      // Профиль удалили (например, из CLI): ключ без профиля сбрасывается.
      await _preferences.saveDefaultProfileId(null);
      _logger?.info('connection_profile.default_reset');
    } on Object catch (error) {
      // Битый файл или недоступное хранилище не мешают подключиться к
      // встроенному агенту; причину покажет страница «Connection».
      _logger?.warning(
        'connection_profile.default_unresolved',
        context: {'error_type': error.runtimeType.toString()},
      );
    }
    return embeddedConnectionProfile;
  }
}
