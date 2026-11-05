import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:codelab_client_core/codelab_client_core.dart'
    show
        ConnectionProfile,
        DraftAccepted,
        DraftRejected,
        EnvToken,
        NewSecretToken,
        NoToken,
        ProbeCancellation,
        ProfileCommitter,
        ProfileDraft,
        ProfileDraftField,
        ProfileDraftIssue,
        ProfileDraftIssueCode,
        ProfileKind,
        ProfileProbe,
        ProfileProbeOutcome,
        ProfileRejected,
        ProfileSaveFailed,
        ProfileSaveFailedReason,
        ProfileSaved,
        ProfileSecretBackend,
        ProfileSecrets,
        ProfileStore,
        Reachable,
        SecretText,
        StdioProfile,
        StoredSecretToken,
        WebSocketProfile,
        isValidProfileId,
        ownTokenSecretName,
        selectableProfileTokenSecrets,
        suggestProfileId;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../core/platform/connection_preferences.dart';
import 'add_profile_state.dart';
import 'probe_outcome_view.dart';
import 'profile_view.dart'
    show
        EnvTokenView,
        NoTokenView,
        ProfileTokenView,
        SecretTokenView,
        profileOrigin;

export 'add_profile_state.dart';
export 'probe_outcome_view.dart';

/// Имя переменной токена по умолчанию, как у CLI (D13).
const defaultTokenEnvName = 'CODELAB_AGENT_TOKEN';

/// Текст общего сбоя записи: без `toString()` исключения (D17).
const _saveFailedMessage = 'Could not save the profile. Try again.';

/// Текст сбоя записи секрета, когда хранилище не назвало причину (D13).
const _secretFailedMessage = 'Could not store the token. Try again.';

/// Форма «Add connection profile»: черновик, проверка и сохранение.
///
/// Почему отдельный Cubit: форма сложная (тип, имя и id, поля stdio или
/// WebSocket, проверка, подтверждение, запись), и её состояние — не состояние
/// страницы «Connection» и не `WorkspaceState` (`state-management.md` §63,
/// §64; design.md change `add-app-settings-shell`, D4, D12). Правила черновика
/// (`ProfileDraft`) и проверка (`ProfileProbe`) живут в kit; здесь только их
/// оркестровка и тексты для экрана.
///
/// Для чего: единственный источник того, что показывает диалог — [state] —
/// и единственное место, где диалог пишет в `profiles.json` и в
/// `codelab.connection.default_profile`. Текущее подключение окна он не
/// меняет: «Connect» — действие строки страницы (D5).
///
/// Как использовать: composition root создаёт Cubit на каждое открытие
/// диалога (`createAddProfileCubit`), диалог зовёт [start], затем методы
/// правки, [testConnection], [confirmPlaintextProbe], [save] и [confirmPlaintext]. Закрытие диалога
/// закрывает Cubit: идущая проверка отменяется, её транспорт закрывается, а
/// поздний исход отбрасывается с событием `connection_profile.probe_discarded`
/// (AGENTS.md §9, §12). Переменная токена проверяется только на «задана ли» по
/// [environment] — значение не читается, не хранится и не показывается (D13).
/// Токен хранилища секретов (design.md change `add-provider-setup-ui`, D13,
/// D14): «Use stored secret» хранит только имя, «Store a new token» держит
/// значение в `SecretText` до записи и забывает его при закрытии; запись
/// «секрет → профиль» с откатом выполняет `ProfileCommitter`.
/// События журнала — по D17 и D18: без адреса, имени переменной и секрета,
/// значений и текстов исключений.
class AddProfileCubit extends Cubit<AddProfileState> {
  AddProfileCubit({
    required ProfileStore store,
    required Future<ProfileSecrets> Function() openSecrets,
    required ConnectionPreferences preferences,
    required ProfileProbe probe,
    required List<ProfileKind> kinds,
    required Map<String, String> environment,
    required String Function() projectDirectory,
    String? profilesPath,
    Logger? logger,
  }) : _store = store,
       _openSecrets = openSecrets,
       _profilesPath = profilesPath,
       _preferences = preferences,
       _probe = probe,
       _environment = environment,
       _projectDirectory = projectDirectory,
       _logger = logger,
       _kind = _initialKind(kinds),
       _kinds = List.unmodifiable(kinds),
       super(const OpeningSecrets());

  final ProfileStore _store;

  /// Фабрика открытия хранилища секретов: диалог открывает его заново при
  /// каждом показе, чтобы правка `secrets.backend` применялась без
  /// перезапуска (ревью итерации 1, design.md change `add-provider-setup-ui`,
  /// D3). Пока оно открывается, состояние — [OpeningSecrets].
  final Future<ProfileSecrets> Function() _openSecrets;

  /// Хранилище этого диалога: задаётся в [start], до него формы нет.
  late ProfileSecrets _secrets;
  late ProfileCommitter _committer;
  final ConnectionPreferences _preferences;
  final ProfileProbe _probe;

