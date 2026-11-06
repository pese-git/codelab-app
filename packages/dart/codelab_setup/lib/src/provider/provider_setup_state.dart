/// Состояния и события мастера провайдера (`dart-agent-and-clients` §12.4.4;
/// design.md change `add-provider-setup-ui`, D7).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show ConfigTarget, SecretBackendInfo;

import 'provider_check.dart';
import 'provider_presets.dart';
import 'provider_setup_committer.dart';
import 'provider_setup_plan.dart';

/// Черновик провайдера, который мастер накапливает от шага к шагу.
///
/// Почему отдельный тип: состояния шагов показывают клиенту сводку пройденного
/// («Type», «Base URL», «Key»), а ключ в черновике — `SecretValue`, который
/// нигде не печатается (SETUP-1). Тело ключа достаётся только при отправке
/// запроса и записи в хранилище.
///
/// Как использовать: клиент читает поля; менять черновик может только автомат.
/// Адрес на экран выводят через [displayBaseUrl]: в [baseUrl] могут быть query и
/// (у правки) userinfo.
final class ProviderDraft {
  const ProviderDraft({
    required this.providerId,
    required this.kind,
    this.preset,
    this.baseUrl,
    this.key,
    this.secretName,
    this.replaceSecret = false,
    this.notVerified,
    this.confirmedInsecureUrl,
    this.model,
  });

  /// Пресет; `null` — правка существующего провайдера.
  final ProviderPreset? preset;

  /// Пусто, пока custom-пресет не получил адрес.
  final String providerId;
  final String kind;
  final String? baseUrl;
  final KeyChoice? key;

  /// Имя секрета плана, см. `ProviderSetupPlan.secretName`.
  final String? secretName;
  final bool replaceSecret;

  /// Вид отказа проверки, пропущенной пользователем (`unreachable`, `timeout`).
  final String? notVerified;

  /// Адрес `http` к нелокальному хосту, подтверждённый пользователем.
  final String? confirmedInsecureUrl;
  final PlannedModel? model;

  /// Адрес для показа: схема, хост, порт и путь без userinfo, query и fragment.
  String? get displayBaseUrl {
    final uri = baseUrl == null ? null : Uri.tryParse(baseUrl!);
    if (uri == null || uri.host.isEmpty) {
      return null;
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    ).toString();
  }

  ProviderDraft copyWith({
    String? providerId,
    String? baseUrl,
    KeyChoice? key,
    bool clearKey = false,
    String? secretName,
    bool? replaceSecret,
    String? notVerified,
    bool clearNotVerified = false,
    String? confirmedInsecureUrl,
    PlannedModel? model,
  }) => ProviderDraft(
    preset: preset,
    providerId: providerId ?? this.providerId,
    kind: kind,
    baseUrl: baseUrl ?? this.baseUrl,
    key: clearKey ? null : key ?? this.key,
    secretName: clearKey ? null : secretName ?? this.secretName,
    replaceSecret: clearKey ? false : replaceSecret ?? this.replaceSecret,
    notVerified: clearNotVerified ? null : notVerified ?? this.notVerified,
    confirmedInsecureUrl: confirmedInsecureUrl ?? this.confirmedInsecureUrl,
    model: model ?? this.model,
  );

  @override
  String toString() => 'ProviderDraft($providerId, $kind)';
}

/// Состояние мастера.
sealed class ProviderSetupState {
  const ProviderSetupState();
}

/// Шаг «API type»: [presets] из таблицы.
final class ChoosingPreset extends ProviderSetupState {
  const ChoosingPreset(this.presets);

  final List<ProviderPreset> presets;

  @override
  String toString() => 'ChoosingPreset';
}

/// Шаг «Base URL». [error] — ошибка шага; [insecureHost] — `http` к нелокальному
/// хосту ждёт подтверждения (`InsecureAddressConfirmed`), привязанного к
/// адресу и сбрасываемого его правкой.
final class EnteringBaseUrl extends ProviderSetupState {
  const EnteringBaseUrl(this.draft, {this.error, this.insecureHost});

  final ProviderDraft draft;
  final String? error;
  final String? insecureHost;

  @override
  String toString() => 'EnteringBaseUrl(${draft.providerId})';
}

