## ADDED Requirements

### Requirement: Лицензия и сторонние уведомления в сборке app
Сборка `apps/codelab_desktop` SHALL содержать ресурсы `assets/legal/LICENSE` и `assets/legal/THIRD_PARTY_NOTICES.md`, побайтно равные `LICENSE` и `THIRD_PARTY_NOTICES.md` корня репозитория. Равенство SHALL проверять тест app. Правка корневого файла без копии SHALL ронять тест (design.md change `add-app-general-page`, D13). Раздел «About» страницы «General» SHALL показывать лицензию и сторонние уведомления из этих ресурсов, без сети. Лицензии пакетов pub в сборке SHALL показываться из реестра лицензий Flutter (`LicenseRegistry`), без отдельной копии.

#### Scenario: Копия разошлась с корнем
- **WHEN** в `THIRD_PARTY_NOTICES.md` корня добавлена запись, а `apps/codelab_desktop/assets/legal/THIRD_PARTY_NOTICES.md` не обновлён
- **THEN** тест сверки ресурсов app падает и называет файл

#### Scenario: Строка лицензии из ресурса
- **WHEN** раздел «About» развёрнут
- **THEN** строка «License» содержит `MIT` и строку авторского права, совпадающую с третьей строкой `assets/legal/LICENSE`