  /// Окружение app: читается только «задана ли переменная» (D13).
  final Map<String, String> _environment;
  final String Function() _projectDirectory;
  final Logger? _logger;
  final List<ProfileKind> _kinds;
  final String? _profilesPath;

  /// Путь файла профилей для подзаголовка диалога (D20).
  ///
  /// Почему здесь: подсказка «Saved to …» должна называть настоящий файл
  /// (при заданном `CODELAB_HOME` он не `~/.codelab`), а виджет окружения не
  /// читает. Путь из composition root; под `HOME` (или `USERPROFILE`) он
  /// сокращается до `~/…`. Без пути — путь по умолчанию из артборда.
  String get profilesPathLabel {
    final path = _profilesPath;
    if (path == null) {
      return '~/.codelab/profiles.json';
    }
    // Сокращение до `~` по правилам разделителя ОС (`package:path`): на Windows
    // это `\`, и `startsWith('$home/')` не сработал бы.
    final home = _environment['HOME'] ?? _environment['USERPROFILE'];
    if (home != null && home.isNotEmpty && p.isWithin(home, path)) {
      return '~${p.separator}${p.relative(path, from: home)}';
    }
    return path;
  }

  /// Тип открытой формы; нужен «Add another» после сохранения.
  ProfileKind _kind;

  /// Id сохранённых профилей: занятость id проверяет `ProfileDraft`.
  List<String> _existingIds = const [];

  /// Всё, что записано за жизнь диалога (M1): «Add another» даёт несколько
  /// профилей, а страница отмечает каждый.
  final _saved = <SavedProfile>[];

  /// Профили, записанные за жизнь диалога, в порядке записи.
  List<SavedProfile> get savedProfiles => List.unmodifiable(_saved);

  /// Комбинация URL и токена, для которой пользователь уже подтвердил
  /// `ws://` (перед проверкой или перед записью): одно подтверждение на одну
  /// комбинацию (решение пользователя 2026-11-05). Сравнивается, а не
  /// сбрасывается: правка URL или токена даёт другой ключ.
  String? _plaintextConfirmed;

  /// Имена хранилища для «Use stored secret»; читаются при открытии формы,
  /// значения не читаются (D14).
  List<String> _secretNames = const [];

  /// Последнее выбранное имя «Use stored secret»: возврат к варианту не
  /// сбрасывает выбор.
  String? _storedChoice;

  /// Ошибка у поля токена от отказа записи («секрет уже есть»); живёт до
  /// следующей правки.
  String? _tokenSubmitError;

  /// Был ли выбранный секрет в хранилище в момент проверки: «rejected the
  /// token» допустим, только если токен действительно ушёл на сервер (D12).
  /// `null` — проверка не шла; тогда берётся снимок имён при открытии формы.
  bool? _storedFound;

  /// Номер последней начатой проверки (`operation_id`).
  var _probeSeq = 0;

  /// Номер проверки, исход которой ещё нужен; `null` — такой нет.
  int? _activeProbe;
  ProbeCancellation? _cancellation;

  /// Загружает id профилей файла для проверки занятости.
  ///
  /// Нечитаемый файл не мешает форме открыться: страница не даёт открыть
  /// диалог при битом файле, а повторная проверка идёт при [save].
  Future<void> start() async {
    final opened = await _openSecrets();
    final ids = await _loadIds() ?? const <String>[];
    if (isClosed || state is! OpeningSecrets) {
      // Поздний результат после закрытия диалога отбрасывается.
      return;
    }
    _secrets = opened;
    _committer = ProfileCommitter(store: _store, secrets: opened);
    _existingIds = ids;
    _secretNames = await _loadSecretNames();
    if (isClosed) {
      return;
    }
    emit(
      Editing(
        _compose(
          draft: ProfileDraft(kind: _initialKind(_kinds)),
          touched: false,
        ),
      ),
    );
  }

  void selectKind(ProfileKind kind) {
    if (!_kinds.contains(kind) || kind == _kind) {
      return;
    }
    _kind = kind;
    _plaintextConfirmed = null;
    // Токен есть только у WebSocket: при смене типа значение не должно
    // висеть в черновике stdio-профиля (ревью итерации 1).
    _change(
      (form) => form.draft.copyWith(
        kind: kind,
        token: kind == ProfileKind.stdio ? const NoToken() : form.draft.token,
      ),
    );
  }

  void setLabel(String value) => _change((form) {
    final draft = form.draft.copyWith(label: value);
    return form.idEdited ? draft : draft.copyWith(id: suggestProfileId(value));
  });

  /// Правка id; пустое значение возвращает id, следующий за именем.
  void setId(String value) => _change(
    (form) => value.isEmpty
        ? form.draft.copyWith(id: suggestProfileId(form.draft.label))
        : form.draft.copyWith(id: value),
    idEdited: (form) => value.isNotEmpty,
  );

  void setCommand(String value) =>
      _change((form) => form.draft.copyWith(command: value));