/// Шаг «API key source».
///
/// [ready] — порт ответил, есть ли секрет `codelab/<id>`; до этого `KeySubmitted`
/// не принимается. [existingSecret] — имя существующего секрета (тогда шаг
/// предлагает «Use the stored key» и «Replace it»). [canStoreSecret] `false` —
/// бэкенд только для чтения, причина — [readOnlyHint]. [canKeepStored] — есть
/// ключ, который можно оставить. [notice] — пояснение шага (литеральный ключ в
/// файле), [error] — ошибка шага, [suggestedEnvVar] — подсказка переменной.
final class ChoosingKey extends ProviderSetupState {
  const ChoosingKey(
    this.draft, {
    required this.backend,
    required this.ready,
    required this.canStoreSecret,
    required this.canKeepStored,
    this.readOnlyHint,
    this.existingSecret,
    this.error,
    this.notice,
    this.suggestedEnvVar,
  });

  final ProviderDraft draft;
  final SecretBackendInfo backend;
  final bool ready;
  final bool canStoreSecret;
  final bool canKeepStored;
  final String? readOnlyHint;
  final String? existingSecret;
  final String? error;
  final String? notice;
  final String? suggestedEnvVar;

  @override
  String toString() => 'ChoosingKey(${draft.providerId}, ready: $ready)';
}

/// Идёт проверка [attempt]; [probeUrl] — адрес запроса без query и userinfo.
final class Checking extends ProviderSetupState {
  const Checking(this.draft, this.probeUrl, this.attempt);

  final ProviderDraft draft;
  final Uri probeUrl;
  final int attempt;

  @override
  String toString() => 'Checking(#$attempt)';
}

/// Проверка отказала. [elapsed] — длительность попытки (строка `GET [url] →
/// [код] · [n] ms`). [canSkip] — «Save without check» (`unreachable`,
/// `timeout`); [canUseV1] — предложить адрес с `/v1` (`notFound` у
/// OpenAI-совместимого адреса без `/v1`).
final class CheckFailed extends ProviderSetupState {
  const CheckFailed(
    this.draft,
    this.failure,
    this.probeUrl,
    this.elapsed, {
    required this.canSkip,
    required this.canUseV1,
  });

  final ProviderDraft draft;
  final ProviderCheckFailure failure;
  final Uri probeUrl;
  final Duration elapsed;
  final bool canSkip;
  final bool canUseV1;

  @override
  String toString() => 'CheckFailed(${failure.kind.name})';
}

/// Шаг «Model»: [models] пуст — только ручной ввод; [checked] `false` —
/// проверка пропущена. [currentModel] — при правке текущая модель провайдера
/// (модель по умолчанию, иначе первая объявленная): клиент выделяет её как
/// выбранную.
final class ChoosingModel extends ProviderSetupState {
  const ChoosingModel(
    this.draft,
    this.models, {
    required this.checked,
    this.currentModel,
  });

  final ProviderDraft draft;
  final List<RemoteModel> models;
  final bool checked;
  final String? currentModel;

  @override
  String toString() => 'ChoosingModel(${models.length}, checked: $checked)';
}

/// Окно контекста неизвестно: спрашиваем; [suggestedContextWindow] — подсказка
/// (каталог ядра, иначе 32000).
final class EnteringModelDetails extends ProviderSetupState {
  const EnteringModelDetails(
    this.draft,
    this.modelId,
    this.suggestedContextWindow, {
    this.error,
  });

  final ProviderDraft draft;
  final String modelId;
  final int suggestedContextWindow;
  final String? error;

  @override
  String toString() => 'EnteringModelDetails($modelId)';
}

/// Почему план нельзя записать (проверка перед `ConfirmSave`).
enum PlanRefusal {
  /// Провайдер с таким id уже есть в конфиге (появился после конфликта записи
  /// или во втором слое): запись молча перезаписала бы чужого.
  providerExists,

  /// Правится провайдер, которого в свежем снимке уже нет.
  providerMissing,

  /// Файл слоя записи не читается: основы для записи нет.
  layerUnreadable,

  /// Правится провайдер не из слоёв `user`/`projectLocal` (слой 3, `--config`,
  /// окружение): правкой файла его не изменить (то же правило, что у Remove).
  notEditable,

  /// Листья провайдера лежат в нескольких слоях: один `apply` пишет один слой.
  multipleLayers,
}

/// Откуда открыт мастер (поле `entry` события `provider_wizard.started`, D18).
enum ProviderWizardEntry {
  /// Страница Providers app.
  app('app'),

  /// Баннер «Add provider» соединения (D26).
  banner('banner'),

  /// Команды и REPL CLI.
  cli('cli'),

  /// Мастер первого запуска CLI.
  firstRun('first_run'),

  /// Флаги `codelab provider add`.
  flags('flags');

  const ProviderWizardEntry(this.wire);

