/// Порт недавних проектов и его запись теперь живут в `codelab_client_core`
/// (design D8 change `extract-acp-client-kit`); app реэкспортирует их по
/// прежнему пути, пока по нему импортирует
/// `test/features/workbench/application/open_external_link_test.dart`.
library;

export 'package:codelab_client_core/codelab_client_core.dart'
    show RecentProject, RecentProjectsStore;
