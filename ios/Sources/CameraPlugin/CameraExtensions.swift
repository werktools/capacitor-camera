import UIKit
import Photos
import CoreLocation
import ImageIO
import Capacitor

internal protocol CameraAuthorizationState {
    var authorizationState: String { get }
}

extension AVAuthorizationStatus: CameraAuthorizationState {
    var authorizationState: String {
        switch self {
        case .denied, .restricted:
            return "denied"
        case .authorized:
            return "granted"
        case .notDetermined:
            fallthrough
        @unknown default:
            return "prompt"
        }
    }
}

extension PHAuthorizationStatus: CameraAuthorizationState {
    var authorizationState: String {
        switch self {
        case .denied, .restricted:
            return "denied"
        case .authorized:
            return "granted"
        case .limited:
            return "limited"
        case .notDetermined:
            fallthrough
        @unknown default:
            return "prompt"
        }
    }
}

internal extension PHAsset {
    /**
     Retrieves the image metadata for the asset.
     */
    var imageData: [String: Any] {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.resizeMode = .none
        options.isNetworkAccessAllowed = false
        options.version = .current

        var result: [String: Any] = [:]
        _ = PHCachingImageManager().requestImageDataAndOrientation(for: self, options: options) { (data, _, _, _) in
            if let data = data as NSData? {
                let options = [kCGImageSourceShouldCache as String: kCFBooleanFalse] as CFDictionary
                if let imgSrc = CGImageSourceCreateWithData(data, options),
                   let metadata = CGImageSourceCopyPropertiesAtIndex(imgSrc, 0, options) as? [String: Any] {
                    result = metadata
                }
            }
        }
        return result
    }
}

internal extension UIImage {
    /**
     Generates a new image from the existing one, implicitly resetting any orientation.
     Dimensions greater than 0 will resize the image while preserving the aspect ratio.
     */
    func reformat(to size: CGSize? = nil) -> UIImage {
        let imageHeight = self.size.height
        let imageWidth = self.size.width
        // determine the max dimensions, 0 is treated as 'no restriction'
        var maxWidth: CGFloat
        if let size = size, size.width > 0 {
            maxWidth = size.width
        } else {
            maxWidth = imageWidth
        }
        let maxHeight: CGFloat
        if let size = size, size.height > 0 {
            maxHeight = size.height
        } else {
            maxHeight = imageHeight
        }
        // adjust to preserve aspect ratio
        var targetWidth = min(imageWidth, maxWidth)
        var targetHeight = (imageHeight * targetWidth) / imageWidth
        if targetHeight > maxHeight {
            targetWidth = (imageWidth * maxHeight) / imageHeight
            targetHeight = maxHeight
        }
        // generate the new image and return
        UIGraphicsBeginImageContextWithOptions(.init(width: targetWidth, height: targetHeight), false, 1.0) // size, opaque and scale
        self.draw(in: .init(origin: .zero, size: .init(width: targetWidth, height: targetHeight)))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resizedImage ?? self
    }
}

internal extension Data {

    /// Returns new image data with a GPS EXIF dictionary injected from `location`. Uses ImageIO to copy the existing image data through
    /// unchanged (pixels, EXIF, TIFF, orientation, etc.) and only merge in the GPS keys - no re-encoding, no quality loss.
    ///
    /// Returns `self` unchanged if the data isn't a recognisable image or the tagging step otherwise fails - geotagging is best-effort and
    /// should never turn a successful capture into a failed one.
    func taggingGPSLocationAndTime(_ location: CLLocation, creationDate: Date) -> Data {
        guard let source = CGImageSourceCreateWithData(self as CFData, nil),
              let type = CGImageSourceGetType(source)
        else { return self }

        var metadata = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        metadata[kCGImagePropertyGPSDictionary] = Self.gpsDictionary(for: location)
        metadata[kCGImagePropertyExifDictionary] = Self.exifDictionary(for: creationDate)

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return self }

        CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { return self }

        return output as Data
    }

    private static func exifDictionary(for creationDate: Date) -> [CFString: Any] {
        var exifDict: [CFString: Any] = [:]
        // let currentLocalTimeZone = TimeZone.current
        // let dateFormatter = DateFormatter()
        // dateFormatter.timeZone = currentLocalTimeZone
        // dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss.SSSSSS"
        // exifDict[kCGImagePropertyExifDateTimeDigitized] = dateFormatter.string(from: creationDate)

        let currentDateValue = currentDateString(date: creationDate)
        exifDict[kCGImagePropertyExifDateTimeOriginal] = currentDateValue
        exifDict[kCGImagePropertyExifDateTimeDigitized] = currentDateValue

        let exifOffsetValue = currentUTCOffsetString()
        exifDict[kCGImagePropertyExifOffsetTime] = exifOffsetValue
        exifDict[kCGImagePropertyExifOffsetTimeDigitized] = exifOffsetValue
        exifDict[kCGImagePropertyExifOffsetTimeOriginal] = exifOffsetValue

        return exifDict
    }

    private static func currentDateString(date: Date) -> String {
        let formatter = DateFormatter()
        let currentLocalTimeZone = TimeZone.current
        formatter.timeZone = currentLocalTimeZone
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss.SSSSSS"
        return formatter.string(from: date)
    }

    private static func currentUTCOffsetString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ZZZZZ" // ISO 8601 style: +05:30
        return formatter.string(from: Date())
    }

    private static func gpsDictionary(for location: CLLocation) -> [CFString: Any] {
        var gps: [CFString: Any] = [:]

        let coordinate = location.coordinate
        gps[kCGImagePropertyGPSLatitude] = abs(coordinate.latitude)
        gps[kCGImagePropertyGPSLatitudeRef] = coordinate.latitude >= 0 ? "N" : "S"

        gps[kCGImagePropertyGPSLongitude] = abs(coordinate.longitude)
        gps[kCGImagePropertyGPSLongitudeRef] = coordinate.longitude >= 0 ? "E" : "W"

        // verticalAccuracy < 0 means altitude is invalid.
        if location.verticalAccuracy >= 0 {
            gps[kCGImagePropertyGPSAltitude] = abs(location.altitude)
            gps[kCGImagePropertyGPSAltitudeRef] = location.altitude >= 0 ? 0 : 1 // 0 = above sea level, 1 = below
        }
        if location.horizontalAccuracy >= 0 {
            gps[kCGImagePropertyGPSHPositioningError] = location.horizontalAccuracy
        }

        let dateFormatter = DateFormatter()
        let utc = TimeZone(identifier: "UTC")
        dateFormatter.timeZone = utc
        dateFormatter.dateFormat = "yyyy:MM:dd"
        gps[kCGImagePropertyGPSDateStamp] = dateFormatter.string(from: location.timestamp)

        let timeFormatter = DateFormatter()
        timeFormatter.timeZone = utc
        timeFormatter.dateFormat = "HH:mm:ss.SSSSSS"
        gps[kCGImagePropertyGPSTimeStamp] = timeFormatter.string(from: location.timestamp)

        gps[kCGImagePropertyGPSVersion] = "2.3.0.0"

        return gps
    }
}
