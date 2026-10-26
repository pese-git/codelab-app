/// Порт недавних проектов и его запись теперь живут в `codelab_client_core`
/// (design D8 change `extract-acp-client-kit`); app реэкспортирует их по
/// прежнему пути, пока по нему импортируют `widget_test.dart` и
/// характеризационные тесты, тексты которых не меняются до конца change.
library;

export 'package:codelab_client_core/codelab_client_core.dart'
    show RecentProject, RecentProjectsStore;
