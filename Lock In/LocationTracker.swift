//
//  LocationTracker.swift
//  Lock In
//
//  Created by Zhi on 9/7/25.
//

import Foundation
import CoreLocation
import UserNotifications

final class LocationTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var authStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 25
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .other
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true

        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }

        handleAuth(manager.authorizationStatus)
        manager.requestLocation()
    }

    /// Call this from UI to (re)kick the flow if needed.
    func kick() {
        handleAuth(manager.authorizationStatus)
        if CLLocationManager.locationServicesEnabled() {
            manager.requestLocation()
        }
    }

    /// Escalate to Always after When-In-Use is granted.
    func requestAlwaysAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            start()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    private func start() {
        manager.startUpdatingLocation()
    }

    // MARK: - Delegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authStatus = manager.authorizationStatus
        handleAuth(manager.authorizationStatus)
    }

    private func handleAuth(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            start()
        case .denied, .restricted:
            coordinate = nil
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let last = locations.last {
            DispatchQueue.main.async {
                self.coordinate = last.coordinate
                print("CL update:", last.coordinate)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error:", error.localizedDescription)
    }
}

struct GeoPoint: Codable, Equatable {
    var lat: Double
    var lon: Double
}

// Distance helper
func isStillHere(current: CLLocationCoordinate2D?, saved: GeoPoint?, thresholdMeters: Double = 150) -> Bool {
    guard let c = current, let s = saved else { return true }
    let a = CLLocation(latitude: c.latitude, longitude: s.lon)
    let b = CLLocation(latitude: s.lat, longitude: s.lon)
    return a.distance(from: b) <= thresholdMeters
}

// Local notifications
enum Notifier {
    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }
}
