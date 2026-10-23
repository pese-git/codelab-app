/// Test support of the agent core: deterministic ports and the scripted
/// model. Only for tests and test hosts — the main barrel does not export
/// it (`agent-core-architecture` §1.3, §14.2).
library;

export 'src/testing/fake_clock.dart';
export 'src/testing/recording_logger.dart';
export 'src/testing/scripted_stream_function.dart';
export 'src/testing/sequential_id_generator.dart';