  void setArgs(String value) =>
      _change((form) => form.draft.copyWith(args: value));

  void setRunInProject(bool value) =>
      _change((form) => form.draft.copyWith(runInProjectDirectory: value));

  void setEnv(String value) =>
      _change((form) => form.draft.copyWith(env: value));

  // Любая правка URL или токена снимает подтверждение `ws://`: «A → B → A»
  // спрашивает снова (N3).
  void setUrl(String value) {
    _plaintextConfirmed = null;
    _change((form) => form.draft.copyWith(url: value));
  }

  void selectTokenNone() {
    _plaintextConfirmed = null;
    _change((form) => form.draft.copyWith(token: const NoToken()));
  }

  void selectTokenEnv() {
    _plaintextConfirmed = null;
    _change((form) => form.draft.copyWith(token: EnvToken(form.tokenEnvName)));
  }

  /// «Use stored secret»: первое имя хранилища либо прежний выбор. Без имён
  /// вариант недоступен (`storedSecretsHint`), вызов ничего не делает.
  void selectTokenStored() {
    if (_secretNames.isEmpty) {
      return;
    }
    _plaintextConfirmed = null;
    final name = _storedChoice != null && _secretNames.contains(_storedChoice)
        ? _storedChoice!
        : _secretNames.first;
    _change((form) => form.draft.copyWith(token: StoredSecretToken(name)));
  }

  /// Выбор имени в списке «Use stored secret»; неизвестное имя игнорируется.
  void setStoredSecret(String name) {
    if (!_secretNames.contains(name)) {
      return;
    }
    _plaintextConfirmed = null;
    _storedChoice = name;
    _change((form) => form.draft.copyWith(token: StoredSecretToken(name)));
  }

  /// «Store a new token»: пустое значение; предыдущий ввод не возвращается.
  /// В хранилище только для чтения вариант недоступен — вызов ничего не
  /// делает (D3).
  void selectTokenNew() {
    if (_editableForm() == null || !_secrets.backend.writable) {
      return;
    }
    _plaintextConfirmed = null;
    _change(
      (form) =>
          form.draft.copyWith(token: NewSecretToken(const SecretText(''))),
    );
  }

  /// Ввод значения нового токена. Правка сбрасывает подтверждение `ws://`,
  /// даже если значение затем вернули к прежнему (spec app-settings).
  void setNewToken(String value) {
    if (_editableForm()?.draft.token is! NewSecretToken) {
      return;
    }
    _plaintextConfirmed = null;
    _change(
      (form) => form.draft.copyWith(token: NewSecretToken(SecretText(value))),
    );
  }

  void setTokenEnvName(String value) {
    _plaintextConfirmed = null;
    _applyTokenEnvName(value);
  }

  void _applyTokenEnvName(String value) => _change(
    (form) => form.draft.token is EnvToken
        ? form.draft.copyWith(token: EnvToken(value))
        : form.draft,
    tokenEnvName: value,
  );

  void setUseByDefault(bool value) {
    final form = _editableForm();
    if (form == null || value == form.useByDefault) {
      return;
    }
    // Флажок не меняет черновик, поэтому исход проверки остаётся (и идущая
    // проверка не отменяется).
    final next = _compose(
      draft: form.draft,
      useByDefault: value,
      idEdited: form.idEdited,
      tokenEnvName: form.tokenEnvName,
      touched: form.touched,
      probe: form.probe,
    );
    emit(switch (state) {
      Probing(:final probeId) => Probing(next, probeId: probeId),
      _ => Editing(next),
    });
  }

  /// «Test connection»: один `initialize` без сессии (D12).
  ///
  /// Повторный вызов и любая правка отменяют идущую проверку.
  Future<void> testConnection() async {
    final form = _editableForm();
    if (form == null || !form.canTest) {
      return;
    }
    // Проверке не нужны имя и id: подставляем безопасные, чтобы `toProfile`
    // не отклонил черновик из-за них.
    final result = form.draft
        .copyWith(id: 'probe', label: 'probe')
        .toProfile(const []);
    if (result is! DraftAccepted) {
      return;
    }
    // Токен уходит в первом же рукопожатии, поэтому `ws://` к другой машине с
    // токеном проверяется только после «Test anyway». Без токена проверка
    // ничего секретного не отправляет и идёт сразу.
    if (_hasToken(form.draft) &&
        _hasPlaintextWarning(result) &&
        _plaintextConfirmed != _plaintextKey(form.draft)) {
      _cancelProbe();
      emit(
        ConfirmingPlaintextProbe(form, message: _plaintextMessage(form.draft)),
      );
      return;
    }
    await _startProbe(form, result.profile);
  }

  /// «Test anyway» после предупреждения о `ws://` с токеном.
  Future<void> confirmPlaintextProbe() async {
    final current = state;
    if (current is! ConfirmingPlaintextProbe) {
      return;
    }
    final form = current.form;
    final result = form.draft
        .copyWith(id: 'probe', label: 'probe')
        .toProfile(const []);
    if (result is! DraftAccepted) {
      return;
    }
    _plaintextConfirmed = _plaintextKey(form.draft);
    await _startProbe(form, result.profile);
  }

