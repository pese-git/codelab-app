/// Сценарий модели для тестов и `codelab-agent serve --llm-script` (change
/// `add-embedded-agent-mode`, D8, задача 2.9).
///
/// Почему отдельная точка входа: основной барель `codelab_agent_io` попадает в
/// граф импортов рабочей сборки клиентов через `codelab_embedded/io.dart`.
/// Сценарий оттуда вычищал бы только tree-shaking — гарантия компилятора, а не
/// структуры. Здесь он недостижим из рабочего кода.
///
/// Для чего: `LlmScript` разбирает блок `llm` формата фикстур и отдаёт модели
/// и функцию модели; `withScriptedProviders` кладёт модели сценария в слой
/// флагов конфигурации; `CwdTrackingStore` запоминает `cwd` сессий для
/// сценария. Один код у бинаря и у `scriptedEmbeddedAgentOpener`.
///
/// Как использовать: импорт разрешён сторожем (`melos run guard`) только
/// `apps/codelab_agent`, `codelab_embedded/lib/src/testing/` и тестам.
library;

export 'src/scripted/cwd_tracking_store.dart';
export 'src/scripted/llm_script.dart';
export 'src/scripted/scripted_providers.dart';
