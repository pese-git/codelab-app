## ADDED Requirements

### Requirement: Onboarding app без dart:io
Код `apps/codelab_desktop/lib/features/onboarding/` НЕ SHALL импортировать `dart:io`: файлы, хранилище секретов и `shared_preferences` onboarding получает только портами (`OnboardingProbe`, `OnboardingPreferences`), а их адаптеры лежат в `lib/app/` и `lib/core/platform/` (SETUP-9; design.md change `add-app-onboarding`, D15). Сторож `codelab_architecture_tests` SHALL проверять это правилом в `test/support/rules.dart`; запрет `package:codelab_setup/io.dart` вне `lib/app/` действует для этого каталога по существующему правилу app.

#### Scenario: dart:io в onboarding
- **WHEN** файл в `apps/codelab_desktop/lib/features/onboarding/application/` импортирует `dart:io`
- **THEN** `melos run guard` сообщает нарушение и называет файл

#### Scenario: IO-барель моста в onboarding
- **WHEN** файл в `apps/codelab_desktop/lib/features/onboarding/presentation/` импортирует `package:codelab_setup/io.dart`
- **THEN** `melos run guard` сообщает нарушение, а тот же импорт в `apps/codelab_desktop/lib/app/onboarding_probe.dart` нарушением не является