  /// Значение нового токена для проверки (из памяти формы, до записи в
  /// хранилище, D13); у других вариантов токен читает сам `ProfileProbe`.
  static SecretText? _probeToken(ProfileDraft draft) {
    final token = draft.token;
    return token is NewSecretToken && !token.value.isEmpty ? token.value : null;
  }

  Future<void> _startProbe(
    AddProfileForm form,
    ConnectionProfile profile,
  ) async {
    _cancelProbe();
    final probeId = ++_probeSeq;
    final cancellation = ProbeCancellation();
    _activeProbe = probeId;
    _cancellation = cancellation;
    // Id черновика фиксируется на старте: к концу проверки форма могла
    // смениться (D17, N2). Пустой id в событие не попадает.
    final draftId = form.draft.id.trim();
    final idContext = {if (draftId.isNotEmpty) 'profile_id': draftId};
    _logger?.info(
      'connection_profile.probe_started',
      context: {
        'operation_id': probeId,
        ...idContext,
        'type': _typeOf(profile),
      },
    );
    emit(
      Probing(
        _compose(
          draft: form.draft,
          useByDefault: form.useByDefault,
          idEdited: form.idEdited,
          tokenEnvName: form.tokenEnvName,
          touched: form.touched,
          probe: null,
        ),
        probeId: probeId,
      ),
    );

    final stopwatch = Stopwatch()..start();
    final outcome = await _probe.probe(
      profile,
      projectDirectory: _projectDirectory(),
      cancellation: cancellation,
      token: _probeToken(form.draft),
    );
    // Поздний исход старой проверки, проверки после `close()` и отменённой
    // проверки (`null`) формы не меняет (AGENTS.md §9).
    if (isClosed || _activeProbe != probeId || outcome == null) {
      _logger?.debug(
        'connection_profile.probe_discarded',
        context: {'operation_id': probeId, ...idContext},
      );
      return;
    }
    // Нашёлся ли секрет — только для проверки, чей исход ещё нужен: поздний
    // исход не должен менять `_storedFound` актуальной формы.
    final draftToken = form.draft.token;
    final storedFound = draftToken is StoredSecretToken
        ? await _isSetOrFalse(draftToken.name)
        : null;
    if (isClosed || _activeProbe != probeId) {
      _logger?.debug(
        'connection_profile.probe_discarded',
        context: {'operation_id': probeId, ...idContext},
      );
      return;
    }
    _storedFound = storedFound;
    _activeProbe = null;
    _cancellation = null;
    _logger?.info(
      'connection_profile.probe_finished',
      context: {
        'operation_id': probeId,
        ...idContext,
        'outcome': probeOutcomeName(outcome),
        'duration_ms': stopwatch.elapsedMilliseconds,
      },
    );
    final current = state;
    if (current is Probing && current.probeId == probeId) {
      emit(
        Editing(
          _compose(
            draft: current.form.draft,
            useByDefault: current.form.useByDefault,
            idEdited: current.form.idEdited,
            tokenEnvName: current.form.tokenEnvName,
            touched: current.form.touched,
            probe: outcome,
          ),
        ),
      );
    }
  }

  /// «Save» / «Save without test».
  ///
  /// Правила проверяются заново на свежем списке id: другой процесс (CLI)
  /// мог занять id, пока диалог был открыт (корневой `AGENTS.md` §2, п. 3).
  /// В `Saving` форма переходит синхронно, до чтения файла: второй клик и
  /// правка поля во время чтения не дадут второй записи или другого
  /// черновика (`_editableForm` в `Saving` пуст).
  Future<void> save() async {
    final form = _editableForm();
    if (form == null || state is Probing) {
      return;
    }
    if (!form.canSave) {
      // Пользователь нажал «Save» на неполной форме: показываем ошибки.
      emit(Editing(_recompute(form, touched: true)));
      return;
    }
    emit(Saving(form));
    final ids = await _loadIds();
    if (isClosed || state is! Saving) {
      return;
    }
    if (ids == null) {
      _failSave(form, form.draft.id, const FormatException());
      return;
    }
    _existingIds = ids;
    switch (form.draft.toProfile(ids)) {
      case DraftRejected():
        emit(Editing(_recompute(form, touched: true)));
      case DraftAccepted(:final warnings):
        if (_plaintextConfirmed != _plaintextKey(form.draft) &&
            warnings.any(
              (issue) => issue.code == ProfileDraftIssueCode.plaintextToRemote,
            )) {
          emit(
            ConfirmingPlaintext(form, message: _plaintextMessage(form.draft)),
          );
          return;
        }
        await _commit(form);
    }
  }

