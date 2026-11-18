/// Строки лицензии для раздела «About» (design.md change
/// `add-app-general-page`, D11).
///
/// Заглушка итерации 5 (красные тесты 5.3): реализация — задача 5.4.
library;

/// Название лицензии и строка авторского права из текста `LICENSE`.
final class LicenseSummary {
  const LicenseSummary({required this.name, required this.copyright});

  /// `MIT` из первой строки `MIT License`.
  final String name;

  /// Строка `Copyright (c) …` как в файле.
  final String copyright;
}

/// Разбирает текст `LICENSE`: первая строка и строка `Copyright`.
LicenseSummary licenseSummaryOf(String licenseText) =>
    const LicenseSummary(name: '', copyright: '');
