import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Пункт «Настройки…» главного меню (⌘,): сообщает Dart-стороне через канал
  /// `codelab/app_menu`. Меню macOS перехватывает ⌘, раньше Flutter, поэтому
  /// без действия пункт ничего не делал, а сочетание Dart-стороны не срабатывало.
  /// Открывает настройки Dart: тот же путь, что у сочетания `open-settings`.
  @IBAction func openPreferences(_ sender: Any?) {
    guard
      let controller = NSApp.windows
        .compactMap({ $0.contentViewController as? FlutterViewController })
        .first
    else { return }
    FlutterMethodChannel(
      name: "codelab/app_menu",
      binaryMessenger: controller.engine.binaryMessenger
    ).invokeMethod("openSettings", arguments: nil)
  }
}
