import 'dart:async';

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/language/app_language_cubit.dart';
import '../../../core/platform/app_language_preferences.dart';
import '../../../l10n/l10n.dart';

/// Тело страницы «General» для таблицы `settingsPageBuilders`.
Widget buildGeneralPage(BuildContext context) => const GeneralPage();

/// Страница настроек «General»: язык интерфейса.
///
/// Почему без своего Cubit-а: единственный владелец языка —
/// `AppLanguageCubit` (`add-desktop-localization`, D2); второй владелец
/// разошёлся бы с ним. Страница только показывает его состояние и передаёт
/// выбор пользователя.
///
/// Для чего: выбор `System | English | Русский` применяется сразу, без
/// перезапуска (spec app-settings «Язык интерфейса app»); сбой записи
/// показывается предупреждением, язык при этом остаётся применённым.
///
/// Как использовать: строится из `settingsPageBuilders`; `AppLanguageCubit`
/// берётся из ближайшего `BlocProvider` (его даёт `CodeLabApp`). Названия
/// `English` и `Русский` — эндонимы, они не переводятся.
class GeneralPage extends StatelessWidget {
  const GeneralPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<AppLanguageCubit>();
    return BlocBuilder<AppLanguageCubit, AppLanguageState>(
      builder: (context, state) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CodeLabText(
            l10n.settingsPageGeneralTitle,
            role: CodeLabTextRole.title,
          ),
          const SizedBox(height: 12),
          if (state.saveFailed) ...[
            // Только типизированный исход: текста исключения нет (D2).
            InfoBar(
              key: const ValueKey('settings-language-save-failed'),
              title: Text(l10n.settingsLanguageSaveFailed),
              severity: InfoBarSeverity.warning,
              // Повтор записи: `RadioGroup` не вызывает `onChanged` для уже
              // выбранного значения, поэтому отдельная кнопка.
              action: Button(
                key: const ValueKey('settings-language-save-retry'),
                onPressed: () => unawaited(cubit.select(state.preference)),
                child: Text(l10n.settingsLanguageSaveRetry),
              ),
            ),
            const SizedBox(height: 12),
          ],
          CodeLabSettingsSection(
            title: l10n.settingsGeneralSectionInterface,
            children: [
              CodeLabSettingsRow(
                key: const ValueKey('settings-general-language'),
                title: l10n.settingsLanguageTitle,
                trailing: RadioGroup<AppLanguagePreference>(
                  groupValue: state.preference,
                  onChanged: (value) {
                    if (value != null) unawaited(cubit.select(value));
                  },
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _option(
                        AppLanguagePreference.system,
                        'settings-language-system',
                        l10n.settingsLanguageSystem,
                      ),
                      _option(
                        AppLanguagePreference.en,
                        'settings-language-en',
                        l10n.settingsLanguageEnglish,
                      ),
                      _option(
                        AppLanguagePreference.ru,
                        'settings-language-ru',
                        l10n.settingsLanguageRussian,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _option(AppLanguagePreference value, String key, String label) =>
      RadioButton<AppLanguagePreference>(
        key: ValueKey(key),
        value: value,
        content: Text(label),
      );
}