  /// Значение в журнале.
  final String wire;
}

/// Шаг «Review»: [warnings] (`Not verified: <kind>`), [error] — ошибка правки,
/// [refusal] — типизированный отказ записи плана (запись не выполнялась).
final class Reviewing extends ProviderSetupState {
  const Reviewing(this.plan, this.warnings, {this.error, this.refusal});

  final ProviderSetupPlan plan;
  final List<String> warnings;
  final String? error;
  final PlanRefusal? refusal;

  @override
  String toString() => 'Reviewing($plan)';
}

/// Идёт запись.
final class Saving extends ProviderSetupState {
  const Saving(this.plan);

  final ProviderSetupPlan plan;

  @override
  String toString() => 'Saving($plan)';
}

/// Конфиг не записан; [failure] несёт исход, вид отката и признак «ключ уже
/// заменён».
final class SaveFailed extends ProviderSetupState {
  const SaveFailed(this.plan, this.failure);

  final ProviderSetupPlan plan;
  final ProviderConfigNotSaved failure;

  @override
  String toString() => 'SaveFailed($failure)';
}

/// Записано. [plan] без значения ключа (см. `withoutSecretValue`);
/// [committed] — `keyReplaced` и `ConfigSaved` (ключи «after restart»).
final class Done extends ProviderSetupState {
  const Done(this.plan, this.committed);

  final ProviderSetupPlan plan;
  final ProviderCommitted committed;

  @override
  String toString() => 'Done($plan)';
}

/// Мастер отменён.
final class Cancelled extends ProviderSetupState {
  const Cancelled();

  @override
  String toString() => 'Cancelled';
}

/// Событие мастера. Событие не к месту состояния игнорируется и пишется в
/// журнал (`provider_wizard.event_ignored`).
sealed class ProviderSetupEvent {
  const ProviderSetupEvent();
}

final class PresetChosen extends ProviderSetupEvent {
  const PresetChosen(this.presetId);

  final String presetId;
}

final class BaseUrlSubmitted extends ProviderSetupEvent {
  const BaseUrlSubmitted(this.text);

  final String text;

  @override
  String toString() => 'BaseUrlSubmitted';
}

/// Пользователь подтвердил `http` к адресу [text], который сейчас в поле.
///
/// Почему с текстом: подтверждение привязано к адресу. Если поле успели
/// изменить, подтверждение не уходит на прежний адрес: несовпадающий текст
/// разбирается как `BaseUrlSubmitted`.
final class InsecureAddressConfirmed extends ProviderSetupEvent {
  const InsecureAddressConfirmed(this.text);

  final String text;

  @override
  String toString() => 'InsecureAddressConfirmed';
}

/// Выбор ключа. [replaceExisting] — явное «Replace it» при существующем секрете.
final class KeySubmitted extends ProviderSetupEvent {
  const KeySubmitted(this.choice, {this.replaceExisting = false});

  final KeyChoice choice;
  final bool replaceExisting;

  @override
  String toString() => 'KeySubmitted(${choice.runtimeType})';
}

final class RetryCheck extends ProviderSetupEvent {
  const RetryCheck();
}

/// «Save without check»; [confirmed] `false` (подтверждения не было) игнорируется
/// (SETUP-4).
final class SkipCheck extends ProviderSetupEvent {
  const SkipCheck({required this.confirmed});

  final bool confirmed;
}

/// Вариант с `/v1` после `notFound` (артборд `Wizard`).
final class UseV1Address extends ProviderSetupEvent {
  const UseV1Address();
}

final class ModelChosen extends ProviderSetupEvent {
  const ModelChosen(this.modelId);

  final String modelId;
}

final class ModelEnteredManually extends ProviderSetupEvent {
  const ModelEnteredManually(this.modelId);

  final String modelId;
}

final class ModelDetailsSubmitted extends ProviderSetupEvent {
  const ModelDetailsSubmitted({
    required this.contextWindow,
    this.maxOutputTokens,
  });

  final int contextWindow;
  final int? maxOutputTokens;
}

/// Правка на шаге «Review»: id, «Make default», цель записи.
final class ReviewEdited extends ProviderSetupEvent {
  const ReviewEdited({this.providerId, this.makeDefault, this.target});

  final String? providerId;
  final bool? makeDefault;
  final ConfigTarget? target;
}

final class ConfirmSave extends ProviderSetupEvent {
  const ConfirmSave();
}

final class Back extends ProviderSetupEvent {
  const Back();
}

final class Cancel extends ProviderSetupEvent {
  const Cancel();
}
