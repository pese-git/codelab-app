/// Версия сборки app и адрес заметок о выпуске (design.md change
/// `add-app-general-page`, D11, D14).
///
/// Почему константы: `package_info_plus` в стек не входит (AGENTS.md §4,
/// §14), образец — `cliVersion` терминального клиента. Расхождение с
/// `pubspec.yaml` и с адресом репозитория сайта ловят `build_version_test`.
///
/// Как использовать: раздел «About» страницы «General» показывает версию, а
/// «Release notes» открывает адрес через порт `ExternalLinkOpener`.
library;

/// Версия сборки desktop; тест сверяет её с `version` в `pubspec.yaml`.
/// При выпуске обновляется вместе с `pubspec.yaml`.
const codelabDesktopVersion = '0.1.0';

/// Адрес `CHANGELOG.md` репозитория CodeLab на ветке `master`; `<repo>` — тот
/// же адрес, что `repoUrl` в `site/src/site.config.ts` (тест сверяет).
/// Константа app, а не ввод пользователя: страница новостей сайта не
/// используется, пока не выбран хостинг (решение пользователя 2026-11-19).
const kCodeLabReleaseNotesUrl =
    'https://github.com/pese-git/codelab-app/blob/master/CHANGELOG.md';
