import XCTest
import CoreLocation
import ImageIO
@testable import CameraPlugin

final class CameraPluginTests: XCTestCase {

    /// Small JPEG generated at test time so the test has no binary fixture dependency.
    private func makeTestJPEGData() -> Data {
        let size = CGSize(width: 4, height: 4)
        UIGraphicsBeginImageContext(size)
        defer { UIGraphicsEndImageContext() }
        UIColor.white.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        return image.jpegData(compressionQuality: 0.9)!
    }

    private func gpsDictionary(from data: Data) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        return properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]
    }

    func testTaggingGPSLocationAndTime_addsExpectedGPSFields() throws {
        let data = makeTestJPEGData()
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 15,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let tagged = data.taggingGPSLocationAndTime(location, Date.now())
        let gps = try XCTUnwrap(gpsDictionary(from: tagged))

        XCTAssertEqual(gps[kCGImagePropertyGPSLatitude] as? Double ?? 0, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(gps[kCGImagePropertyGPSLatitudeRef] as? String, "N")
        XCTAssertEqual(gps[kCGImagePropertyGPSLongitude] as? Double ?? 0, 122.4194, accuracy: 0.0001)
        XCTAssertEqual(gps[kCGImagePropertyGPSLongitudeRef] as? String, "W")
    }

    func testTaggingGPSLocationAndTime_southernAndEasternHemisphereRefsAreCorrect() throws {
        let data = makeTestJPEGData()
        let location = CLLocation(latitude: -33.8688, longitude: 151.2093) // Sydney

        let tagged = data.taggingGPSLocationAndTime(location, Date.now())
        let gps = try XCTUnwrap(gpsDictionary(from: tagged))

        XCTAssertEqual(gps[kCGImagePropertyGPSLatitudeRef] as? String, "S")
        XCTAssertEqual(gps[kCGImagePropertyGPSLongitudeRef] as? String, "E")
    }

    func testTaggingGPSLocationAndTime_preservesExistingImageData() throws {
        let data = makeTestJPEGData()
        let location = CLLocation(latitude: 0, longitude: 0)

        let tagged = data.taggingGPSLocationAndTime(location, Date.now())

        // The pixel data should still decode to an image of the same dimensions - tagging must not corrupt or
        // re-encode the underlying image.
        let original = UIImage(data: data)
        let result = UIImage(data: tagged)
        XCTAssertEqual(original?.size, result?.size)
    }

    func testTaggingGPSLocationAndTime_invalidImageData_returnsInputUnchanged() {
        let garbage = Data([0x00, 0x01, 0x02])
        let location = CLLocation(latitude: 0, longitude: 0)

        let result = garbage.taggingGPSLocationAndTime(location, Date.now())

        XCTAssertEqual(result, garbage)
    }
}
