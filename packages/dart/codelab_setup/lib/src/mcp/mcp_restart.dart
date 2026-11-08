/// Серверы MCP, которые начнут работать только после перезапуска агента
/// (design.md change `add-provider-setup-ui`, D11 «Итерация 6: сервер,
/// отложенный до перезапуска», решение Q31 (а)).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show ConfigReloadPlan, planConfigReload;

import '../config/agent_config_store.dart';

/// План ядра для перехода [before] → [after] или `null`, если у любого
/// снимка нет `loaded.config` (применённого состояния нет).
ConfigReloadPlan? _planOf(
  AgentConfigSnapshot before,
  AgentConfigSnapshot after,
) {
  final previous = before.loaded.config;
  final next = after.loaded.config;
  if (previous == null || next == null) {
    return null;
  }
  return planConfigReload(
    previousValues: before.loaded.values,
    previous: previous,
    nextValues: after.loaded.values,
    next: next,
  );
}

/// Имена ВКЛЮЧЁННЫХ серверов, которые рантайм агента отложит до перезапуска,
/// если применить к нему переход от [before] к [after].
///
/// Почему через ядро: признак «ждёт перезапуска» — граница безопасности
/// (R0-1: новый `stdio` не запускается на лету; R0-4: `http` с подстановкой
/// `${…}` не отправляет секрет на новый адрес; R6-1: правка соединения,
/// включение `false → true`). Её определяет `planConfigReload`; копия правила
/// в мосте разошлась бы с рантаймом, поэтому здесь только вызов и выбор имён.
///
/// Для чего: `McpSettingsCubit` после записи сервера сравнивает снимок
/// страницы до записи со свежим и, если агент подключён, показывает «starts
/// after Restart agent». Правка без смены соединения (`call_timeout`),
/// удаление и выключение в список не попадают. Выключенный в [after] сервер
/// тоже не называется: ядро откладывает и его правку соединения (R6-1), но
/// запуска он не ждёт — подключит его только `/mcp enable`.
///
/// Как использовать: оба снимка — из `AgentConfigStore.snapshot`. Если у
/// любого нет `loaded.config` (отклонённый или нечитаемый конфиг), применённого
/// состояния нет и результат пуст. Порядок — как в конфиге [after]. Сервер,
/// отложенный ещё прошлой записью, повторно не называется: сравнение идёт со
/// снимком страницы, а не с применённым конфигом агента.
List<String> restartRequiredServers(
  AgentConfigSnapshot before,
  AgentConfigSnapshot after,
) {
  final plan = _planOf(before, after);
  if (plan == null) {
    return const [];
  }
  return [
    // Порядок серверов следующего конфига, а не сортировка ключей показа.
    for (final server in after.loaded.config!.mcpServers)
      if (server.enabled && plan.deferred.servers.contains(server.name))
        server.name,
  ];
}

/// Идентификаторы провайдеров, чьё изменение агент отложит до перезапуска
/// (Q35): новый провайдер «с ключом» (`api_key_secret`, `api_key_env`,
/// подстановка `${…}` в адресе и заголовках, R0-4) и смена группы адреса и
/// аутентификации существующего такого провайдера.
///
/// Почему через ядро: правило то же `planConfigReload`, что у серверов; модели
/// существующего провайдера и провайдеры без ключа применяются сразу и в
/// список не попадают.
///
/// Как использовать: как [restartRequiredServers]; порядок — как в конфиге
/// [after], пусто при отсутствии `loaded.config` у любого снимка.
List<String> restartRequiredProviders(
  AgentConfigSnapshot before,
  AgentConfigSnapshot after,
) {
  final plan = _planOf(before, after);
  if (plan == null) {
    return const [];
  }
  return [
    for (final provider in after.loaded.config!.providers)
      if (plan.deferred.providers.contains(provider.config.name))
        provider.config.name,
  ];
}
