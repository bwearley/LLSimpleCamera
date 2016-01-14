//
//  LLSimpleCamera.swift
//
//  Created by Brian Earley on 1/11/16.
//

import UIKit
import AVFoundation
import ImageIO

enum LLCameraPosition {
    case Rear
    case Front
}

enum LLCameraFlash {
    case Off // The default state has to be off
    case On
    case Auto
}

enum LLCameraMirror {
    case Off // The default state has to be off
    case On
    case Auto
}

enum LLSimpleCameraErrorCode:ErrorType {
    case CameraPermission// = 10
    case MicrophonePermission// = 11
    case Session// = 12
    case VideoNotEnabled// = 13
}

class LLSimpleCamera: UIViewController, AVCaptureFileOutputRecordingDelegate {

    let LLSimpleCameraErrorDomain = "LLSimpleCameraErrorDomain"

    private var preview:UIView!
    private var stillImageOutput:AVCaptureStillImageOutput!
    private var session:AVCaptureSession!
    private var videoCaptureDevice:AVCaptureDevice!
    private var audioCaptureDevice:AVCaptureDevice!
    private var videoDeviceInput:AVCaptureDeviceInput!
    private var audioDeviceInput:AVCaptureDeviceInput!
    private var captureVideoPreviewLayer:AVCaptureVideoPreviewLayer!
    private var tapGesture:UITapGestureRecognizer!
    private var focusBoxLayer:CALayer!
    private var focusBoxAnimation:CAAnimation!
    private var movieFileOutput:AVCaptureMovieFileOutput!
    private var cameraPosition:LLCameraPosition!

    var didRecord:((LLSimpleCamera,NSURL) -> Void)!

    /**
     * Triggered on device change.
     */
     //@property (nonatomic, copy) void (^onDeviceChange)(LLSimpleCamera *camera, AVCaptureDevice *device);
    var onDeviceChange:((LLSimpleCamera!, AVCaptureDevice!) -> Void)!

    /**
     * Triggered on any kind of error.
     */
     //@property (nonatomic, copy) void (^onError)(LLSimpleCamera *camera, NSError *error);
    var onError:((LLSimpleCamera, NSError) -> Void)!

    /**
     * Camera quality, set a constants prefixed with AVCaptureSessionPreset.
     * Make sure to call before calling -(void)initialize method, otherwise it would be late.
     */
    var cameraQuality:String!

    var flash:LLCameraFlash! // Camera flash mode
    var mirror:LLCameraMirror! // Camera mirror mode
    var position:LLCameraPosition! // Position of the camera
    var videoEnabled:Bool! // Boolean value to indicate if the video is enabled
    var recording:Bool! // Boolean value to indicate if the camera is recording a video at the current moment
    var tapToFocus:Bool! // Set NO if you don't want to enable user triggered focusing. Enabled by default.

    /**
    * Fixes the orientation after the image is captured is set to Yes.
    * see: http://stackoverflow.com/questions/5427656/ios-uiimagepickercontroller-result-image-orientation-after-upload
    */
    var fixOrientationAfterCapture:Bool!

