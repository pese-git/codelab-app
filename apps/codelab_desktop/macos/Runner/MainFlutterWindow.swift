import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    #if DEBUG
      registerE2eWindowChannel(flutterViewController)
    #endif

    super.awakeFromNib()
  }

  #if DEBUG
    /// Канал, которым e2e-тесты задают настоящий размер окна.
    ///
    /// Почему: тестам нужна широкая раскладка (сайдбар и док колонками), а
    /// подмена `physicalSize` вида в Dart расходится с поверхностью окна, и
    /// macOS показывает чёрное окно всё время теста.
    ///
    /// Для чего: `integration_test/flutter_test_config.dart` перед каждым
    /// тестом вызывает `setContentSize` с логическим размером; окно меняет
    /// размер, а Flutter получает новые метрики обычным путём.
    ///
    /// Как использовать: только debug-сборка (e2e на macOS идут в debug);
    /// в release канала нет. Аргументы — `{"width": Double, "height": Double}`
    /// в точках; иначе `FlutterMethodNotImplemented`.
    private func registerE2eWindowChannel(_ controller: FlutterViewController) {
      let channel = FlutterMethodChannel(
        name: "codelab/e2e_window",
        binaryMessenger: controller.engine.binaryMessenger)
      channel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "setContentSize",
          let args = call.arguments as? [String: Any],
          let width = args["width"] as? Double,
          let height = args["height"] as? Double,
          let window = self
        else {
          result(FlutterMethodNotImplemented)
          return
        }
        window.setContentSize(NSSize(width: width, height: height))
        result(nil)
      }
    }
  #endif
}
