import CoreLocation
import Flutter
import UIKit

/// Native half of the Dart GeofencePlatform contract on iOS
/// (channel `vidavoice/geofence`; the Android twin lives in
/// GeofenceBridge.kt).
///
/// iOS region monitoring survives app termination and reboot: the
/// system relaunches the app into the background for enter/exit
/// events. Transitions observed before a Dart engine is ready are
/// persisted to a UserDefaults spill queue (opaque zone ids only)
/// for Dart to drain on launch. iOS caps monitored regions at 20 —
/// syncRegions takes the first 20 of the desired set.
final class GeofenceIosBridge: NSObject, CLLocationManagerDelegate {
  static let shared = GeofenceIosBridge()

  private let defaultsKeyRegions = "vidavoice.geofence.regions"
  private let defaultsKeyPending = "vidavoice.geofence.pending"

  private let manager = CLLocationManager()
  private var channel: FlutterMethodChannel?

  override private init() {
    super.init()
    manager.delegate = self
    manager.pausesLocationUpdatesAutomatically = false
  }

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "vidavoice/geofence", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "syncRegions":
        let args = call.arguments as? [String: Any]
        let raw = args?["regions"] as? [[String: Any]] ?? []
        result(self.syncRegions(raw))
      case "drainPending":
        result(self.drainPending())
      case "permissionStatus":
        result(self.permissionStatus())
      case "requestBackgroundPermission":
        self.manager.requestAlwaysAuthorization()
        result(self.permissionStatus())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func syncRegions(_ raw: [[String: Any]]) -> Bool {
    // Persist the desired set for inspection/relaunch; the OS keeps
    // its own registration across reboots.
    UserDefaults.standard.set(raw, forKey: defaultsKeyRegions)
    for region in manager.monitoredRegions {
      manager.stopMonitoring(for: region)
    }
    for entry in raw.prefix(20) {
      guard let id = entry["id"] as? String,
        let lat = (entry["lat"] as? NSNumber)?.doubleValue,
        let lng = (entry["lng"] as? NSNumber)?.doubleValue,
        let radius = (entry["radiusM"] as? NSNumber)?.doubleValue
      else { continue }
      let capped = min(radius, manager.maximumRegionMonitoringDistance)
      let region = CLCircularRegion(
        center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
        radius: max(capped, 50),
        identifier: id)
      region.notifyOnEntry = true
      region.notifyOnExit = true
      manager.startMonitoring(for: region)
    }
    return CLLocationManager.authorizationStatus() == .authorizedAlways
  }

  private func permissionStatus() -> String {
    switch CLLocationManager.authorizationStatus() {
    case .authorizedAlways: return "always"
    case .authorizedWhenInUse: return "whenInUse"
    case .notDetermined: return "denied"
    case .denied, .restricted: return "denied"
    @unknown default: return "unsupported"
    }
  }

  // MARK: - CLLocationManagerDelegate

  func locationManager(
    _ manager: CLLocationManager, didEnterRegion region: CLRegion
  ) {
    record(zoneId: region.identifier, enter: true)
  }

  func locationManager(
    _ manager: CLLocationManager, didExitRegion region: CLRegion
  ) {
    record(zoneId: region.identifier, enter: false)
  }

  func locationManager(
    _ manager: CLLocationManager,
    monitoringDidFailFor region: CLRegion?,
    withError error: Error
  ) {
    // Silent by contract: monitoring failures degrade to the Dart
    // in-app evaluation fallback; nothing here may crash or block.
  }

  private func record(zoneId: String, enter: Bool) {
    let ts = Int64(Date().timeIntervalSince1970 * 1000)
    appendPending(zoneId: zoneId, enter: enter, ts: ts)
    channel?.invokeMethod(
      "onTransition",
      arguments: [
        "zoneId": zoneId,
        "transition": enter ? "enter" : "exit",
        "ts": ts,
      ])
  }

  private func appendPending(zoneId: String, enter: Bool, ts: Int64) {
    var items =
      UserDefaults.standard.array(forKey: defaultsKeyPending)
      as? [[String: Any]] ?? []
    items.append([
      "zoneId": zoneId,
      "transition": enter ? "enter" : "exit",
      "ts": ts,
    ])
    if items.count > 200 {
      items = Array(items.suffix(200))
    }
    UserDefaults.standard.set(items, forKey: defaultsKeyPending)
  }

  private func drainPending() -> [[String: Any]] {
    let items =
      UserDefaults.standard.array(forKey: defaultsKeyPending)
      as? [[String: Any]] ?? []
    UserDefaults.standard.removeObject(forKey: defaultsKeyPending)
    return items
  }
}
