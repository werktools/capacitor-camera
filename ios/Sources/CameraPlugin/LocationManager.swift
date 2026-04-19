import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    private let locationManager = CLLocationManager()

    @Published var locationStatus: CLAuthorizationStatus?
    @Published var lastLocation: CLLocation?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        locationStatus = status

        switch status {
        case .notDetermined:
            print("no location data - permission notDetermined")
        case .restricted:
            print("no location data - permission restricted")
        case .denied:
            print("no location data - permission denied")
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
        @unknown default:
            print("no location data - unknown status")
        }
    }
 
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
    }

    func createLocationMetadata() -> Dictionary<String, Any> {
        
        var gpsDictionary = Dictionary<String, Any>()
        
        guard ( CLLocationManager.authorizationStatus() == .authorizedWhenInUse
                || CLLocationManager.authorizationStatus() == .authorizedAlways )
                else { return gpsDictionary }
        
        if let location = lastLocation {
            var latitude = location.coordinate.latitude
            var longitude = location.coordinate.longitude
            var altitude = location.altitude
            var latitudeRef = "N"
            var longitudeRef = "E"
            var altitudeRef = 0

            if latitude < 0.0 {
                latitude = -latitude
                latitudeRef = "S"
            }

            if longitude < 0.0 {
                longitude = -longitude
                longitudeRef = "W"
            }

            if altitude < 0.0 {
                altitude = -altitude
                altitudeRef = 1
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy:MM:dd"
            gpsDictionary[kCGImagePropertyGPSDateStamp as String] = formatter.string(from:location.timestamp)
            formatter.dateFormat = "HH:mm:ss"
            gpsDictionary[kCGImagePropertyGPSTimeStamp as String] = formatter.string(from:location.timestamp)
            gpsDictionary[kCGImagePropertyGPSLatitudeRef as String] = latitudeRef
            gpsDictionary[kCGImagePropertyGPSLatitude as String] = latitude
            gpsDictionary[kCGImagePropertyGPSLongitudeRef as String] = longitudeRef
            gpsDictionary[kCGImagePropertyGPSLongitude as String] = longitude
            gpsDictionary[kCGImagePropertyGPSDOP as String] = location.horizontalAccuracy
            gpsDictionary[kCGImagePropertyGPSAltitudeRef as String] = altitudeRef
            gpsDictionary[kCGImagePropertyGPSAltitude as String] = altitude

            if let heading = locationManager.heading {
                gpsDictionary[kCGImagePropertyGPSImgDirectionRef as String] = "T"
                gpsDictionary[kCGImagePropertyGPSImgDirection as String] = heading.trueHeading
            }
        }
        
        return gpsDictionary
    }
}
