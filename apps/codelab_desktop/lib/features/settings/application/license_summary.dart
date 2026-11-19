/// Строки лицензии для раздела «About» (design.md change
/// `add-app-general-page`, D11).
library;

/// Название лицензии и строка авторского права из текста `LICENSE`.
final class LicenseSummary {
  const LicenseSummary({required this.name, required this.copyright});

  /// `MIT` из первой строки `MIT License`; пусто, если текст пуст.
  final String name;

  /// Строка `Copyright (c) …` как в файле; пусто, если её нет.
  final String copyright;
}

/// Разбирает текст `LICENSE`: имя — первая строка без слова `License`, права
/// — первая строка, начинающаяся с `Copyright`.
///
/// Почему разбор, а не копия строк в коде: текст лицензии один (ресурс
/// `assets/legal/LICENSE`, D13), и строка «License» не должна разойтись с ним.
/// Не бросает: нечитаемый текст даёт пустые поля.
LicenseSummary licenseSummaryOf(String licenseText) {
  final lines = licenseText.split('\n').map((l) => l.trimRight()).toList();
  final first = lines.isEmpty ? '' : lines.first.trim();
  final name = first.replaceFirst(RegExp(r'\s*License$'), '').trim();
  final copyright = lines.firstWhere(
    (l) => l.startsWith('Copyright'),
    orElse: () => '',
  );
  return LicenseSummary(name: name, copyright: copyright);
}