  /// «Save anyway» после предупреждения о `ws://`.
  ///
  /// Список id читается заново, как в [save]: подтверждение могло висеть
  /// долго, и профиль с тем же id мог появиться в файле (CLI) — перезаписывать
  /// его нельзя (корневой `AGENTS.md` §2, п. 3).
  Future<void> confirmPlaintext() async {
    final current = state;
    if (current is! ConfirmingPlaintext) {
      return;
    }
    final form = current.form;
    _plaintextConfirmed = _plaintextKey(form.draft);
    emit(Saving(form));
    final ids = await _loadIds();
    if (isClosed || state is! Saving) {
      return;
    }
    if (ids == null) {
      _failSave(form, form.draft.id, const FormatException());
      return;
    }
    _existingIds = ids;
    switch (form.draft.toProfile(ids)) {
      case DraftRejected():
        emit(Editing(_recompute(form, touched: true)));
      case DraftAccepted():
        await _commit(form);
    }
  }

  /// «Add another»: пустая форма того же типа.
  void addAnother() {
    final current = state;
    if (current is! Saved) {
      return;
    }
    _existingIds = [..._existingIds, current.profileId];
    // Новый профиль — новое подтверждение, даже при том же URL и токене.
    _plaintextConfirmed = null;
    _tokenSubmitError = null;
    emit(Editing(_compose(draft: ProfileDraft(kind: _kind), touched: false)));
  }

  @override
  Future<void> close() {
    // Закрытие диалога отменяет идущую проверку: процесс агента завершается, а
    // исход отбрасывается (spec «Закрытие во время проверки»).
    _cancelProbe();
    _forgetNewToken();
    return super.close();
  }

  /// Черновик забывает значение нового токена при закрытии диалога (D13):
  /// состояние Cubit-а иначе хранило бы `SecretText` до сборки мусора.
  void _forgetNewToken() {
    final current = state;
    if (isClosed || current is! AddProfileInProgress) {
      return;
    }
    final form = current.form;
    if (form.draft.token is! NewSecretToken) {
      return;
    }
    final cleared = _compose(
      draft: form.draft.copyWith(token: NewSecretToken(const SecretText(''))),
      useByDefault: form.useByDefault,
      idEdited: form.idEdited,
      tokenEnvName: form.tokenEnvName,
      touched: form.touched,
    );
    // Запись идёт и после закрытия: значение уже у `ProfileCommitter`, а в
    // состоянии `Saving` оно забывается так же, как в `Editing`.
    if (current is Saving) {
      emit(Saving(cleared));
      return;
    }
    emit(Editing(cleared));
  }

  /// Правка поля: отменяет проверку, сбрасывает её исход и подтверждение.
  void _change(
    ProfileDraft Function(AddProfileForm form) edit, {
    bool Function(AddProfileForm form)? idEdited,
    String? tokenEnvName,
  }) {
    final form = _editableForm();
    if (form == null) {
      return;
    }
    _cancelProbe();
    // Любая правка снимает ошибку отказа записи у поля токена и результат
    // проверки секрета.
    _tokenSubmitError = null;
    _storedFound = null;
    emit(
      Editing(
        _compose(
          draft: edit(form),
          useByDefault: form.useByDefault,
          idEdited: idEdited?.call(form) ?? form.idEdited,
          tokenEnvName: tokenEnvName ?? form.tokenEnvName,
          touched: true,
          probe: null,
        ),
      ),
    );
  }

  /// Форма, которую можно править: все состояния, кроме записи и итога.
  AddProfileForm? _editableForm() => switch (state) {
    OpeningSecrets() || Saving() || Saved() => null,
    AddProfileInProgress(:final form) => form,
  };

  void _cancelProbe() {
    _activeProbe = null;
    _cancellation?.cancel();
    _cancellation = null;
  }

  /// Запись через `ProfileCommitter`: секрет (если «Store a new token»),
  /// затем профиль; отказ профиля откатывает созданный секрет (D13).
  Future<void> _commit(AddProfileForm form) async {
    // `save` и `confirmPlaintext` уже перевели форму в `Saving`.
    if (state is! Saving) {
      emit(Saving(form));
    }
    final draftId = form.draft.id.trim();
    final newToken = form.draft.token is NewSecretToken;
    final result = await _committer.save(form.draft);
    if (isClosed) {
      // Профиль мог записаться уже после закрытия диалога: страница отметит
      // его по `savedProfiles` (M1).
      if (result is ProfileSaved) {
        _saved.add((profileId: result.profile.id, probe: _probeOf(form)));
      }
      return;
    }
    switch (result) {
      case ProfileSaved(:final profile):
        await _afterSaved(form, profile, newToken: newToken);
      case ProfileRejected(:final issues):
        // Id мог занять другой процесс (CLI) или секрет с таким именем уже
        // лежит в хранилище: ничего не записано, форма остаётся с ошибкой.
        final ids = await _loadIds();
        if (isClosed) {
          return;
        }
        if (ids != null) {
          _existingIds = ids;
        }
        final exists = issues.any(
          (issue) => issue.code == ProfileDraftIssueCode.tokenSecretExists,
        );
        if (exists) {
          _tokenSubmitError =
              'A stored token ${ownTokenSecretName(draftId)} already exists '
              'in ${_secrets.backend.id}. Choose it with "Use stored secret" '
              'or remove it with codelab secret delete.';
        }
        emit(Editing(_recompute(form, touched: true)));
      case ProfileSaveFailed():
        _failCommit(form, draftId, result, newToken: newToken);
    }
  }

