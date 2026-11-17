import 'connection_profile.dart';

final _profileId = RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$');

/// Id, которые профилю подключения давать нельзя: оба — имена встроенного
/// агента (`embedded` — слово `--agent`, `default` — его алиас; design.md
/// change `add-app-settings-shell`, D21).
///
/// Почему отдельно от [isValidProfileId]: нарушение синтаксиса и резерв
/// требуют разных сообщений об ошибке.
///
/// Как использовать: проверяют `ProfileDraft` app и `codelab profiles add`;
/// `JsonFileProfileStore.save` отклоняет такой id `ArgumentError`.
const reservedProfileIds = {'embedded', 'default'};

/// `true`, если [id] входит в [reservedProfileIds].
bool isReservedProfileId(String id) => reservedProfileIds.contains(id);

/// Допустим ли [id] нового профиля: `^[a-z0-9][a-z0-9._-]{0,63}$`.
///
/// Почему: нижний регистр и без `:` выбраны заранее, чтобы имя секрета
/// `codelab/profiles/<id>/token` прошло `SecretNames` (change
/// `add-provider-setup-ui`); правило — подмножество прежнего правила CLI
/// (design.md change `add-app-settings-shell`, D11).
///
/// Как использовать: только для **новых** профилей (`profiles add`, форма
/// app). Прежние профили с другими id (`Old`) читаются и выбираются как
/// раньше, поэтому при загрузке и выборе функция не применяется.
bool isValidProfileId(String id) => _profileId.hasMatch(id);

/// Предлагает id профиля по его имени: нижний регистр, каждый символ вне
/// `[a-z0-9]` — `-`, повторы схлопнуты, `-` по краям убраны.
///
/// Почему: пользователь вводит имя («My Dev-Box!»), а id — ключ хранения и
/// часть имени будущего секрета; предложение избавляет от ручного набора
/// (design.md change `add-app-settings-shell`, D11).
///
/// Как использовать: форма подставляет результат в поле id, пока оно не
/// правлено вручную. Результат может быть пустым (`!!!`) или
/// зарезервированным (`Default` → `default`): допустимость решает
/// `ProfileDraft.validate`, а не эта функция.
String suggestProfileId(String label) => label
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

/// Разделяет прочитанный список профилей на пригодные к выбору и признак
/// прежней записи `default`.
///
/// Почему: `default` теперь имя встроенного агента, а в `profiles.json`
/// от прежней версии такая запись могла остаться. Хранилище данные не
/// прячет (`ProfileStore.load` возвращает файл как есть), а решение —
/// игнорировать запись — принимает потребитель, и принимает одинаково
/// (design.md change `add-app-settings-shell`, D21).
///
/// Для чего: единственное место, где запись `default` отделяется; CLI и
/// страница «Connection» app выбирают профиль только из `usable` и
/// сообщают пользователю о [ignoredDefault]. Файл не перезаписывается:
/// удаляет запись только явный `ProfileStore.remove('default')`.
///
/// Как использовать: `final (:usable, :ignoredDefault) =
/// usableStoredProfiles(await store.load())`. Порядок `usable` — порядок
/// файла.
({List<ConnectionProfile> usable, bool ignoredDefault}) usableStoredProfiles(
  List<ConnectionProfile> profiles,
) {
  const legacy = 'default';
  return (
    usable: List.unmodifiable([
      for (final profile in profiles)
        if (profile.id != legacy) profile,
    ]),
    ignoredDefault: profiles.any((profile) => profile.id == legacy),
  );
}
