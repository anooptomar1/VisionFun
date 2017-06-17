import UIKit
import AVFoundation

extension UIDeviceOrientation {
    var videoOrientation: AVCaptureVideoOrientation {
        guard let videoOrientation = AVCaptureVideoOrientation(
            rawValue: UIDevice.current.orientation.rawValue)
            else {
                return .portrait
        }
        
        return videoOrientation
    }
}

