import UIKit
import AVFoundation
import Vision

enum VideoCaptureError {
    case error(description: String)
}

class VideoCaptureViewController: UIViewController {
    
    // MARK: - Outlets
    
    @IBOutlet var blurView: UIVisualEffectView!
    @IBOutlet var tableView: UITableView!
    @IBOutlet var hideTableViewConstraint: NSLayoutConstraint!
    
    // MARK: - Stored Properties
    
    private var captureSession: AVCaptureSession?
    private static let sessionPreset = AVCaptureSession.Preset.high
    fileprivate var previewLayer: AVCaptureVideoPreviewLayer?
    
    private var requests = [VNRequest]()
    
    private let shapeLayer = CAShapeLayer()
    private var classifications: [VNClassificationObservation] = []
    
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
        } catch {
            print(error)
        }
        
        self.blurView.layer.maskedCorners = [
            .layerMinXMinYCorner, .layerMaxXMinYCorner
        ]
        self.blurView.layer.masksToBounds = true
        self.blurView.layer.cornerRadius = 10
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
        shapeLayer.fillColor = UIColor.yellow.withAlphaComponent(0.5).cgColor
        self.previewLayer?.addSublayer(shapeLayer)
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
        rectangleDetectionRequest?.maximumObservations = 100
        
        self.requests = [
            classificationRequest!
        ]
    }
    
    func handleClassifications(request: VNRequest, error: Error?) {
        guard let observations = request.results as? [VNClassificationObservation] else { return }
        
        DispatchQueue.main.async {
            self.classifications = observations.filter({ $0.confidence > 0.1 })
            self.tableView.reloadData()
        }
    }
    
    func handleRectangles(request: VNRequest, error: Error?) {
        DispatchQueue.main.async {
            guard let results = request.results as? [VNObservation] else { return }
            self.draw(visionRequestResults: results)
        }
    }
    
    private func draw(visionRequestResults results: [VNObservation]) {
        guard let previewLayer = self.previewLayer else { return }
        
        let flipVertically: (CGPoint) -> CGPoint = { point in
            return CGPoint(
                x: point.x,
                y: 1.0 - point.y
            )
        }
        let path = UIBezierPath()
        
        let observations = results.flatMap({ $0 as? VNRectangleObservation })
        
        for observation in observations {
            let topLeft = flipVertically(observation.topLeft)
            let topRight = flipVertically(observation.topRight)
            let bottomRight = flipVertically(observation.bottomRight)
            let bottomLeft = flipVertically(observation.bottomLeft)
            
            path.move(to: previewLayer.layerPointConverted(fromCaptureDevicePoint: topLeft))
            path.addLine(to: previewLayer.layerPointConverted(fromCaptureDevicePoint: topRight))
            path.addLine(to: previewLayer.layerPointConverted(fromCaptureDevicePoint: bottomRight))
            path.addLine(to: previewLayer.layerPointConverted(fromCaptureDevicePoint: bottomLeft))
            
            path.close()
        }
        
        shapeLayer.path = path.cgPath
    }
    
    // MARK: - Actions
    
    @IBAction func selectionChanged(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0: // Classifications
            guard let classificationRequest = self.classificationRequest else { return }
            requests = [classificationRequest]
            
            shapeLayer.isHidden = true
            setTableViewVisibility(visible: true)
            
        case 1: // Rectangles
            guard let rectangleDetectionRequest = self.rectangleDetectionRequest else { return }
            requests = [rectangleDetectionRequest]
            
            shapeLayer.isHidden = false
            setTableViewVisibility(visible: false)
            
        default:
            break
        }
    }
    
    // MARK: - View Helpers
    
    private func setTableViewVisibility(visible: Bool) {
        hideTableViewConstraint.priority = visible ? .defaultLow : .defaultHigh
        
        UIView.animate(
            withDuration: 0.3,
            delay: 0.0,
            usingSpringWithDamping: 1.0,
            initialSpringVelocity: 2.0,
            options: [],
            animations: { self.view.layoutIfNeeded() },
            completion: nil
        )
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension VideoCaptureViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection)
    {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        var requestOptions: [VNImageOption: Any] = [:]
        
        if let cameraIntrinsicData = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil) {
            requestOptions = [.cameraIntrinsics: cameraIntrinsicData]
        }
        
        let imageRequestHandler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            options: requestOptions
        )
        
        do {
            try imageRequestHandler.perform(self.requests)
        } catch {
            print(error)
        }
    }
}

extension VideoCaptureViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.classifications.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "classificationCell", for: indexPath) as! ClassificationCell
        
        let classification = self.classifications[indexPath.row]
        cell.update(with: classification)
        
        return cell
    }
}


class ClassificationCell: UITableViewCell {
    
    // MARK: - Outlets
    
    @IBOutlet var classificationLabel: UILabel!
    @IBOutlet var confidenceLabel: UILabel!
    
    // MARK: - Update
    
    func update(with classification: VNClassificationObservation) {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .percent
        
        self.classificationLabel.text = classification.identifier
        
        let confidence = NSNumber(value: classification.confidence)
        self.confidenceLabel.text = numberFormatter.string(from: confidence)
    }
}
