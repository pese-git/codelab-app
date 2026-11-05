/// Источник значения конфига для страниц настроек (design.md change
/// `add-provider-setup-ui`, D6, D10).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart' show ConfigLayer;

/// Откуда пришло итоговое значение ключа.
enum ConfigSourceKind {
  /// `$CODELAB_HOME/config.yaml` (слой 2) — редактируется.
  user,

  /// `<проект>/.codelab/config.yaml` (слой 3) — только чтение (SETUP-3).
  project,

  /// `<проект>/.codelab/config.local.yaml` (слой 4) — редактируется.
  projectLocal,

  /// Файл `--config` / `CODELAB_CONFIG` — только чтение.
  extraFile,

  /// Переменные окружения `CODELAB_*` — только чтение.
  environment,
}

/// Источник значения: вид и подпись для `defined in <file>`.
///
/// Почему отдельный тип: страница показывает источник провайдера и решает,
/// можно ли его править, и ей нельзя разбирать строки вроде `env:…` (§12.4.2
/// допускала строку; типизированный вид надёжнее — решение этой итерации).
///
/// Как использовать: строит `AgentConfigSnapshot`; [label] — путь файла или
/// `env`, значений в нём нет. Равенство — по значению.
final class ConfigSourceView {
  const ConfigSourceView({required this.kind, required this.label});

  final ConfigSourceKind kind;

  /// Путь файла (слои 2–4 и `--config`) либо `env`.
  final String label;

  /// Правится ли значение из этого источника: только слои `user` и
  /// `projectLocal` (SETUP-3).
  bool get editable =>
      kind == ConfigSourceKind.user || kind == ConfigSourceKind.projectLocal;

  /// Слой файла источника; `null` у `--config` и окружения. У слоя `project`
  /// слой есть, но [editable] — `false`: писать в него нельзя.
  ConfigLayer? get layer => switch (kind) {
    ConfigSourceKind.user => ConfigLayer.user,
    ConfigSourceKind.projectLocal => ConfigLayer.projectLocal,
    ConfigSourceKind.project => ConfigLayer.project,
    ConfigSourceKind.extraFile || ConfigSourceKind.environment => null,
  };

  @override
  bool operator ==(Object other) =>
      other is ConfigSourceView && other.kind == kind && other.label == label;

  @override
  int get hashCode => Object.hash(kind, label);

  @override
  String toString() => 'ConfigSourceView(${kind.name}, $label)';
}
