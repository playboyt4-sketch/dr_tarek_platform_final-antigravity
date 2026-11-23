import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private var blindView: UIView?
  private var screenGuardChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    window?.makeKeyAndVisible()
    window?.makeSecure()

    setupScreenGuardChannel()
    setupCaptureObservers()
    screenCaptureChanged()

    return result
  }

  private func setupScreenGuardChannel() {
    let controller = (window?.rootViewController as? FlutterViewController) ?? (getKeyWindow()?.rootViewController as? FlutterViewController)
    if let flutterViewController = controller {
      screenGuardChannel = FlutterMethodChannel(
        name: "com.drtarek.platform/screen_guard",
        binaryMessenger: flutterViewController.binaryMessenger
      )
      screenGuardChannel?.setMethodCallHandler { [weak self] (call, result) in
        if call.method == "isRecording" {
          if #available(iOS 11.0, *) {
            result(UIScreen.main.isCaptured)
          } else {
            result(false)
          }
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  private func setupCaptureObservers() {
    if #available(iOS 11.0, *) {
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(screenCaptureChanged),
        name: UIScreen.capturedDidChangeNotification,
        object: nil
      )
    }
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenCaptureChanged),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
  }

  @objc private func screenCaptureChanged() {
    if #available(iOS 11.0, *) {
      let isCaptured = UIScreen.main.isCaptured
      if isCaptured {
        showSecurityShield()
      } else {
        removeSecurityShield()
      }
      screenGuardChannel?.invokeMethod("onRecordingChanged", arguments: isCaptured)
    }
  }

  private func showSecurityShield() {
    guard blindView == nil else { return }
    let targetWindow = self.window ?? getKeyWindow()
    guard let window = targetWindow else { return }
    let shield = UIView(frame: window.bounds)
    shield.backgroundColor = .black
    shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    let label = UILabel()
    label.text = "تسجيل الشاشة غير مسموح"
    label.textColor = .white
    label.textAlignment = .center
    label.font = UIFont.systemFont(ofSize: 18, weight: .bold)
    label.translatesAutoresizingMaskIntoConstraints = false
    shield.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: shield.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: shield.centerYAnchor)
    ])
    window.addSubview(shield)
    self.blindView = shield
  }

  private func removeSecurityShield() {
    blindView?.removeFromSuperview()
    blindView = nil
  }

  private func getKeyWindow() -> UIWindow? {
    if #available(iOS 13.0, *) {
      return UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow } ?? UIApplication.shared.windows.first { $0.isKeyWindow } ?? self.window
    } else {
      return self.window
    }
  }
}

extension UIWindow {
  func makeSecure() {
    if self.viewWithTag(998877) != nil { return }
    let field = UITextField()
    field.tag = 998877
    field.isSecureTextEntry = true
    field.isUserInteractionEnabled = false
    self.addSubview(field)
    field.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      field.centerXAnchor.constraint(equalTo: self.centerXAnchor),
      field.centerYAnchor.constraint(equalTo: self.centerYAnchor)
    ])
    self.layer.superlayer?.addSublayer(field.layer)
    field.layer.sublayers?.first?.addSublayer(self.layer)
  }
}
