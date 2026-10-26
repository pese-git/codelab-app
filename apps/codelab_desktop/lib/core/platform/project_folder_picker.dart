import 'package:file_selector/file_selector.dart';

abstract interface class ProjectFolderPicker {
  Future<String?> pickFolder({String? initialDirectory});
}

final class FileSelectorProjectFolderPicker implements ProjectFolderPicker {
  const FileSelectorProjectFolderPicker();

  @override
  Future<String?> pickFolder({String? initialDirectory}) =>
      getDirectoryPath(initialDirectory: initialDirectory);
}
