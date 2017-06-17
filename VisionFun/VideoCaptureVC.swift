import UIKit
import AVFoundation
import Vision

enum VideoCaptureError {
    case error(description: String)
}

class VideoCaptureViewController: UIViewController {
    
    // MARK: - Outlets
    
    @IBOutlet var classificationLabel: UILabel!
    
    // MARK: - Stored Properties
    
    private var captureSession: AVCaptureSession?
    private static let sessionPreset = AVCaptureSession.Preset.high
    fileprivate var previewLayer: AVCaptureVideoPreviewLayer?
    
    private var requests = [VNRequest]()
    
    private let shapeLayer = CAShapeLayer()
    
    // MARK: - Computed Properties
    
    fileprivate var videoOrientation: AVCaptureVideoOrientation {
        return UIDevice.current.orientation.videoOrientation
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupViews()
        setupVision()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        captureSession?.startRunning()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        updateOrientations()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        captureSession?.stopRunning()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.previewLayer?.frame = self.view.bounds
    }
    
    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator)
    {
        updateOrientations()
        
        super.viewWillTransition(to: size, with: coordinator)
    }
    
    private func updateOrientations() {
        previewLayer?.connection?.videoOrientation = videoOrientation
    }
    
    // MARK: - Setup
    
    private func setupViews() {
        do {
            try captureSession = makeVideoCaptureSession()
            try addPreviewLayer(for: captureSession!, to: self.view)
            try addVideoDataOutput(to: captureSession!)
            addShapeLayer()
            classificationLabel.isHidden = true
        } catch {
            print(error)
        }
    }
    
    private func makeVideoCaptureSession() throws -> AVCaptureSession {
        let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        )!
        let videoInput = try AVCaptureDeviceInput(device: camera)
        
        let session = AVCaptureSession()
        session.sessionPreset = VideoCaptureViewController.sessionPreset
        
        session.addInput(videoInput)
        
        return session
    }
    
    private func addPreviewLayer(
        for session: AVCaptureSession,
        to previewView: UIView) throws
    {
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        self.previewLayer = previewLayer
        
        previewLayer.frame = previewView.bounds
        previewLayer.videoGravity = .resizeAspectFill
        
        previewView.layer.insertSublayer(previewLayer, at: 0)
    }
    
    private func addVideoDataOutput(to session: AVCaptureSession) throws {
        let videoDataOutput = AVCaptureVideoDataOutput()
        
        let queue = DispatchQueue(
            label: "VideoDataOutput.SampleBufferDelegate",
            qos: .default
        )
        
        videoDataOutput.setSampleBufferDelegate(self, queue: queue)
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA as UInt32)
        ]
        
        session.addOutput(videoDataOutput)
    }
    
    private func addShapeLayer() {
        shapeLayer.fillColor = UIColor.yellow.cgColor
        self.view.layer.addSublayer(shapeLayer)
    }
    
    // MARK: - Vision
    
    private var classificationRequest: VNCoreMLRequest?
    private var rectangleDetectionRequest: VNDetectRectanglesRequest?
    
    private func setupVision() {
        
        // Classifications
        
        guard let visionModel = try? VNCoreMLModel(for: Inceptionv3().model) else {
            fatalError("Failed to load ML model")
        }
        self.classificationRequest = VNCoreMLRequest(
            model: visionModel,
            completionHandler: handleClassifications
        )
        classificationRequest?.imageCropAndScaleOption = VNImageCropAndScaleOptionCenterCrop
        
        // Rectangles
        
        self.rectangleDetectionRequest = VNDetectRectanglesRequest(
            completionHandler: self.handleRectangles
        )
        rectangleDetectionRequest?.minimumSize = 0.2
        rectangleDetectionRequest?.maximumObservations = 5
        
        self.requests = [
            rectangleDetectionRequest!
        ]
    }
    
    func handleClassifications(request: VNRequest, error: Error?) {
        guard let observations = request.results as? [VNClassificationObservation] else { return }
        
        let classifications = observations[0...4].filter({ $0.confidence > 0.3 })
        let classificationMessages = classifications.map({ "\($0.identifier)\nconfidence: \($0.confidence)" })
        
        DispatchQueue.main.async {
            self.classificationLabel.text = classificationMessages.joined(separator: "\n\n")
        }
    }
    
    func handleRectangles(request: VNRequest, error: Error?) {
        DispatchQueue.main.async {
            guard let results = request.results as? [VNObservation] else { return }
            self.draw(visionRequestResults: results)
        }
    }
    
    private func draw(visionRequestResults results: [VNObservation]) {
        guard let observation = results.first as? VNRectangleObservation else { return }
        
        let viewSize = self.view.bounds.size
        
        let path = UIBezierPath()
        
        path.move(to: observation.topLeft.scaled(to: viewSize))
        path.addLine(to: observation.topRight.scaled(to: viewSize))
        path.addLine(to: observation.bottomRight.scaled(to: viewSize))
        path.addLine(to: observation.bottomLeft.scaled(to: viewSize))
        path.close()
        
        shapeLayer.path = path.cgPath
    }
    
    
    @IBAction func selectionChanged(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0: // Rectangles
            guard let rectangleDetectionRequest = self.rectangleDetectionRequest else { return }
            requests = [rectangleDetectionRequest]
            
            classificationLabel.isHidden = true
            shapeLayer.isHidden = false
            
        case 1: // Classifications
            guard let classificationRequest = self.classificationRequest else { return }
            requests = [classificationRequest]
            
            classificationLabel.isHidden = false
            shapeLayer.isHidden = true
            
        default:
            break
        }
    }
}

extension VideoCaptureViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection)
    {
        connection.videoOrientation = UIDevice.current.orientation.videoOrientation
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        var requestOptions: [VNImageOption: Any] = [:]
        
        if let cameraIntrinsicData = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil)
        {
            requestOptions = [.cameraIntrinsics: cameraIntrinsicData]
        }
        
        let exifOrientation = getExifOrientation()
        
        let imageRequestHandler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: exifOrientation,
            options: requestOptions
        )
        
        do {
            try imageRequestHandler.perform(self.requests)
        } catch {
            print(error)
        }
    }
    
    private func getExifOrientation() -> Int32 {
        // TODO: Figure out how to actually calculate this.
        return 4
    }
}

