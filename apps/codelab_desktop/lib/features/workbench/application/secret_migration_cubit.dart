import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:flutter_bloc/flutter_bloc.dart';

import 'secret_migration_runner.dart';

/// Состояние переноса секретов встроенного агента.
///
/// Почему: показ предупреждения, план, перенос и итог — явный автомат, а не
/// набор булевых флагов (`AGENTS.md` §8; design.md change
/// `add-config-literal-secrets-and-migrate`, D8):
///
/// ```text
/// hidden → offered → planning → planReady | planFailed
///        → applying → applied | applyFailed
/// ```
///
/// Для чего: presentation (`InfoBar` и диалог, задача 4.4) только отображает
/// состояние: `offered` — предупреждение без диалога, остальные — диалог.
sealed class SecretMigrationState {
  const SecretMigrationState();
}

/// Предупреждения нет: встроенный агент не открыт, секретов в файле нет или
/// пользователь закрыл предупреждение крестиком.
final class SecretMigrationHidden extends SecretMigrationState {
  const SecretMigrationHidden();
}

/// Встроенный агент открыт с секретами в файле: показывается `InfoBar`.
final class SecretMigrationOffered extends SecretMigrationState {
  const SecretMigrationOffered();
}

/// Диалог открыт, план строится.
final class SecretMigrationPlanning extends SecretMigrationState {
  const SecretMigrationPlanning();
}

/// План построен. Кнопки выбирает presentation по признакам: [canApply] —
/// `Migrate` и `Cancel`; иначе только `Close`, а текст — по [readOnlyBackend],
/// [nameConflict] или [onlyExtraLayerFindings].
final class SecretMigrationPlanReady extends SecretMigrationState {
  const SecretMigrationPlanReady({
    required this.items,
    required this.canApply,
    required this.readOnlyBackend,
    required this.nameConflict,
    required this.onlyExtraLayerFindings,
    this.detail,
  });

  /// Строки плана без значений секретов.
  final List<String> items;

  /// `Migrate` доступна: пункты есть, бэкенд пишущий, конфликтов нет.
  final bool canApply;

  /// Бэкенд `env` только для чтения.
  final bool readOnlyBackend;

  /// Имя секрета занято; замена в app не предлагается (L7).
  final bool nameConflict;

  /// Находки только в файле `CODELAB_CONFIG`.
  final bool onlyExtraLayerFindings;

  /// Текст подсказки `env` или конфликта имени от порта.
  final String? detail;
}

/// План не построен; [message] — безопасный текст без `error.toString()`.
final class SecretMigrationPlanFailed extends SecretMigrationState {
  const SecretMigrationPlanFailed(this.message);

  /// Текст проблемы для диалога: из отчёта порта или `Planning failed: <тип>.`
  /// (D8); без значений секретов и путей, показывается как есть.
  final String message;
}

/// Перенос выполняется.
final class SecretMigrationApplying extends SecretMigrationState {
  const SecretMigrationApplying();
}

/// Перенос выполнен: диалог показывает `Secrets moved…` и `Restart agent`.
final class SecretMigrationApplied extends SecretMigrationState {
  const SecretMigrationApplied({
    required this.items,
    required this.canRestart,
    this.agentGone = false,
  });

  /// Строки итога без значений секретов.
  final List<String> items;

  /// `Restart agent` доступна: ход не идёт (подсказка просит дождаться его
  /// конца).
  final bool canRestart;

  /// Агент, для которого шёл перенос, сменился или закрыт: перезапускать
  /// нечего (подсказка `The embedded agent is no longer connected.`).
  final bool agentGone;
}

/// Перенос не выполнен; [message] — безопасный текст без `error.toString()`.
///
/// При частичном сбое (часть файлов уже переписана) [movedAny] `true`, а
/// [items] — то, что перенесено: пользователь видит это под текстом проблемы
/// и может перезапустить агента ([canRestart] — тем же правилом хода, что у
/// [SecretMigrationApplied]).
final class SecretMigrationApplyFailed extends SecretMigrationState {
  const SecretMigrationApplyFailed(
    this.message, {
    this.items = const [],
    this.movedAny = false,
    this.canRestart = false,
    this.agentGone = false,
  });

  /// Текст проблемы для диалога (из отчёта порта или `Migration failed: <тип>.`);
  /// без значений секретов, показывается как есть.
  final String message;

  /// Что уже перенесено при частичном сбое; пусто, если [movedAny] `false`.
  final List<String> items;

  /// Часть файлов уже переписана: presentation показывает [items] и кнопку
  /// `Restart agent`; иначе предлагается только `Close`.
  final bool movedAny;

  /// `Restart agent` доступна: ход не идёт и агент не сменился. Пересчитывается
  /// при смене активности хода, пока [movedAny] `true`.
  final bool canRestart;

  /// Агент, для которого шёл перенос, сменился или закрыт: перезапускать
  /// нечего, а `Close` решает по текущему предложению.
  final bool agentGone;
}

