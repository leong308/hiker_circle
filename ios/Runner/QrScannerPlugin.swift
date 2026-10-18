// QrScannerPlugin registers the iOS camera preview and streams QR scan results to Flutter.
import Flutter
import UIKit
import AVFoundation

class QrScannerPlatformView: NSObject, FlutterPlatformView {
  private let previewView: QrScannerPreviewView
  private let captureSession: AVCaptureSession
  private let metadataOutput: AVCaptureMetadataOutput
  private let eventSink: FlutterEventSink?

  init(
    frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?,
    eventSink: FlutterEventSink?
  ) {
    previewView = QrScannerPreviewView()
    previewView.backgroundColor = UIColor.black
    captureSession = AVCaptureSession()
    metadataOutput = AVCaptureMetadataOutput()
    self.eventSink = eventSink
    super.init()
    setupCamera()
  }

  func view() -> UIView {
    previewView
  }

  private func setupCamera() {
    AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
      guard let self, granted else { return }
      self.configureCaptureSession()
    }
  }

  private func configureCaptureSession() {
    guard let videoCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
          let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice)
    else { return }

    guard captureSession.canAddInput(videoInput) else { return }
    captureSession.addInput(videoInput)

    guard captureSession.canAddOutput(metadataOutput) else { return }
    captureSession.addOutput(metadataOutput)
    metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
    metadataOutput.metadataObjectTypes = [.qr]

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
      previewLayer.frame = previewView.bounds
      previewLayer.videoGravity = .resizeAspectFill
      previewView.layer.addSublayer(previewLayer)
      previewView.previewLayer = previewLayer
    }

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      self?.captureSession.startRunning()
    }
  }

  func stopScanning() {
    captureSession.stopRunning()
  }
}

extension QrScannerPlatformView: AVCaptureMetadataOutputObjectsDelegate {
  func metadataOutput(
    _ output: AVCaptureMetadataOutput,
    didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    guard let metadataObject = metadataObjects.first,
          let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
          let stringValue = readableObject.stringValue else {
      return
    }
    eventSink?(stringValue)
  }
}

class QrScannerPreviewView: UIView {
  weak var previewLayer: AVCaptureVideoPreviewLayer?

  override func layoutSubviews() {
    super.layoutSubviews()
    previewLayer?.frame = bounds
  }
}

class QrScannerPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private let eventChannel: FlutterEventChannel
  private var eventSink: FlutterEventSink?

  init(messenger: FlutterBinaryMessenger) {
    eventChannel = FlutterEventChannel(
      name: "hiker_circle/qr_scanner_events",
      binaryMessenger: messenger
    )
    super.init()
    eventChannel.setStreamHandler(self)
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    QrScannerPlatformView(
      frame: frame,
      viewIdentifier: viewId,
      arguments: args,
      eventSink: eventSink
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

extension QrScannerPlatformViewFactory: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}
