import 'package:codelab_setup/codelab_setup.dart';

/// Страница, которой принадлежит ключ реестра `scope: shared` (design.md
/// change `add-app-general-page`, D2).
///
/// Почему: раскладка ключей по страницам — решение экрана app, а не моста
/// (CLI показывает все строки `/settings`). Явная таблица с тестом полноты
/// заставляет решить судьбу нового ключа, а не даёт ему молча появиться на
/// «General» или пропасть.
///
/// Для чего: `general` — блок «Agent defaults»; остальные владельцы только
/// исключают ключ со «General» (у них своя страница или правка запрещена).
enum SettingsPageOwner {
  general,
  providers,
  agentsAndModes,
  mcpServers,
  permissionsAndTools,
  trustBoundary,
}

/// Строка блока «Agent defaults»: строка реестра, отказ в правке и перекрытие.
///
/// Для чего: чистые данные для страницы; решение «можно ли править» берётся
/// из моста (`settingEditRefusalOf`, D6), а не принимается в виджете.
final class AgentDefaultsRow {
  const AgentDefaultsRow({
    required this.field,
    this.refusal,
    this.overriddenBy,
  });

  /// Строка реестра: ключ, значение, источник, дескриптор.
  final SettingFieldView field;

  /// Причина, по которой редактора нет; `null` — строка редактируется.
  final SettingEditRefusal? refusal;

  /// `project` или `local`, если значение пришло из проектного слоя
  /// (подпись `This project overrides it (<source>).`); иначе `null`.
  final String? overriddenBy;
}

/// Группа строк одного раздела реестра.
final class AgentDefaultsGroup {
  const AgentDefaultsGroup({required this.section, required this.rows});

  /// Раздел реестра: `Budget`, `Agent`, `Subagents` или `Logging`.
  final String section;
  final List<AgentDefaultsRow> rows;
}

/// Заглушка итерации 2 (красные тесты 2.1): реализация — задача 2.2.
SettingsPageOwner? settingsPageOwnerOf(String descriptorKey) => null;

/// Заглушка итерации 2 (красные тесты 2.1): реализация — задача 2.2.
List<AgentDefaultsGroup> agentDefaultsGroupsOf(
  Iterable<SettingFieldView> fields,
) => const [];

/// Идентификатор сообщения ARB с подписью ключа реестра (D2).
///
/// Заглушка итерации 2: реализация — задача 2.2.
String agentSettingLabelId(String descriptorKey) => '';

/// Идентификатор сообщения ARB с описанием ключа реестра (D2).
///
/// Заглушка итерации 2: реализация — задача 2.2.
String agentSettingDescriptionId(String descriptorKey) => '';