/// Автомат переноса секретов встроенного агента.
///
/// Почему: предупреждение «секреты в файле конфига» и перенос — состояние
/// app, а не клиентского ядра (`codelab_client_core` и ACP не меняются, D8).
/// Источник признака — `SecretMigrationOffer` composition root (задача 4.3).
///
/// Для чего: ведёт `InfoBar` и диалог, вызывает порт [SecretMigrationRunner]
/// и отбрасывает запоздавшие результаты по номеру попытки (`AGENTS.md` §9,
/// §12). Папка проекта берётся из предложения — это `cwd`, с которым открыт
/// агент, а не текущий выбор проекта в UI: после смены проекта без
/// переподключения агент читает прежние файлы.
///
/// Как использовать: composition root создаёт Cubit с портом и потоками «ход
/// идёт» (по всем сессиям рабочего места) и [offered] (`cwd` агента или
/// `null`, текущее значение первым событием). [setOffered] вызывается при
/// *смене* предложения: повторный вызов с `cwd` в `hidden` после [dismiss]
/// снова покажет предупреждение — так «до следующего подключения» и
/// работает. Операция записи ([migrate]) в полёте одна; пока она идёт,
/// [closeDialog], [openPlan] и смена предложения состояние не трогают. Тексты
/// ошибок строятся из отчёта порта или имени типа исключения, никогда из
/// `toString()`; в [logger] идут только события, числа, id бэкенда и имена
/// типов — без путей и значений (`AGENTS.md` §16).
final class SecretMigrationCubit extends Cubit<SecretMigrationState> {
  SecretMigrationCubit({
    required SecretMigrationRunner runner,
    required Stream<bool> turnActivity,
    Stream<String?>? offered,
    Logger? logger,
  }) : _runner = runner,
       _logger = logger,
       super(const SecretMigrationHidden()) {
    _turnSubscription = turnActivity.listen(_handleTurn);
    _offeredSubscription = offered?.listen(setOffered);
  }

  final SecretMigrationRunner _runner;
  final Logger? _logger;
  late final StreamSubscription<bool> _turnSubscription;
  StreamSubscription<String?>? _offeredSubscription;

  /// Номер последней начатой операции. Результат старого номера (диалог
  /// закрыт, агент закрыт, начата новая попытка) состояние не меняет.
  var _attempt = 0;
  var _turnActive = false;

  /// `cwd` агента из предложения; `null` — предложения нет.
  String? _cwd;

  /// Перенос (запись) в полёте: его нельзя ни закрыть, ни наложить на него
  /// другую операцию.
  var _applyInFlight = false;

  /// Предложение переноса появилось ([cwd] — папка, с которой открыт агент)
  /// или пропало ([cwd] `null`: агент закрыт или переподключён). Пропадание
  /// закрывает всё и отбрасывает идущие операции, кроме записи: она
  /// завершится и покажет итог.
  void setOffered(String? cwd) {
    _cwd = cwd;
    if (_applyInFlight) return;
    _attempt++;
    if (cwd != null) {
      if (state is SecretMigrationHidden) {
        emit(const SecretMigrationOffered());
      }
      return;
    }
    _emitIfChanged(const SecretMigrationHidden());
  }

  /// Закрытие `InfoBar` крестиком: скрыть до следующего подключения.
  void dismiss() {
    if (_applyInFlight) return;
    _attempt++;
    _emitIfChanged(const SecretMigrationHidden());
  }

  /// `Migrate secrets`: открыть диалог и построить план.
  void openPlan() {
    final cwd = _cwd;
    if (state is! SecretMigrationOffered || _applyInFlight) return;
    if (cwd == null) {
      // Предложения уже нет (агент закрыт): показывать нечего.
      emit(const SecretMigrationHidden());
      return;
    }
    unawaited(_plan(++_attempt, cwd));
  }

  /// `Migrate`: выполнить перенос; доступно только из применимого плана.
  void migrate() {
    final current = state;
    final cwd = _cwd;
    if (current is! SecretMigrationPlanReady ||
        !current.canApply ||
        cwd == null ||
        _applyInFlight) {
      return;
    }
    unawaited(_apply(++_attempt, cwd));
  }

  /// `Close`/`Cancel`: закрыть диалог. После переноса (в том числе
  /// частичного) предупреждение больше не показывается — файл изменён, а
  /// признак пересчитает переподключение; в остальных случаях остаётся
  /// `InfoBar`. Во время записи ничего не делает.
  void closeDialog() {
    final current = state;
    if (current is SecretMigrationHidden ||
        current is SecretMigrationOffered ||
        current is SecretMigrationApplying) {
      return;
    }
    _attempt++;
    // После переноса для *того же* агента предупреждение скрыто (признак
    // пересчитает переподключение). Если агент за время переноса сменился,
    // или переноса не было, решает текущее предложение: есть `cwd` —
    // `InfoBar` остаётся, нет — скрыт.
    final migratedCurrentAgent =
        (current is SecretMigrationApplied && !current.agentGone) ||
        (current is SecretMigrationApplyFailed &&
            current.movedAny &&
            !current.agentGone);
    emit(
      migratedCurrentAgent || _cwd == null
          ? const SecretMigrationHidden()
          : const SecretMigrationOffered(),
    );
  }

