/// Страница «Keyboard» настроек (заглушка для красных тестов 3.3 и 3.4 change
/// `add-app-keyboard-page`; D5–D9).
///
/// Почему: сочетания app — каталог кита, а страница только показывает его
/// (D2, D6). Cubit и порты не нужны: у страницы нет внешних данных.
///
/// Для чего: таблица «Action · Shortcut · Where» с поиском, только для
/// чтения.
///
/// Как использовать: `buildKeyboardPage` — построитель для
/// `settingsPageBuilders`. Сейчас страница пустая и в сборку не
/// зарегистрирована; поведение и регистрация — задача 3.5.
library;

import 'package:fluent_ui/fluent_ui.dart';

/// Построитель тела страницы для `settingsPageBuilders`.
Widget buildKeyboardPage(BuildContext context) => const KeyboardPage();

class KeyboardPage extends StatelessWidget {
  const KeyboardPage({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