  Reachable? _probeOf(AddProfileForm form) {
    final probe = form.probe;
    return probe is Reachable ? probe : null;
  }

  /// Профиль записан: ключ умолчания, журнал и экран «Profile saved».
  Future<void> _afterSaved(
    AddProfileForm form,
    ConnectionProfile profile, {
    required bool newToken,
  }) async {
    // Секрет создан этим сохранением, только если профиль ссылается на
    // собственное имя `codelab/profiles/<id>/token` и выбран «Store a new
    // token»: «Use stored secret» с тем же именем секрета не создаёт.
    final created =
        newToken &&
        profile is WebSocketProfile &&
        profile.tokenRef == 'secret:${ownTokenSecretName(profile.id)}';
    if (created) {
      _logger?.info(
        'connection_profile.token_stored',
        context: {'profile_id': profile.id, 'backend': _secrets.backend.id},
      );
    }
    var defaulted = false;
    if (form.useByDefault) {
      try {
        await _preferences.saveDefaultProfileId(profile.id);
        defaulted = true;
        _logger?.info(
          'connection_profile.default_changed',
          context: {'profile_id': profile.id},
        );
      } on Object catch (error) {
        // Профиль уже записан: повторять «Save» нельзя (id занят), поэтому
        // экран «Profile saved» не обещает умолчание.
        _logger?.warning(
          'connection_profile.save_failed',
          context: {
            'profile_id': profile.id,
            'error_type': error.runtimeType.toString(),
            'stage': 'default',
          },
        );
      }
    }
    final probe = _probeOf(form);
    _logger?.info(
      'connection_profile.saved',
      context: {
        'profile_id': profile.id,
        'type': _typeOf(profile),
        'token': _tokenKindOf(profile),
        'tested': probe != null,
      },
    );
    // Профиль записан, даже если диалог уже закрыт: страница отметит его по
    // `savedProfiles` (M1).
    _saved.add((profileId: profile.id, probe: probe));
    if (isClosed) {
      return;
    }
    emit(
      Saved(
        profileId: profile.id,
        label: profile.label,
        probe: probe,
        useByDefault: defaulted,
      ),
    );
  }

  /// Отказ записи: тексты без значения токена и без `toString()` исключения,
  /// в журнале — только имя типа (D17, D18).
  void _failCommit(
    AddProfileForm form,
    String profileId,
    ProfileSaveFailed failure, {
    required bool newToken,
  }) {
    final orphan = failure.orphanedSecret;
    final String errorType;
    final String message;
    switch (failure.reason) {
      case ProfileSaveFailedReason.secretReadOnly:
        errorType = 'SecretReadOnly';
        message = failure.message;
      case ProfileSaveFailedReason.secretWrite:
        errorType = failure.errorType ?? 'SecretWriteFailed';
        message = _secretFailedMessage;
      case ProfileSaveFailedReason.profileWrite:
        errorType = failure.errorType ?? 'ProfileSaveFailed';
        message = orphan == null
            ? _saveFailedMessage
            : 'The profile was not saved; the token stays in '
                  '${_secrets.backend.id} as $orphan. Remove it with codelab '
                  'secret delete $orphan.';
        if (newToken) {
          if (orphan == null) {
            _logger?.warning(
              'connection_profile.token_rollback',
              context: {
                'profile_id': profileId,
                'backend': _secrets.backend.id,
              },
            );
          } else {
            _logger?.warning(
              'connection_profile.token_rollback_failed',
              context: {
                'profile_id': profileId,
                'backend': _secrets.backend.id,
                'error_type': 'SecretDeleteFailed',
              },
            );
          }
        }
    }
    _logger?.warning(
      'connection_profile.save_failed',
      context: {
        'profile_id': profileId,
        'error_type': errorType,
        // Сбой записи самого профиля; сбой ключа умолчания — `default` (D17).
        'stage': 'profile',
      },
    );
    emit(SaveFailed(form, message: message));
  }

  void _failSave(AddProfileForm form, String profileId, Object error) {
    _logger?.warning(
      'connection_profile.save_failed',
      context: {
        'profile_id': profileId,
        'error_type': error.runtimeType.toString(),
        // Сбой записи самого профиля; сбой ключа умолчания — `default` (D17).
        'stage': 'profile',
      },
    );
    emit(SaveFailed(form, message: _saveFailedMessage));
  }

  Future<bool> _isSetOrFalse(String name) async {
    try {
      return await _secrets.isSet(name);
    } on Object {
      return false;
    }
  }

