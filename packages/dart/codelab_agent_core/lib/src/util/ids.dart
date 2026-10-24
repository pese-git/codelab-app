/// Id port of the core (PKG-6): ids of sessions, records and tool calls
/// come from the host, so tests get the same ids on every run.
abstract interface class IdGenerator {
  String nextId();
}
