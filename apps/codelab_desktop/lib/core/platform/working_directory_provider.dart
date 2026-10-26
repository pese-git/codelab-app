/// `WorkingDirectoryProvider` и его реализация на `dart:io` теперь живут в
/// `codelab_client_io` (design D2 change `extract-acp-client-kit`); app
/// реэкспортирует их по прежнему пути, пока по нему импортирует
/// `widget_test.dart`, текст которого не меняется до конца change.
library;

export 'package:codelab_client_io/codelab_client_io.dart'
    show IoWorkingDirectoryProvider, WorkingDirectoryProvider;
