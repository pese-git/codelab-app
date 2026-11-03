import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Файл слоя конфигурации до разрешения ссылок цели: `user` —
/// `<home>/config.yaml`, `project` — `<cwd>/.codelab/config.yaml`,
/// `projectLocal` — `<cwd>/.codelab/config.local.yaml` (design.md change
/// `add-config-writer-and-reload`, D5, D6).
///
/// Почему отдельная функция: путь нужен и писателю (`ConfigWriter`), и
/// `config path`. Два вычисления разошлись бы, и `$EDITOR $(codelab config
/// path --local)` открывал бы не тот файл, в который пишет `config set
/// --local` (ревью итерации 4, arch L3).
///
/// Как использовать: [home] — каталог `CODELAB_HOME` (`codelabHomeOf`),
/// [target] — слой; у проектных слоёв `target.cwd` обязателен. Корень проекта
/// канонизируется (ссылки на каталог раскрываются), как у загрузчика
/// конфига. Ничего не создаёт и не читает, кроме разбора ссылок каталога.
String configLayerFilePath(ConfigTarget target, String home) {
  switch (target.layer) {
    case ConfigLayer.user:
      return '$home/config.yaml';
    case ConfigLayer.project:
      return '${canonicalDirectory(target.cwd!)}/.codelab/config.yaml';
    case ConfigLayer.projectLocal:
      return '${canonicalDirectory(target.cwd!)}/.codelab/config.local.yaml';
  }
}

/// Каталог с раскрытыми символическими ссылками; исчезнувший между проверкой
/// и разбором — абсолютный путь.
String canonicalDirectory(String dir) {
  try {
    return Directory(dir).resolveSymbolicLinksSync();
  } on FileSystemException {
    return Directory(dir).absolute.path;
  }
}
