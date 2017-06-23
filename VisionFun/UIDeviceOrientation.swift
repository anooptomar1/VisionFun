import UIKit
import AVFoundation

extension UIDeviceOrientation {
    var videoOrientation: AVCaptureVideoOrientation {
        return AVCaptureVideoOrientation(rawValue: UIDevice.current.orientation.rawValue) ?? .portrait
    }
}
