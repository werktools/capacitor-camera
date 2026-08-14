import CoreLocation

/// Resolves a single, best-effort device location fix, used to embed GPS EXIF metadata in photos taken with `includeLocation` set.
///
/// Requesting a location for the first time triggers the system location permission prompt automatically (via
/// `CLLocationManager.requestWhenInUseAuthorization()`). Requires `NSLocationWhenInUseUsageDescription` in the host app's `Info.plist`.
///
/// Fails open: denied/restricted permission, disabled location services, or a timeout all resolve `nil` rather than throwing - a missing
/// location should never block or fail photo capture.
final class CameraLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let timeout: TimeInterval
    private var completion: ((CLLocation?) -> Void)?
    private var timeoutWorkItem: DispatchWorkItem?

    init(timeout: TimeInterval = 5.0) {
        self.timeout = timeout
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Requests a single location fix. Safe to call from the main thread. `completion` is always called exactly once, on the main thread.
    func requestLocation(completion: @escaping (CLLocation?) -> Void) {
        self.completion = completion

        guard CLLocationManager.locationServicesEnabled() else {
            return finish(nil)
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            // Resumes in locationManagerDidChangeAuthorization once the user responds to the system prompt.
        case .denied, .restricted:
            finish(nil)
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdating()
        @unknown default:
            finish(nil)
        }
    }

    private func startUpdating() {
        let workItem = DispatchWorkItem { [weak self] in self?.finish(nil) }
        timeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
        manager.requestLocation()
    }

    private func finish(_ location: CLLocation?) {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        let pending = completion
        completion = nil
        manager.stopUpdatingLocation()

        if Thread.isMainThread {
            pending?(location)
        } else {
            DispatchQueue.main.async { pending?(location) }
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Only proceed if a request is actually pending, so we don't act on unrelated authorization changes.
        guard completion != nil else { return }

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdating()
        case .denied, .restricted:
            finish(nil)
        case .notDetermined:
            break
        @unknown default:
            finish(nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }
}
