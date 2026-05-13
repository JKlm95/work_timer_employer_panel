/// Opt-in verbose logging for `users/.../live/status` and live running amount estimates.
///
/// Defaults to **off** so the dashboard tick does not spam the console.
/// Set [verboseLiveLogs] to `true` locally while debugging (e.g. mobile → web timer flow).
/// Example in `main()` (debug sessions only):
/// `LiveStatusDebugConfig.verboseLiveLogs = true;`
class LiveStatusDebugConfig {
  LiveStatusDebugConfig._();

  /// When `true`, logs each Firestore `live/status` snapshot and live-amount summary lines.
  static bool verboseLiveLogs = false;
}
