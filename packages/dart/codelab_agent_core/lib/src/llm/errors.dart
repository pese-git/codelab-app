/// Class of a model request failure, set once at the adapter boundary
/// (`agent-core-architecture` §2.9). Decorators decide on retries and
/// fallback only by this class, never by the error text.
enum LlmErrorClass {
  network,
  timeout,
  rateLimited,
  overflow,
  auth,
  badRequest,
  server,
  terminalFinish,
  aborted,
  unknown,
}
