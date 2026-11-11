import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "JmEngine")!
    let channel = FlutterMethodChannel(
      name: "jmcomic/engine",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { _, result in
      result(
        FlutterError(
          code: "unavailable",
          message: "iOS 需要先用 gomobile 生成 xcframework 并在这里调用 jmengine.Start，见仓库 README。",
          details: nil
        )
      )
    }
  }
}
