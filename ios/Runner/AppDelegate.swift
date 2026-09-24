import Flutter
import MessageUI
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, MFMailComposeViewControllerDelegate {
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

      let supportChannel = FlutterMethodChannel(
        name: "cards_wallet/support",
        binaryMessenger: controller.binaryMessenger
      )
      supportChannel.setMethodCallHandler { [weak self, weak controller] call, result in
        guard let self else {
          result(
            FlutterError(
              code: "email_unavailable",
              message: "The email composer is unavailable.",
              details: nil
            )
          )
          return
        }

        switch call.method {
        case "getDeviceDetails":
          let device = UIDevice.current
          result([
            "platform": "iOS",
            "manufacturer": "Apple",
            "model": device.model,
            "device": device.name,
            "osVersion": device.systemVersion,
          ])
        case "composeEmail":
          guard
            let arguments = call.arguments as? [String: Any],
            let recipient = arguments["recipient"] as? String
          else {
            result(
              FlutterError(
                code: "invalid_email",
                message: "Email recipient is missing.",
                details: nil
              )
            )
            return
          }
          guard MFMailComposeViewController.canSendMail() else {
            result(
              FlutterError(
                code: "email_unavailable",
                message: "No email account is configured in Mail.",
                details: nil
              )
            )
            return
          }
          let composer = MFMailComposeViewController()
          composer.mailComposeDelegate = self
          composer.setToRecipients([recipient])
          composer.setSubject(arguments["subject"] as? String ?? "CardVault diagnostic logs")
          composer.setMessageBody(arguments["body"] as? String ?? "", isHTML: false)
          if let attachmentPath = arguments["attachmentPath"] as? String {
            guard let attachment = try? Data(
              contentsOf: URL(fileURLWithPath: attachmentPath)
            ) else {
              result(
                FlutterError(
                  code: "missing_attachment",
                  message: "The diagnostic log file was not found.",
                  details: nil
                )
              )
              return
            }
            composer.addAttachmentData(
              attachment,
              mimeType: "text/plain",
              fileName: URL(fileURLWithPath: attachmentPath).lastPathComponent
            )
          }
          controller?.present(composer, animated: true) {
            result(true)
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return launched
  }

  func mailComposeController(
    _ controller: MFMailComposeViewController,
    didFinishWith result: MFMailComposeResult,
    error: Error?
  ) {
    controller.dismiss(animated: true)
  }
}