    /**
     * Set YES if your view controller does not allow autorotation,
     * however you want to take the device rotation into account no matter what. Disabled by default.
     */
    var useDeviceOrientation:Bool!

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.setupWithQuality(AVCaptureSessionPresetHigh, position:.Rear, videoEnabled:true)
    }

    convenience init()
    {
        self.init(withVideoEnabled:false)
    }

    convenience init(withVideoEnabled videoEnabled:Bool) {
        self.init(withQuality: AVCaptureSessionPresetHigh, position:.Rear, videoEnabled:videoEnabled)
    }

    init(withQuality quality:String, position:LLCameraPosition, videoEnabled:Bool) {
        super.init(nibName: nil, bundle: nil)
        self.setupWithQuality(quality, position:position, videoEnabled:videoEnabled)
    }


    func setupWithQuality(quality:String, position:LLCameraPosition, videoEnabled:Bool) {
        self.cameraQuality = quality
        self.position = position
        self.fixOrientationAfterCapture = false
        self.tapToFocus = true
        self.useDeviceOrientation = false
        self.flash = .Off
        self.mirror = .Auto
        self.videoEnabled = videoEnabled
        self.recording = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = UIColor.clearColor()
        self.view.autoresizingMask = .None

        self.preview = UIView(frame: CGRectZero)
        self.preview.backgroundColor = UIColor.clearColor()
        self.view.addSubview(self.preview)

        // tap to focus
        self.tapGesture = UITapGestureRecognizer(target: self, action: Selector("previewTapped:"))
        self.tapGesture.numberOfTapsRequired = 1
        self.tapGesture.delaysTouchesEnded = false
        self.preview.addGestureRecognizer(self.tapGesture)

        // add focus box to view
        self.addDefaultFocusBox()
    }

    // Mark: Camera

    func attachToViewController(vc:UIViewController, withFrame frame:CGRect) {
        vc.view.addSubview(self.view)
        vc.addChildViewController(self)
        self.didMoveToParentViewController(vc)
        vc.view.frame = frame
    }

    func start() {
        LLSimpleCamera.requestCameraPermission() {
            granted in
            if (granted)
            {
                // Request microphone permission if video is enabled
                if (self.videoEnabled == true)
                {
                    LLSimpleCamera.requestMicrophonePermission() {
                        granted in
                        if (granted)
                        {
                            self.initialize()
                        }
                        else
                        {
                            //throw LLSimpleCameraErrorCode.LLSimpleCameraErrorCodeMicrophonePermission
                        }
                    }
                }
                else
                {
                    self.initialize()
                }
            }
            else
            {
                //throw LLSimpleCameraErrorCode.LLSimpleCameraErrorCodeCameraPermission
            }
        }

    }

    func initialize() {
        self.session = AVCaptureSession()
        self.session.sessionPreset = self.cameraQuality

        // preview layer
        let bounds:CGRect = self.preview.layer.bounds
        self.captureVideoPreviewLayer = AVCaptureVideoPreviewLayer(session: self.session)
        self.captureVideoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill
        self.captureVideoPreviewLayer.bounds = bounds
        self.captureVideoPreviewLayer.position = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds))
        self.preview.layer.addSublayer(self.captureVideoPreviewLayer)

        var devicePosition:AVCaptureDevicePosition
        switch self.position! {
        case .Rear:
            if LLSimpleCamera.isRearCameraAvailable() {
                devicePosition = AVCaptureDevicePosition.Back
            } else {
                devicePosition = AVCaptureDevicePosition.Front
                self.position = .Front
            }
        case .Front:
            if self.classForCoder.isFrontCameraAvailable() {
                devicePosition = AVCaptureDevicePosition.Front
            } else {
                devicePosition = AVCaptureDevicePosition.Back
                self.position = .Rear
            }
        default:
            devicePosition = AVCaptureDevicePosition.Unspecified
        }

        if devicePosition == AVCaptureDevicePosition.Unspecified {
            self.videoCaptureDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
        } else {
            self.videoCaptureDevice = self.cameraWithPosition(devicePosition)
        }

        do {
            self.videoDeviceInput = try AVCaptureDeviceInput(device: self.videoCaptureDevice)
        } catch let error as NSError { print("ERROR: \(error), \(error.userInfo)") }

        if self.session.canAddInput(self.videoDeviceInput) {
            self.session.addInput(self.videoDeviceInput)
            self.captureVideoPreviewLayer.connection.videoOrientation = self.orientationForConnection
        }

        // add audio if video is enabled
        if (self.videoEnabled != nil) {
            self.audioCaptureDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeAudio)
            do {
                self.audioDeviceInput = try AVCaptureDeviceInput(device: self.audioCaptureDevice)
            } catch let error as NSError { print("ERROR: \(error), \(error.userInfo)") }

            if self.session.canAddInput(self.audioDeviceInput) {
                self.session.addInput(self.audioDeviceInput)
            }

            self.movieFileOutput = AVCaptureMovieFileOutput()
            self.movieFileOutput.movieFragmentInterval = kCMTimeInvalid

            if self.session.canAddOutput(self.movieFileOutput) {
                self.session.addOutput(self.movieFileOutput)
            }
        }

        self.stillImageOutput = AVCaptureStillImageOutput()
        let outputSettings = [AVVideoCodecJPEG : AVVideoCodecKey]
        self.stillImageOutput.outputSettings = outputSettings
        self.session.addOutput(self.stillImageOutput)

        //if we had disabled the connection on capture, re-enable it
        if self.captureVideoPreviewLayer.connection.enabled {
            self.captureVideoPreviewLayer.connection.enabled = true
        }

        self.session.startRunning()
    }

    /**
     * Stops the running camera session. Needs to be called when the app doesn't show the view.
     */
    func stop() {
        self.session.stopRunning()
    }

    // MARK: - Image Capture

    func capture(onCaptureBlock:((LLSimpleCamera,UIImage,NSDictionary) -> Void), exactSeenImage:Bool) {
        if self.session == nil {
            onCaptureBlock(self,UIImage(),[:])
            return
        }

        // get connection and set orientation
        let videoConnection = self.captureConnection
        videoConnection.videoOrientation = self.orientationForConnection

        // freeze the screen
        self.captureVideoPreviewLayer.connection.enabled = false
        self.stillImageOutput.captureStillImageAsynchronouslyFromConnection(videoConnection) {
            imageSampleBuffer in

            var image = UIImage()
            var metaData = NSDictionary()

            let exifAttachments = CMGetAttachment(imageSampleBuffer as! CMAttachmentBearerRef, kCGImagePropertyExifDictionary, nil) as! CFDictionaryRef
            metaData = exifAttachments

            let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageSampleBuffer as! CMSampleBuffer)
            image = UIImage(data: imageData)!

            if (exactSeenImage) {
                image = self.cropImageUsingPreviewBounds(image)
            }

            if (self.fixOrientationAfterCapture == true) {
                image = image.fixOrientation()!
            }

            // trigger the block
            dispatch_async(dispatch_get_main_queue()) {
                onCaptureBlock(self,image,metaData)
            }
        }//)
    }

    func capture(onCapture:((LLSimpleCamera,UIImage,NSDictionary) -> Void)) {
        self.capture(onCapture, exactSeenImage:false)
    }

    // MARK: - Video Capture

    func startRecordingWithOutputUrl(url:NSURL) {
        // check if video is enabled
        if (!self.videoEnabled) {
            //NSError *error = [NSError errorWithDomain:LLSimpleCameraErrorDomain
            //code:LLSimpleCameraErrorCode.LLSimpleCameraErrorCodeVideoNotEnabled
            //userInfo:nil]
            //if(self.onError) {
            //self.onError(self, error)
            //}
            print("Error: LLSimpleCameraErrorCodeVideoNotEnabled")
            return
        }

        if self.flash == .On {
            self.enableTorch(true)
        }

        // set video orientation
        for connection in self.movieFileOutput.connections! as! [AVCaptureConnection] {
            for port in connection.inputPorts! as! [AVCaptureInputPort] {
                // get only the video media types
                if (port.mediaType == AVMediaTypeVideo) {
                    if connection.supportsVideoOrientation {
                        self.captureConnection.videoOrientation = self.orientationForConnection
                        //connection.videoOrientation = self.orientationForConnection // From original Objective-C
                    }
                }
            }
        }

        self.movieFileOutput.startRecordingToOutputFileURL(url, recordingDelegate:self)

    }

    /**
     * Stop recording video with a completion block.
     */
    func stopRecording(completionBlock:((LLSimpleCamera, NSURL) -> Void)) {
        if (!self.videoEnabled) {
            return
        }
        self.didRecord = completionBlock
        // Objective-C: self.didRecord = completionBlock;
        self.movieFileOutput.stopRecording()
    }

    func captureOutput(captureOutput: AVCaptureFileOutput!, didStartRecordingToOutputFileAtURL fileURL: NSURL!, fromConnections connections: [AnyObject]!) {
        self.recording = true
    }

    func captureOutput(captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAtURL outputFileURL: NSURL!, fromConnections connections: [AnyObject]!, error: NSError!) {
        self.recording = false
        self.enableTorch(false)

        if (self.didRecord != nil) {
            self.didRecord(self, outputFileURL)
        }
    }

    func enableTorch(enabled:Bool) {
        // check if the device has a torch, otherwise don't even bother to take any action.
        if (self.isTorchAvailable()) {
            self.session.beginConfiguration()
            try! self.videoCaptureDevice.lockForConfiguration()
            if (enabled) {
                self.videoCaptureDevice.torchMode = AVCaptureTorchMode.On
            } else {
                self.videoCaptureDevice.torchMode = AVCaptureTorchMode.Off
            }
            self.videoCaptureDevice.unlockForConfiguration()
            self.session.commitConfiguration()
        }
    }

    // MARK: - Helpers

    func cropImageUsingPreviewBounds(image:UIImage) -> UIImage {
        let previewBounds = self.captureVideoPreviewLayer.bounds
        let outputRect = self.captureVideoPreviewLayer.metadataOutputRectOfInterestForRect(previewBounds)

        let takenCGImage = image.CGImage
        let width/*:size_t*/ = CGImageGetWidth(takenCGImage)
        let height/*:size_t*/ = CGImageGetHeight(takenCGImage)
        let cropRect = CGRectMake(outputRect.origin.x * CGFloat(width), outputRect.origin.y * CGFloat(height),
            outputRect.size.width * CGFloat(width), outputRect.size.height * CGFloat(height))
        let cropCGImage = CGImageCreateWithImageInRect(takenCGImage, cropRect)
        return UIImage(CGImage: cropCGImage!, scale: 1, orientation: image.imageOrientation)
    }

    var captureConnection:AVCaptureConnection {
        var videoConnection:AVCaptureConnection!
        for connection in self.stillImageOutput.connections {
            for port in connection.inputPorts! {
                if port.mediaType == AVMediaTypeVideo {
                    videoConnection = connection as! AVCaptureConnection
                }
            }
        }
        return videoConnection
    }

    func setVideoCaptureDevice(videoCaptureDevice:AVCaptureDevice) {
        self.videoCaptureDevice = videoCaptureDevice

        if (videoCaptureDevice.flashMode == AVCaptureFlashMode.Auto) {
            self.flash = .Auto
        } else if (videoCaptureDevice.flashMode == AVCaptureFlashMode.On) {
            self.flash = .On
        } else if (videoCaptureDevice.flashMode == AVCaptureFlashMode.Off) {
            self.flash = .Off
        } else {
            self.flash = .Off
        }

        // trigger block
        self.onDeviceChange(self, videoCaptureDevice)
    }

    /**
     * Checks if flash is avilable for the currently active device.
     */
    func isFlashAvailable() -> Bool {
        return self.videoCaptureDevice.hasFlash && self.videoCaptureDevice.flashAvailable
    }

    /**
     * Checks if torch (flash for video) is avilable for the currently active device.
     */
    func isTorchAvailable() -> Bool {
        return self.videoCaptureDevice.hasTorch && self.videoCaptureDevice.torchAvailable
    }

    func updateFlashMode(cameraFlash:LLCameraFlash) -> Bool {
        if (self.session == nil) {
            return false
        }
        var flashMode:AVCaptureFlashMode

        if (cameraFlash == .On) {
            flashMode = AVCaptureFlashMode.On
        } else if (cameraFlash == .Auto) {
            flashMode = AVCaptureFlashMode.Auto
        } else {
            flashMode = AVCaptureFlashMode.Off
        }

        if (self.videoCaptureDevice.isFlashModeSupported(flashMode)) {
            do {
                try self.videoCaptureDevice.lockForConfiguration()
            } catch let error as NSError { print("ERROR: \(error), \(error.userInfo)") }
            self.videoCaptureDevice.flashMode = flashMode
            self.videoCaptureDevice.unlockForConfiguration()
            self.flash = cameraFlash
            return true
        } else {
            return false
        }
    }

    func setMirror(mirror:LLCameraMirror) {
        self.mirror = mirror

        if (self.session == nil) {
            return
        }

        let videoConnection:AVCaptureConnection = self.movieFileOutput.connectionWithMediaType(AVMediaTypeVideo)
        let pictureConnection:AVCaptureConnection = self.stillImageOutput.connectionWithMediaType(AVMediaTypeVideo)

        switch (mirror) {
        case .Off:
            if (videoConnection.supportsVideoMirroring) {
                videoConnection.videoMirrored = false
            }
            if (pictureConnection.supportsVideoMirroring) {
                pictureConnection.videoMirrored = false
            }
        case .On:
            if (videoConnection.supportsVideoMirroring) {
                videoConnection.videoMirrored = true
            }
            if (pictureConnection.supportsVideoMirroring) {
                pictureConnection.videoMirrored = true
            }
        case .Auto:
            let shouldMirror = (self.position == .Front)
            if (videoConnection.supportsVideoMirroring) {
                videoConnection.videoMirrored = shouldMirror
            }
            if (pictureConnection.supportsVideoMirroring) {
                pictureConnection.videoMirrored = shouldMirror
            }
        default:
            fatalError("Fatal error in LLSimpleCamera.setMirror") // Do we need this?
        }
        return
    }

    func togglePosition() -> LLCameraPosition {
        if (self.session == nil) {
            return self.position
        }
        if (self.position == .Rear) {
            self.cameraPosition = .Front
        } else {
            self.cameraPosition = .Rear
        }
        return self.position
    }

    func setCameraPosition(cameraPosition:LLCameraPosition) {
        if ((self.position == cameraPosition) || (self.session == nil)) {
            return
        }

        if ((cameraPosition == .Rear) && (!self.classForCoder.isRearCameraAvailable())) {
            return
        }

        if ((cameraPosition == .Front) && (!self.classForCoder.isFrontCameraAvailable())) {
            return
        }

        self.session.beginConfiguration()

        // remove existing input
        self.session.removeInput(self.videoDeviceInput)

        // get new input
        var device:AVCaptureDevice

        if (self.videoDeviceInput.device.position == AVCaptureDevicePosition.Back) {
            device = self.cameraWithPosition(AVCaptureDevicePosition.Front)
        } else {
            device = self.cameraWithPosition(AVCaptureDevicePosition.Back)
        }

        //if (device == nil) { return }

        // add input to session
        var videoInput:AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: device)
        } catch let error as NSError { print("ERROR: \(error), \(error.userInfo)"); self.session.commitConfiguration(); return }


        self.position = cameraPosition

        self.session.addInput(videoInput)
        self.session.commitConfiguration()

        self.videoCaptureDevice = device
        self.videoDeviceInput = videoInput

        self.setMirror(self.mirror)
    }

    // Find a camera with the specified AVCaptureDevicePosition, returning nil if one is not found
    func cameraWithPosition(position:AVCaptureDevicePosition) -> AVCaptureDevice! {
        let devices = AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo)

        for device in devices {
            if device.position == position { return device as! AVCaptureDevice }
        }
        return nil
    }

    // MARK: - Focus

    func previewTapped(gestureRecognizer:UIGestureRecognizer) {
        if (!self.tapToFocus) {
            return
        }

        let touchedPoint:CGPoint = gestureRecognizer.locationInView(self.preview)

        // focus
        let pointOfInterest = self.convertToPointOfInterestFromViewCoordinates(touchedPoint)
        self.focusAtPoint(pointOfInterest)

        // show the box
        self.showFocusBox(touchedPoint)
    }

    func addDefaultFocusBox() {
        let focusBox = CALayer()
        focusBox.cornerRadius = 5.0
        focusBox.bounds = CGRectMake(0.0, 0.0, 70, 60)
        focusBox.borderWidth = 3.0
        focusBox.borderColor = UIColor.yellowColor().CGColor
        focusBox.opacity = 0.0
        self.view.layer.addSublayer(focusBox)

        let focusBoxAnimation = CABasicAnimation(keyPath: "opacity")
        focusBoxAnimation.duration = 0.75
        focusBoxAnimation.autoreverses = false
        focusBoxAnimation.repeatCount = 0.0
        focusBoxAnimation.fromValue = 1
        focusBoxAnimation.toValue = 0

        self.alterFocusBox(focusBox, animation:focusBoxAnimation)
    }

    func alterFocusBox(layer:CALayer, animation:CAAnimation) {
        self.focusBoxLayer = layer
        self.focusBoxAnimation = animation
    }

    func focusAtPoint(point:CGPoint) {
        let device = self.videoCaptureDevice
        if (device.focusPointOfInterestSupported && device.isFocusModeSupported(AVCaptureFocusMode.AutoFocus)) {
            do {
                try device.lockForConfiguration()
                device.focusPointOfInterest = point
                device.focusMode = AVCaptureFocusMode.AutoFocus
                device.unlockForConfiguration()
            } catch let error as NSError { print("ERROR: \(error), \(error.userInfo)") }
        }
    }

    func showFocusBox(point:CGPoint) {
        // clear animations
        self.focusBoxLayer.removeAllAnimations()

        // move layer to the touch point
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey:kCATransactionDisableActions)
        self.focusBoxLayer.position = point
        CATransaction.commit()

        if ((self.focusBoxAnimation) != nil) {
            // run the animation
            self.focusBoxLayer.addAnimation(self.focusBoxAnimation, forKey:"animateOpacity")
        }
    }

    func convertToPointOfInterestFromViewCoordinates(viewCoordinates:CGPoint) -> CGPoint {
        let previewLayer = self.captureVideoPreviewLayer

        var pointOfInterest = CGPointMake(0.5, 0.5)
        let frameSize = previewLayer.frame.size

        if previewLayer.videoGravity == AVLayerVideoGravityResize {
            pointOfInterest = CGPointMake(viewCoordinates.y / frameSize.height, 1 - (viewCoordinates.x / frameSize.width))
        } else {
            var cleanAperture:CGRect

            for port in self.videoDeviceInput.ports {
                if port.mediaType == AVMediaTypeVideo {
                    cleanAperture = CMVideoFormatDescriptionGetCleanAperture(port.formatDescription, true)
                    let apertureSize = cleanAperture.size
                    let point = viewCoordinates

                    let apertureRatio:CGFloat = apertureSize.height / apertureSize.width
                    let viewRatio:CGFloat = frameSize.width / frameSize.height
                    var xc:CGFloat = 0.5
                    var yc:CGFloat = 0.5

                    if previewLayer.videoGravity == AVLayerVideoGravityResizeAspect {
                        if viewRatio > apertureRatio {
                            let y2:CGFloat = frameSize.height
                            let x2:CGFloat = frameSize.height * apertureRatio
                            let x1:CGFloat = frameSize.width
                            let blackBar:CGFloat = (x1-x2)/2
                            if ((point.x >= blackBar) && (point.x <= blackBar+x2)) {
                                xc = point.y / y2
                                yc = 1 - ((point.x-blackBar)/x2)
                            }
                        } else {
                            let y2:CGFloat = frameSize.width / apertureRatio
                            let y1:CGFloat = frameSize.height
                            let x2:CGFloat = frameSize.width
                            let blackBar:CGFloat = (y1-y2)/2
                            if ((point.y >= blackBar) && (point.y <= blackBar+y2)) {
                                xc = ((point.y-blackBar)/y2)
                                yc = 1 - (point.x / x2)
                            }
                        }
                    } else if previewLayer.videoGravity == AVLayerVideoGravityResizeAspectFill {
                        if viewRatio > apertureRatio {
                            let y2:CGFloat = apertureSize.width * (frameSize.width / apertureSize.height)
                            xc = (point.y + ((y2 - frameSize.height) / 2)) / y2
                            yc = (frameSize.width - point.x) / frameSize.width
                        } else {
                            let x2:CGFloat = apertureSize.height * (frameSize.height / apertureSize.width)
                            yc = 1 - ((point.x + ((x2 - frameSize.width) / 2)) / x2)
                            xc = point.y / frameSize.height
                        }
                    }
                    pointOfInterest = CGPointMake(xc, yc)
                }
            }
        }
        return pointOfInterest
    }

    // MARK: UIViewController

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        self.preview.frame = CGRectMake(0, 0, self.view.bounds.size.width, self.view.bounds.size.height)

        let bounds = self.preview.bounds

        self.captureVideoPreviewLayer.bounds = bounds
        self.captureVideoPreviewLayer.position = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds))

        self.captureVideoPreviewLayer.connection.videoOrientation = self.orientationForConnection
    }

    var orientationForConnection:AVCaptureVideoOrientation {
        var videoOrientation:AVCaptureVideoOrientation = AVCaptureVideoOrientation.Portrait

        if (self.useDeviceOrientation == true) {
            switch UIDevice.currentDevice().orientation {
            case UIDeviceOrientation.LandscapeLeft:
                // yes we to the right, this is not a bug!
                videoOrientation = AVCaptureVideoOrientation.LandscapeRight
            case UIDeviceOrientation.LandscapeRight:
                videoOrientation = AVCaptureVideoOrientation.LandscapeLeft
            case UIDeviceOrientation.PortraitUpsideDown:
                videoOrientation = AVCaptureVideoOrientation.PortraitUpsideDown
            default:
                videoOrientation = AVCaptureVideoOrientation.Portrait
            }
        } else {
            switch (self.interfaceOrientation) {
            case UIInterfaceOrientation.LandscapeLeft:
                videoOrientation = AVCaptureVideoOrientation.LandscapeLeft
            case UIInterfaceOrientation.LandscapeRight:
                videoOrientation = AVCaptureVideoOrientation.LandscapeRight
            case UIInterfaceOrientation.PortraitUpsideDown:
                videoOrientation = AVCaptureVideoOrientation.PortraitUpsideDown
            default:
                videoOrientation = AVCaptureVideoOrientation.Portrait
            }
        }
        return videoOrientation
    }


    func willRotateToInterfaceOrientation(toInterfaceOrientation:UIInterfaceOrientation, withDuration duration:NSTimeInterval) {
        super.willRotateToInterfaceOrientation(toInterfaceOrientation, duration:duration)

        // layout subviews is not called when rotating from landscape right/left to left/right
        if (UIInterfaceOrientationIsLandscape(self.interfaceOrientation) && UIInterfaceOrientationIsLandscape(toInterfaceOrientation)) {
            self.view.setNeedsLayout()
        }
    }

    /*func dealloc() {
    self.stop()
    }*/

    // MARK: Legacy Getters
    func isVideoEnabled() -> Bool { return self.videoEnabled }
    func isRecording() -> Bool { return self.recording }

    // MARK: Class Methods

    /**
    * Use this method to request camera permission before initalizing LLSimpleCamera.
    */
    class func requestCameraPermission(completionBlock:(Bool -> Void)) {
        if (AVCaptureDevice.respondsToSelector(Selector("requestAccessForMediaType:completionHandler"))) {
            AVCaptureDevice.requestAccessForMediaType(AVMediaTypeVideo, completionHandler: {
                granted in
                dispatch_async(dispatch_get_main_queue()) {
                    completionBlock(granted)
                }
            })
        }
    }

    /**
     * Use this method to request microphone permission before initalizing LLSimpleCamera.
     */
    class func requestMicrophonePermission(completionBlock:(Bool -> Void)) {
        if AVAudioSession.sharedInstance().respondsToSelector("requestRecordPermission:") {
            AVAudioSession.sharedInstance().requestRecordPermission {
                granted in
                dispatch_async(dispatch_get_main_queue()) {
                    completionBlock(granted)
                }
            }
        }
    }
    
    /**
     * Checks is the front camera is available.
     */
    class func isFrontCameraAvailable() -> Bool {
        return UIImagePickerController.isCameraDeviceAvailable(UIImagePickerControllerCameraDevice.Front)
    }
    
    /**
     * Checks is the rear camera is available.
     */
    class func isRearCameraAvailable() -> Bool {
        return UIImagePickerController.isCameraDeviceAvailable(UIImagePickerControllerCameraDevice.Rear)
    }
    
}
