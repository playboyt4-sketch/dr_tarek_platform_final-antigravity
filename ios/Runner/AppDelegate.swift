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

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    application.registerForRemoteNotifications()

    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    window?.makeKeyAndVisible()
    clearNotificationBadge(application)

    setupScreenGuardChannel()
    setupCaptureObservers()
    screenCaptureChanged()

    return result
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    clearNotificationBadge(application)
  }

  private func clearNotificationBadge(_ application: UIApplication) {
    if #available(iOS 16.0, *) {
      UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
    } else {
      application.applicationIconBadgeNumber = 0
    }
  }

  @available(iOS 10.0, *)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .badge, .sound, .list])
    } else {
      completionHandler([.alert, .badge, .sound])
    }
  }

  private func setupScreenGuardChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    screenGuardChannel = FlutterMethodChannel(
      name: "com.drtarek.platform/screen_guard",
      binaryMessenger: controller.binaryMessenger
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
      if screenGuardChannel == nil {
        setupScreenGuardChannel()
      }
      screenGuardChannel?.invokeMethod("onRecordingChanged", arguments: isCaptured)
    }
  }

  private func showSecurityShield() {
    guard blindView == nil else { return }
    guard let targetWindow = window else { return }
    let shield = UIView(frame: targetWindow.bounds)
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
    targetWindow.addSubview(shield)
    self.blindView = shield
  }

  private func removeSecurityShield() {
    blindView?.removeFromSuperview()
    blindView = nil
  }
}
