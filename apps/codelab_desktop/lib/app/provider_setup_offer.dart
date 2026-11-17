/// Признак «встроенному агенту нужен провайдер» и папка, с которой агент
/// не открылся.
///
/// Почему: на новой установке встроенный агент не открывается из-за
/// `EmbeddedAgentConfigException`, а баннер показывал сырой текст проблем без
/// пути к настройке (design.md change `add-provider-setup-ui`, D26). Какие
/// именно проблемы значат «нужен провайдер», решает мост (`providerSetupNeeded`
/// по снимку конфига), а не app и не текст сообщения.
///
/// Для чего: значение для `ConnectionCubit`. Резолвер знает встроенного агента,
/// Cubit — номер попытки окна; связывает их этот объект, созданный
/// composition root (образец — `SecretMigrationOffer`).
class ProviderSetupNeeded {
  const ProviderSetupNeeded(this.cwd);

  /// Папка проекта, с которой агент пытались открыть: по ней мастер решает,
  /// доступна ли цель «This project only» (D26).
  final String cwd;

  @override
  String toString() => 'ProviderSetupNeeded';
}

/// Порт между `EmbeddedTransportResolver` и `ConnectionCubit` (D26).
///
/// Почему не поток, как у `SecretMigrationOffer`: Cubit читает значение
/// синхронно в обработчике сбоя своей попытки, и именно тогда оно должно
/// относиться к этой попытке, а не к более поздней. Подписки и контроллера
/// нет, поэтому закрывать нечего.
///
/// Как использовать: резолвер вызывает [set] до исключения (значение при
/// истинном признаке, `null` в начале каждого открытия и при успехе),
/// `ConnectionCubit` читает [value] при сбое попытки встроенного агента.
final class ProviderSetupOffer {
  ProviderSetupNeeded? _value;

  /// Последнее значение резолвера; `null` — провайдер не нужен или агент
  /// ещё не открывался.
  ProviderSetupNeeded? get value => _value;

  /// Задаёт значение; вызывает только `EmbeddedTransportResolver`.
  void set(ProviderSetupNeeded? value) => _value = value;
}