  @override
  Future<void> close() async {
    _attempt++;
    await _turnSubscription.cancel();
    await _offeredSubscription?.cancel();
    return super.close();
  }

  Future<void> _plan(int attempt, String cwd) async {
    emit(const SecretMigrationPlanning());
    try {
      final report = await _runner.plan(cwd);
      if (_discarded(attempt, 'plan')) return;
      final problem = report.problem;
      if (problem != null) {
        _logger?.warning(
          'secret_migration.plan_failed',
          context: {'exit_code': report.exitCode},
        );
        emit(SecretMigrationPlanFailed(problem));
        return;
      }
      // Блокирующий признак сильнее `canApply` порта: перенос при бэкенде
      // `env` или конфликте имени запрещён, даже если порт ошибся.
      final blocked =
          report.readOnlyBackend ||
          report.nameConflict ||
          report.onlyExtraLayerFindings;
      final canApply = report.canApply && !blocked;
      _logger?.info(
        'secret_migration.planned',
        context: {'items': report.items.length, 'can_apply': canApply},
      );
      emit(
        SecretMigrationPlanReady(
          items: report.items,
          canApply: canApply,
          readOnlyBackend: report.readOnlyBackend,
          nameConflict: report.nameConflict,
          onlyExtraLayerFindings: report.onlyExtraLayerFindings,
          detail: report.detail,
        ),
      );
    } on Object catch (error) {
      if (_discarded(attempt, 'plan')) return;
      _logger?.warning(
        'secret_migration.plan_failed',
        context: {'error_class': '${error.runtimeType}'},
      );
      emit(SecretMigrationPlanFailed(_describe('Planning', error)));
    }
  }

  Future<void> _apply(int attempt, String cwd) async {
    _applyInFlight = true;
    emit(const SecretMigrationApplying());
    try {
      final report = await _runner.apply(cwd);
      _applyInFlight = false;
      if (_discarded(attempt, 'apply')) return;
      // Агент мог смениться, пока шла запись (`setOffered` её не прерывает):
      // итог показываем, но перезапускать уже нечего, а после Close решает
      // текущее предложение.
      final gone = _cwd != cwd;
      final problem = report.problem;
      if (problem != null) {
        _logger?.warning(
          'secret_migration.apply_failed',
          context: {
            'exit_code': report.exitCode,
            'moved': report.movedAny,
            'backend': ?report.backendId,
          },
        );
        emit(
          SecretMigrationApplyFailed(
            problem,
            items: report.movedAny ? report.items : const [],
            movedAny: report.movedAny,
            canRestart: !_turnActive && !gone,
            agentGone: gone,
          ),
        );
        return;
      }
      _logger?.info(
        'secret_migration.applied',
        context: {'moved': report.items.length, 'backend': ?report.backendId},
      );
      emit(
        SecretMigrationApplied(
          items: report.items,
          canRestart: !_turnActive && !gone,
          agentGone: gone,
        ),
      );
    } on Object catch (error) {
      _applyInFlight = false;
      if (_discarded(attempt, 'apply')) return;
      _logger?.warning(
        'secret_migration.apply_failed',
        context: {'error_class': '${error.runtimeType}'},
      );
      emit(SecretMigrationApplyFailed(_describe('Migration', error)));
    }
  }

  /// Результат устарел (диалог закрыт, агент сменился, Cubit закрыт):
  /// состояние не меняется, в журнал — событие `result_discarded` (§16).
  bool _discarded(int attempt, String phase) {
    if (isClosed || attempt != _attempt) {
      _logger?.info(
        'secret_migration.result_discarded',
        context: {'phase': phase},
      );
      return true;
    }
    return false;
  }

  void _handleTurn(bool active) {
    _turnActive = active;
    final current = state;
    if (current is SecretMigrationApplied &&
        current.canRestart == (active || current.agentGone)) {
      emit(
        SecretMigrationApplied(
          items: current.items,
          canRestart: !active && !current.agentGone,
          agentGone: current.agentGone,
        ),
      );
    } else if (current is SecretMigrationApplyFailed &&
        current.movedAny &&
        current.canRestart == (active || current.agentGone)) {
      emit(
        SecretMigrationApplyFailed(
          current.message,
          items: current.items,
          movedAny: true,
          canRestart: !active && !current.agentGone,
          agentGone: current.agentGone,
        ),
      );
    }
  }

  void _emitIfChanged(SecretMigrationState next) {
    if (state.runtimeType != next.runtimeType) emit(next);
  }

  /// Только имя типа: `toString()` исключения может нести литерал секрета.
  static String _describe(String action, Object error) =>
      '$action failed: ${error.runtimeType}.';
}
