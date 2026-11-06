import 'dart:async';

import 'package:codelab_setup/codelab_setup.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'provider_settings_state.dart'
    show ProviderBanner, ProviderBannerAction, ProviderBannerKind;
import 'provider_wizard_view.dart';

export 'provider_settings_state.dart'
    show ProviderBanner, ProviderBannerAction, ProviderBannerKind;
export 'provider_wizard_view.dart';

/// Открывает мастер встроенного агента из баннера соединения (D26).
///
/// Почему порт: сессию настроек и автомат собирает composition root, а баннер
/// принадлежит рабочему месту; он знает только папку проекта сбоя [cwd].
/// Возвращает `null`, если настройки недоступны (нет `CODELAB_HOME`, конфиг не
/// читается); владелец закрывает Cubit после диалога.
typedef EmbeddedWizardOpener =
    Future<ProviderWizardCubit?> Function({required String cwd});

/// Состояние диалога мастера: состояние автомата и то, что к нему добавляет
/// presentation (шаг строки шагов, сводка, баннер конфликта).
///
/// Почему обёртка, а не сам `ProviderSetupState`: конфликт записи возвращает
/// мастер в «Review» с баннером, а `Reviewing` несёт только ошибку правки
/// автомата; пометка «после конфликта» принадлежит диалогу app (spec
/// app-settings «Мастер провайдера в app»). Значения ключа здесь нет: состояния
/// автомата не печатают его (SETUP-1), сводка описывает способ хранения.
final class ProviderWizardState {
  const ProviderWizardState({
    required this.setup,
    required this.stepIndex,
    required this.summary,
    this.reviewNotice,
  });

  /// Состояние автомата моста.
  final ProviderSetupState setup;

  /// Индекс текущего шага в [wizardStepLabels].
  final int stepIndex;

  /// Сводка пройденных шагов (см. `wizardSummaryOf`).
  final List<WizardSummaryRow> summary;

  /// Баннер «Review» после конфликта записи; `null` — баннера нет.
  final String? reviewNotice;

  @override
  String toString() => 'ProviderWizardState($setup)';
}

/// Cubit диалога «Add provider» / «Edit provider» — тонкая обёртка над
/// `ProviderSetupFlow` моста (design.md change `add-provider-setup-ui`, D7,
/// D18, D21).
///
/// Почему: шаги, проверка `/models`, порядок «ключ → конфиг → откат» и тексты
/// ошибок шага принадлежат автомату (один на CLI и app, SETUP-8). Cubit не
/// принимает решений о безопасности: он пересылает события пользователя,
/// публикует состояния, закрывает автомат и считает баннер после записи.
///
/// Для чего: порта `ProviderKeys` и значения ключа Cubit не видит — автомат
/// построила сессия настроек composition root (`ProviderSettingsSession.
/// openWizard`); ключ вводит виджет и передаёт событием `KeySubmitted` внутри
/// `SecretValue`. Cancel и Esc в `Saving` заблокированы (D21): запись нельзя
/// прервать между секретом и конфигом. Поздний результат проверки после
/// Cancel/закрытия автомат отбрасывает по номеру попытки и сам пишет все
/// события `provider_wizard.*` (D18), включая `check_discarded` и `cancelled`;
/// Cubit их не дублирует.
///
/// Как использовать: владелец диалога (страница или баннер) создаёт Cubit,
/// показывает `showProviderWizardDialog`, после закрытия читает [savedBanner]
/// (`null` — записи не было) и вызывает [close]. Закрытие в любом состоянии
/// отменяет идущую проверку и сбрасывает ссылку на значение ключа.
class ProviderWizardCubit extends Cubit<ProviderWizardState> {
  ProviderWizardCubit({
    required ProviderSetupFlow flow,
    required EditableSettings access,
    required String backendId,
    required bool Function() isAgentConnected,
    this.editingId,
    this.forceDefault = false,
  }) : _flow = flow,
       _access = access,
       _backendId = backendId,
       _isAgentConnected = isAgentConnected,
       super(_stateOf(flow.current, backendId, access, conflict: false)) {
    _subscription = _flow.states.listen(_onSetup);
  }

