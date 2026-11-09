/// Перечень пропусков, допустимых в дополнительных источниках.
///
/// Почему: пропуск по правилу спецификации (например, `setup.mcp` не
/// передаётся процессу агента) не должен открывать строку Must, а любой
/// неизвестный пропуск должен (`switch-default-agent-to-dart`, D5, решение
/// Q5). Перечень явный, у каждой записи — требование-источник.
///
/// Для чего: единственное место перечня; его читают `parity_evidence_test` и
/// модульные тесты. Список пополняется только записью со ссылкой на
/// требование спецификации; причина пропуска, которой в спецификации нет,
/// остаётся `skipped`.
library;

import 'verdict.dart';

/// Допустимые пропуски дополнительных источников (D5, Q5).
final allowedSkips = <AllowedSkip>[
  const AllowedSkip(
    'setup.mcp cannot be passed to the agent process',
    'cli-scenario-driver «Команда test-scenario»: фикстура с setup.mcp '
        'не играется процессом агента',
  ),
  AllowedSkip(
    RegExp(r'embedded: .* cannot be played by the embedded agent'),
    'cli-scenario-driver «Команда test-scenario»: setup.config, '
    'setup.sessions, setup.web и профиль вне перечня не играются '
    'встроенным агентом',
  ),
  AllowedSkip(
    RegExp(r'has setup\.transport: the transport driver'),
    'acp-golden-fixtures «Транспортный драйвер фикстур»: фикстуру с '
    'setup.transport играет драйвер бинаря агента',
  ),
  AllowedSkip(
    RegExp(r'has roles \[[^\]]*\] without "(agent|client)"'),
    'acp-golden-fixtures «Агентский драйвер фикстур» и «Клиентский драйвер '
    'фикстур»: фикстура играется только ролями из roles',
  ),
  const AllowedSkip(
    '[skipped: the embedded agent runs files and commands locally',
    'testing-quality «Встроенный режим в e2e и conformance»: fs/* и '
        'terminal/* во встроенном режиме',
  ),
  const AllowedSkip(
    '[skipped: the embedded agent starts no stdio child process',
    'testing-quality «Встроенный режим в e2e и conformance»: у встроенного '
        'агента нет дочернего stdio-процесса',
  ),
  const AllowedSkip(
    'the embedded agent is built in and cannot be stored in profiles.json',
    'codelab-cli «Профили подключения CLI»: встроенный агент зарезервирован '
        '(id embedded и default), в profiles.json не хранится, '
        '`profiles add embedded` даёт код 64; тесты со сохранённым профилем '
        'в режиме embedded пропускаются',
  ),
];
