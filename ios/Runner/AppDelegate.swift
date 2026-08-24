import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let launched = super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "cards_wallet/app_icon",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        guard call.method == "setAppIcon" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard
          let arguments = call.arguments as? [String: Any],
          let iconId = arguments["iconId"] as? String
        else {
          result(
            FlutterError(
              code: "invalid_icon",
              message: "Missing app icon identifier.",
              details: nil
            )
          )
          return
        }

        let iconName: String?
        switch iconId {
        case "three_d": iconName = nil
        case "purple": iconName = "AppIconPurple"
        case "multicolor": iconName = "AppIconMulticolor"
        case "ocean": iconName = "AppIconOcean"
        case "emerald": iconName = "AppIconEmerald"
        case "sunset": iconName = "AppIconSunset"
        case "red": iconName = "AppIconRed"
        default:
          result(
            FlutterError(
              code: "invalid_icon",
              message: "Unknown app icon: \(iconId)",
              details: nil
            )
          )
          return
        }

        guard UIApplication.shared.supportsAlternateIcons else {
          result(
            FlutterError(
              code: "unsupported",
              message: "This device does not support alternate app icons.",
              details: nil
            )
          )
          return
        }
        if UIApplication.shared.alternateIconName == iconName {
          result(true)
          return
        }

        UIApplication.shared.setAlternateIconName(iconName) { error in
          if let error {
            result(
              FlutterError(
                code: "icon_change_failed",
                message: error.localizedDescription,
                details: nil
              )
            )
          } else {
            result(true)
          }
        }
      }
    }

    return launched
  }
}
