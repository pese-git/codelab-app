import 'usage_models.dart';

/// Свёртка снимков `_codelab/session/usage` одной сессии в [UsageView]
/// (D7, D8, D21 Т4).
///
/// Почему отдельный чистый класс: правило «какой снимок применять» — главная
/// политика расширения (дубли, опоздания, смена соединения), и её нужно
/// проверять без `ClientWorkspace` и сокетов; тем же классом свёртку делает
/// тест корпуса фикстур (D21 Т7). Состояние неизменяемо: каждый переход —
/// новое значение, поэтому публикация в `SessionView` — одна ревизия на
/// применённый снимок (VIEW-6).
///
/// Для чего: хранит `UsageView`, поколение соединения последнего снимка и
/// признак «агент объявил usage». Клиент ничего не суммирует и окно не
/// оценивает: суммы и заполнение приходят готовыми от агента (D8).
///
/// Как использовать: `UsageFold.initial(declared: …)` при создании сессии и
/// при смене соединения или `session/load` (сброс — снова `initial`);
/// `apply(snapshot, generation: …)` на каждый разобранный снимок — `null`
/// значит «отбросить» (дубль или опоздание), иначе — новое состояние.
final class UsageFold {
  const UsageFold._({
    required this.declared,
    required this.generation,
    required this.view,
    required this.turnId,
  });

  /// Состояние без снимков: `awaiting`, если агент объявил `usage` при
  /// `initialize` (D3), иначе `unknown`.
  UsageFold.initial({required this.declared})
    : generation = null,
      turnId = null,
      view = UsageView(
        support: declared ? UsageSupport.awaiting : UsageSupport.unknown,
      );

  /// Агент объявил `usage: {"version": 1}` в текущем соединении.
  final bool declared;

  /// Поколение соединения, по которому пришёл последний применённый снимок;
  /// `null` — снимков в этом состоянии нет.
  final int? generation;

  final UsageView view;

  /// `turnId` последнего снимка с ходом: по нему решается, чей агрегат
  /// показывает `view.lastTurn` (D8). `null` — снимков с ходом не было.
  final String? turnId;

  /// Применяет [snapshot], пришедший по соединению поколения [generation].
  ///
  /// Правило D7: снимок применяется, только если его `seq` больше последнего
  /// применённого в том же поколении; в более новом поколении счёт начинается
  /// заново (`seq` нового агента может быть 1), а снимок более старого
  /// поколения отбрасывается. Поэтому снимок старого агента, пришедший между
  /// началом `reconnect` и заменой транспорта, не блокирует `seq: 1`
  /// нового (D21 Т2).
  ///
  /// Возвращает `null` для дубля и опоздания: состояние и ревизия не меняются.
  ///
  /// [receivedAt] — момент применения по часам вызывающего (D9, «Часы»):
  /// свёртка чистая и `DateTime.now` не зовёт; обязателен, чтобы вызывающий не
  /// забыл часы рабочего пространства. Бюджет хода (D9, «Свёртка») ведётся по
  /// `turnId`: снимок с `budget` заменяет его; тот же ход без `budget` его
  /// сохраняет (снимок `turn` лишь ставит `ended`); новый ход без `budget`
  /// стирает; снимок без `turnId` не трогает.
  UsageFold? apply(
    UsageSnapshot snapshot, {
    required int generation,
    required DateTime receivedAt,
  }) {
    final known = this.generation;
    if (known != null && generation < known) {
      return null;
    }
    final base = known == generation ? view.lastSeq : 0;
    if (snapshot.seq <= base) {
      return null;
    }
    return UsageFold._(
      declared: declared,
      generation: generation,
      turnId: snapshot.turnId ?? turnId,
      view: UsageView(
        support: UsageSupport.reported,
        // `lastTurn` привязан к `turnId` (D8): снимок без `turnId`
        // (`compaction`) ход не трогает; со `turnId` — это агрегат его хода,
        // в том числе тот же `turnId` (ход идёт) и новый ход без разобранного
        // `turn` (`null`, а не агрегат прошлого хода).
        lastTurn: snapshot.turnId == null ? view.lastTurn : snapshot.turn,
        session: snapshot.session,
        context: snapshot.context,
        lastSeq: snapshot.seq,
        budget: _budgetAfter(snapshot, receivedAt),
      ),
    );
  }

  /// Бюджет после [snapshot] (D9, «Свёртка», Q11 (а)). Сравнение «тот же или
  /// новый ход» — с `turnId` текущего бюджета: пока он не `null`, совпадает с
  /// [turnId] свёртки.
  TurnBudgetView? _budgetAfter(UsageSnapshot snapshot, DateTime receivedAt) {
    final current = view.budget;
    final turnId = snapshot.turnId;
    if (turnId == null) {
      // compaction, compactionDiscarded, load и незнакомый повод: ход не
      // менялся, бюджет прежний.
      return current;
    }
    // `ended` липкий в пределах хода: поздний `step` с бюджетом после итога
    // того же `turnId` (нарушение агентом) не «оживляет» ход (D9, Q11 (а)).
    final ended =
        snapshot.trigger == UsageTrigger.turn ||
        (current?.turnId == turnId && current!.ended);
    final fresh = snapshot.budget;
    if (fresh != null) {
      return TurnBudgetView(
        turnId: turnId,
        receivedAt: receivedAt,
        ended: ended,
        steps: fresh.steps,
        tokens: fresh.tokens,
        cost: fresh.cost,
        duration: fresh.duration,
      );
    }
    if (current != null && current.turnId == turnId) {
      // Тот же ход без `budget`: числа прежние; итог хода лишь помечается.
      return ended ? current.copyWith(ended: true) : current;
    }
    return null;
  }
}