  /// Имена хранилища для «Use stored secret»; нечитаемое хранилище — пусто
  /// (вариант неактивен). Текст ошибки не показывается и не пишется: он мог
  /// бы цитировать значение.
  Future<List<String>> _loadSecretNames() async {
    try {
      return selectableProfileTokenSecrets(await _secrets.names());
    } on Object {
      return const [];
    }
  }

  Future<List<String>?> _loadIds() async {
    try {
      return [for (final profile in await _store.load()) profile.id];
    } on Object {
      return null;
    }
  }

  AddProfileForm _recompute(AddProfileForm form, {bool? touched}) => _compose(
    draft: form.draft,
    useByDefault: form.useByDefault,
    idEdited: form.idEdited,
    tokenEnvName: form.tokenEnvName,
    touched: touched ?? form.touched,
    probe: form.probe,
  );

  /// Собирает форму; имена хранилища, бэкенд и ошибка у поля токена берутся
  /// из полей Cubit-а, чтобы вызовы не передавали их каждый раз.
  AddProfileForm _compose({
    required ProfileDraft draft,
    bool useByDefault = false,
    bool idEdited = false,
    String tokenEnvName = defaultTokenEnvName,
    required bool touched,
    ProfileProbeOutcome? probe,
  }) => _composeForm(
    existingIds: _existingIds,
    environment: _environment,
    kinds: _kinds,
    secretNames: _secretNames,
    backend: _secrets.backend,
    tokenSubmitError: _tokenSubmitError,
    storedFound: _storedFound,
    draft: draft,
    useByDefault: useByDefault,
    idEdited: idEdited,
    tokenEnvName: tokenEnvName,
    touched: touched,
    probe: probe,
  );

  /// Подтверждение `ws://` к нелокальному хосту — всегда, с токеном и без
  /// (решение пользователя 2026-11-05, D11, D20): по `ws://` открытым
  /// текстом идут и промпты с файлами. Адрес показан без `userinfo`, пути и
  /// query (D17).
  String _plaintextMessage(ProfileDraft draft) {
    final origin = profileOrigin(Uri.parse(draft.url.trim()));
    return _hasToken(draft)
        ? 'The token for $origin will travel in clear text. Use wss:// if the '
              'host supports it.'
        : 'Prompts and files sent to $origin will travel in clear text. Use '
              'wss:// if the host supports it.';
  }

  /// Есть ли у разобранного черновика предупреждение о `ws://` к другой
  /// машине (правило — `ProfileDraft`, не виджет и не Cubit).
  static bool _hasPlaintextWarning(DraftAccepted result) => result.warnings.any(
    (issue) => issue.code == ProfileDraftIssueCode.plaintextToRemote,
  );

  /// Ключ комбинации URL и токена. Значение нового токена в него не входит:
  /// его правка сбрасывает подтверждение явно (`setNewToken`), а имя секрета и
  /// переменной различает ключ.
  static String _plaintextKey(ProfileDraft draft) {
    final token = draft.token;
    final part = switch (token) {
      EnvToken(:final name) => 'env:$name',
      StoredSecretToken(:final name) => 'secret:$name',
      NewSecretToken() => 'new',
      _ => 'none',
    };
    return '${draft.url.trim()}|$part';
  }

  /// Выбран любой вариант токена, кроме «No token» (правила `ws://`, D14).
  static bool _hasToken(ProfileDraft draft) =>
      draft.token is EnvToken ||
      draft.token is StoredSecretToken ||
      draft.token is NewSecretToken;

  /// Вид токена профиля для события `connection_profile.saved` (D18).
  static String _tokenKindOf(ConnectionProfile profile) {
    final ref = profile is WebSocketProfile ? profile.tokenRef : null;
    if (ref == null) {
      return 'none';
    }
    return ref.startsWith('secret:') ? 'secret' : 'env';
  }

  /// Первый доступный тип; на десктопе — stdio, без stdio-резолвера —
  /// WebSocket (SETUP-22).
  static ProfileKind _initialKind(List<ProfileKind> kinds) =>
      kinds.contains(ProfileKind.stdio)
      ? ProfileKind.stdio
      : (kinds.isEmpty ? ProfileKind.webSocket : kinds.first);

  static String _typeOf(ConnectionProfile profile) => switch (profile) {
    StdioProfile() => 'stdio',
    WebSocketProfile() => 'websocket',
    _ => 'other',
  };
}

