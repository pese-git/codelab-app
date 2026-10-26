/// Порт недавних проектов и его запись теперь живут в `acp_client_kit`
/// (design D8 change `extract-acp-client-kit`); app реэкспортирует их по
/// прежнему пути, пока по нему импортируют `widget_test.dart` и
/// характеризационные тесты, тексты которых не меняются до конца change.
library;

export 'package:acp_client_kit/acp_client_kit.dart'
    show RecentProject, RecentProjectsStore;
