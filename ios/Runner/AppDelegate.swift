import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private var blindView: UIView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Listen for Screen Recording / AirPlay Mirroring status changes
    if #available(iOS 11.0, *) {
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(screenCaptureChanged),
        name: UIScreen.capturedDidChangeNotification,
        object: nil
      )
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  @objc private func screenCaptureChanged() {
    if #available(iOS 11.0, *) {
      if UIScreen.main.isCaptured {
        // Block display by covering window with black security shield
        showSecurityShield()
      } else {
        removeSecurityShield()
      }
    }
  }

  private func showSecurityShield() {
    guard blindView == nil, let window = self.window else { return }
    let shield = UIView(frame: window.bounds)
    shield.backgroundColor = .black
    let label = UILabel()
    label.text = "Screen recording is prohibited / تسجيل الشاشة غير مصرح به"
    label.textColor = .white
    label.textAlignment = .center
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
}
