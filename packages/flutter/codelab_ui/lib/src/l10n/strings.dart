import 'package:flutter/widgets.dart';

import 'codelab_localizations.dart';
import 'codelab_localizations_en.dart';

/// Каталог текстов кита для [context] с фолбэком на английский.
///
/// Почему: кит живёт и без делегата `CodeLabLocalizations` — в 45 тестовых
/// `FluentApp`, превью без `FluentApp` и любых хостах без локализации. Там
/// `CodeLabLocalizations.of` возвращает `null`, и виджет не должен падать,
/// а показывать прежний английский (`add-desktop-localization`, D4; spec
/// app-settings «Кит без делегата»).
///
/// Для чего: единственная точка, через которую `lib/src/**` берёт видимый
/// текст. Файл не экспортируется из `codelab_ui.dart`: каталог — внутренняя
/// реализация, публичны только `CodeLabLocalizations` (делегат),
/// `toolPaneTitleOf` и `CodeLabApprovalRisk.labelOf`.
///
/// Как использовать: в `build` — `codeLabStringsOf(context).codeLabActionSend`.
/// Вызов зависит от `Localizations`, поэтому смена языка пересобирает виджет
/// без подписок (D5). Кит не читает `AppLocalizations` app (D4).
CodeLabLocalizations codeLabStringsOf(BuildContext context) =>
    CodeLabLocalizations.of(context) ?? CodeLabLocalizationsEn();