/// Собирает форму: черновик плюс вычисленные тексты и доступность действий.
///
/// Почему функция, а не метод: начальное состояние Cubit-а нужно в
/// `super(...)`, где экземпляра ещё нет.
AddProfileForm _composeForm({
  required List<String> existingIds,
  required Map<String, String> environment,
  required List<ProfileKind> kinds,
  required List<String> secretNames,
  required ProfileSecretBackend backend,
  String? tokenSubmitError,
  bool? storedFound,
  required ProfileDraft draft,
  bool useByDefault = false,
  bool idEdited = false,
  String tokenEnvName = defaultTokenEnvName,
  required bool touched,
  ProfileProbeOutcome? probe,
}) {
  final issues = draft.validate(existingIds);
  final blocking = [
    for (final issue in issues)
      if (!issue.isWarning) issue,
  ];
  // Для проверки нужны только поля агента, а не имя и id.
  final testIssues = draft
      .copyWith(id: 'probe', label: 'probe')
      .validate(const []);
  final token = draft.token;
  final tokenName = token is EnvToken && _isVariableName(token.name)
      ? token.name
      : null;
  final unset = tokenName != null && (environment[tokenName] ?? '').isEmpty;
  final errorTexts = touched
      ? _errorTexts(draft, blocking)
      : const <ProfileDraftField, String>{};
  final ownName = isValidProfileId(draft.id.trim())
      ? ownTokenSecretName(draft.id.trim())
      : 'codelab/profiles/<id>/token';
  return AddProfileForm(
    draft: draft,
    kinds: kinds,
    useByDefault: useByDefault,
    idEdited: idEdited,
    tokenEnvName: tokenEnvName,
    secretNames: secretNames,
    storedSecretsHint: secretNames.isEmpty
        ? 'No stored secrets in ${backend.id}.'
        : null,
    newTokenAvailable: backend.writable,
    newTokenHint: backend.writable
        ? 'Saved as $ownName in ${backend.id}. The value is never shown '
              'again or written to profiles.json.'
        : (backend.unavailableReason ??
              'Secret store ${backend.id} is read-only.'),
    touched: touched,
    probe: probe,
    errors: {
      ...errorTexts,
      // Отказ записи («секрет уже есть») важнее общей ошибки поля токена.
      ProfileDraftField.token: ?tokenSubmitError,
    },
    probeText: probe == null
        ? null
        : probeOutcomeText(
            probe,
            command: draft.command,
            // Токен «был отправлен», только если переменная выбрана и задана
            // (D12: иначе агент отказал бы в доступе без токена).
            token: _probeTokenView(
              token,
              envName: tokenName,
              envUnset: unset,
              secretNames: secretNames,
              storedFound: storedFound,
              backend: backend,
              ownName: ownName,
            ),
          ),
    warning: issues.any((i) => i.isWarning)
        ? (token is EnvToken ||
                  token is StoredSecretToken ||
                  token is NewSecretToken
              ? 'ws:// to another machine: the token is sent unencrypted.'
              : 'ws:// to another machine: traffic is sent unencrypted.')
        : null,
    tokenNotice: unset
        ? "$tokenName is not set in CodeLab's environment."
        : null,
    canTest: !testIssues.any((issue) => !issue.isWarning),
    canSave: blocking.isEmpty,
  );
}

Map<ProfileDraftField, String> _errorTexts(
  ProfileDraft draft,
  List<ProfileDraftIssue> blocking,
) {
  final labelEmpty = blocking.any(
    (i) => i.code == ProfileDraftIssueCode.labelEmpty,
  );
  final out = <ProfileDraftField, String>{};
  for (final issue in blocking) {
    // Пустое имя уже объяснено у поля имени: «id пуст» было бы вторым
    // сообщением об одном и том же.
    if (issue.code == ProfileDraftIssueCode.idEmpty && labelEmpty) {
      continue;
    }
    out.putIfAbsent(issue.field, () => _textOf(issue, draft));
  }
  return out;
}

/// Тексты полей: макет `AddProfile` и spec app-settings; `message` kit —
/// запасной английский текст. Значения `env` и токена в них нет (SETUP-19).
String _textOf(ProfileDraftIssue issue, ProfileDraft draft) =>
    switch (issue.code) {
      ProfileDraftIssueCode.labelEmpty => 'Enter a name.',
      ProfileDraftIssueCode.idTaken =>
        'A profile with id "${draft.id.toLowerCase()}" already exists.',
      ProfileDraftIssueCode.commandEmpty =>
        'Enter the command that starts the agent.',
      ProfileDraftIssueCode.urlInvalid => 'Use ws:// or wss:// with a host.',
      _ => issue.message,
    };

bool _isVariableName(String name) =>
    RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name);

/// Источник токена, который проверка действительно отправила (D12): текст
/// «rejected the token» допустим только для него.
ProfileTokenView _probeTokenView(
  Object? token, {
  required String? envName,
  required bool envUnset,
  required List<String> secretNames,
  required bool? storedFound,
  required ProfileSecretBackend backend,
  required String ownName,
}) => switch (token) {
  EnvToken() when envName != null => EnvTokenView(envName, isSet: !envUnset),
  StoredSecretToken(:final name) => SecretTokenView(
    name,
    backend: backend.id,
    isSet: storedFound ?? secretNames.contains(name),
  ),
  NewSecretToken(:final value) => SecretTokenView(
    ownName,
    backend: backend.id,
    isSet: !value.isEmpty,
  ),
  _ => const NoTokenView(),
};