  final ProviderSetupFlow _flow;
  final EditableSettings _access;
  final String _backendId;
  final bool Function() _isAgentConnected;
  late final StreamSubscription<ProviderSetupState> _subscription;

  /// Id редактируемого провайдера; `null` — добавление.
  final String? editingId;

  /// «Make default» нельзя снять (баннер D26, первый запуск CLI).
  final bool forceDefault;

  var _conflict = false;
  ProviderBanner? _savedBanner;

  /// Правка существующего провайдера.
  bool get editing => editingId != null;

  /// Заголовок диалога: `Add provider` или `Edit provider <id>`.
  String get title => editing ? 'Edit provider $editingId' : 'Add provider';

  /// Цель записи «This project only»: слой `projectLocal` из доступа сессии
  /// (D5); `null` — папки проекта нет.
  ConfigTarget? get projectTarget => _access.targets
      .where((target) => target.layer == ConfigLayer.projectLocal)
      .firstOrNull;

  /// Показывать ли переключатель «This project only»: только при добавлении и
  /// только если у доступа есть папка проекта; при правке слой записи —
  /// слой провайдера (D7).
  bool get projectOnlyAvailable => !editing && projectTarget != null;

  /// Можно ли закрыть диалог: в `Saving` нельзя (D21).
  bool get canDismiss => state.setup is! Saving;

  /// Баннер страницы после `ConfigSaved`; `null`, пока записи не было.
  ProviderBanner? get savedBanner => _savedBanner;

  /// Посылает событие автомату. `Cancel` идёт через [cancel], чтобы журнал и
  /// блокировка `Saving` были в одном месте.
  void dispatch(ProviderSetupEvent event) {
    if (event is Cancel) {
      cancel();
      return;
    }
    _flow.dispatch(event);
  }

  /// «Cancel» и Esc: закрывает мастер, кроме состояния `Saving` (D21).
  void cancel() {
    final setup = state.setup;
    if (setup is Saving) {
      // Автомат сам запишет `provider_wizard.event_ignored`.
      _flow.dispatch(const Cancel());
      return;
    }
    if (setup is Done || setup is Cancelled) {
      return;
    }
    _flow.dispatch(const Cancel());
  }

  void _onSetup(ProviderSetupState setup) {
    if (isClosed) {
      return;
    }
    if (setup is SaveFailed && setup.failure.outcome is ConfigConflict) {
      // Конфликт возвращает в «Review» с тем же планом без автоповтора
      // (SETUP-6); сам `SaveFailed` диалогу не показывается.
      _conflict = true;
      _flow.dispatch(const Back());
      return;
    }
    if (setup is! Reviewing) {
      _conflict = false;
    }
    if (setup is Done) {
      _savedBanner = _bannerFor(setup);
    }
    emit(_stateOf(setup, _backendId, _access, conflict: _conflict));
  }

  static ProviderWizardState _stateOf(
    ProviderSetupState setup,
    String backendId,
    EditableSettings access, {
    required bool conflict,
  }) => ProviderWizardState(
    setup: setup,
    stepIndex: wizardStepIndex(setup),
    summary: wizardSummaryOf(setup, backendId: backendId, access: access),
    reviewNotice: conflict && setup is Reviewing
        ? 'Config changed on disk — review and save again'
        : null,
  );

  /// Баннер страницы после записи (D9): без запущенного агента — «Connect»;
  /// при замене ключа — напоминание про «Restart agent» (резолвер агента
  /// держит старое значение).
  ProviderBanner _bannerFor(Done done) {
    if (!_isAgentConnected()) {
      return const ProviderBanner(
        ProviderBannerKind.saved,
        'Saved. Connect to start the agent with the new provider.',
        action: ProviderBannerAction.connect,
      );
    }
    final id = done.plan.providerId;
    return ProviderBanner(
      ProviderBannerKind.saved,
      done.committed.keyReplaced
          ? 'Provider $id saved. The new key is used after Restart agent '
                '(Settings › Connection).'
          : 'Provider $id saved.',
    );
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    // `dispose` отменяет проверку и сбрасывает ссылку на значение ключа.
    await _flow.dispose();
    return super.close();
  }
}
