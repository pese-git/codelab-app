// Тесты правок ревью итерации 4 (change `add-desktop-localization`):
// чистый разрез сообщения по меткам и разбивка строки «Key» карточки
// провайдера (`keyStatusDetail`).

import 'package:codelab_desktop/features/settings/application/message_markers.dart';
import 'package:codelab_desktop/features/settings/application/provider_messages.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:flutter_test/flutter_test.dart';

String _show(List<MessagePart> parts) =>
    parts.map((p) => p.slot == null ? p.text : '<${p.slot}>').join();

void main() {
  group('splitMessage', () {
    test('числа в тексте остаются текстом, метки становятся местами', () {
      final parts = splitMessage((m) => 'a 0600 ${m[1]} 30 с ${m[0]}', 2);

      expect(_show(parts), 'a 0600 <1> 30 с <0>');
    });

    test('метка вне диапазона выводится обычным текстом, без RangeError', () {
      final parts = splitMessage((m) => '${m[0]}-7-', 1);

      expect(_show(parts), '<0>-7-');
    });

    test('без меток всё сообщение — один кусок текста', () {
      expect(_show(splitMessage((m) => 'просто текст', 1)), 'просто текст');
    });
  });

  group('keyStatusDetail', () {
    final en = AppLocalizationsEn();
    final ru = AppLocalizationsRu();
    const stored = KeyInSecretStore(name: 'codelab/a', backendId: 'file');

    test('моно — ровно имя секрета, закрывающая «ёлочка» — хвост', () {
      final detail = keyStatusDetail(ru, stored);

      expect(detail.text, 'В file как «');
      expect(detail.mono, 'codelab/a');
      expect(detail.tail, '»');
      expect(
        '${detail.text}${detail.mono}${detail.tail}',
        'В file как «codelab/a»',
      );
    });

    test('en: хвоста нет', () {
      final detail = keyStatusDetail(en, stored);

      expect(detail.text, 'In file as ');
      expect(detail.mono, 'codelab/a');
      expect(detail.tail, '');
    });

    test('вид без имени: весь текст обычный, моно нет', () {
      final detail = keyStatusDetail(ru, const KeyNone());

      expect(detail.text, 'Без ключа');
      expect(detail.mono, isNull);
      expect(detail.tail, '');
    });
  });
}
