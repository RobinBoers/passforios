//
//  QRScannerController.swift
//  pass
//
//  Created by Yishi Lin on 7/4/17.
//  Copyright © 2017 Yishi Lin. All rights reserved.
//

import AVFoundation
import OneTimePassword
import passKit
import UIKit
import VisionKit

protocol QRScannerControllerDelegate: AnyObject {
    func checkScannedOutput(line: String) -> (accepted: Bool, message: String)
    func handleScannedOutput(line: String)
}

/// Scans QR codes with VisionKit where the device supports it, and with a capture session of its own elsewhere.
class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    @IBOutlet var scannerOutput: UILabel!

    var captureSession: AVCaptureSession?
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    var qrCodeFrameView: UIView?
    private var dataScanner: DataScannerViewController?
    private var hasStarted = false
    private var isDone = false

    let supportedCodeTypes = [AVMetadataObject.ObjectType.qr]

    weak var delegate: QRScannerControllerDelegate?

    var idleMessage = "NoQrCodeDetected.".localize()

    private var statusView = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addScannerOutput()
        scannerOutput.text = idleMessage
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasStarted else {
            return
        }
        hasStarted = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startScanning()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.startScanning()
                    } else {
                        self.presentCameraSettings()
                    }
                }
            }
        default:
            presentCameraSettings()
        }
    }

    private func startScanning() {
        if DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
            startDataScanner()
        } else {
            startCaptureSession()
        }
    }

    private func startDataScanner() {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = self
        addChild(scanner)
        scanner.view.frame = view.bounds
        scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(scanner.view, at: 0)
        scanner.didMove(toParent: self)
        dataScanner = scanner
        do {
            try scanner.startScanning()
        } catch {
            scannerOutput.text = error.localizedDescription
        }
    }

    private func startCaptureSession() {
        guard let captureDevice = AVCaptureDevice.default(for: .video) else {
            scannerOutput.text = "CameraAccessDenied.".localize()
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: captureDevice)
            let session = AVCaptureSession()
            session.addInput(input)

            let captureMetadataOutput = AVCaptureMetadataOutput()
            session.addOutput(captureMetadataOutput)
            captureMetadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            captureMetadataOutput.metadataObjectTypes = supportedCodeTypes

            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = view.layer.bounds
            view.layer.insertSublayer(previewLayer, at: 0)
            videoPreviewLayer = previewLayer
            captureSession = session

            let frameView = UIView()
            frameView.layer.borderColor = UIColor.systemYellow.cgColor
            frameView.layer.borderWidth = 3
            frameView.layer.cornerRadius = 8
            frameView.layer.cornerCurve = .continuous
            view.insertSubview(frameView, belowSubview: statusView)
            qrCodeFrameView = frameView

            // Starting blocks until the camera runs.
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        } catch {
            scannerOutput.text = error.localizedDescription
        }
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate Methods

    func metadataOutput(_: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from _: AVCaptureConnection) {
        guard let metadataObj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              supportedCodeTypes.contains(metadataObj.type),
              let barCodeObject = videoPreviewLayer?.transformedMetadataObject(for: metadataObj) else {
            setNotDetected()
            return
        }
        qrCodeFrameView?.frame = barCodeObject.bounds
        guard let scanned = metadataObj.stringValue else {
            scannerOutput.text = "NoStringValue".localize()
            return
        }
        handle(scanned: scanned)
    }

    private func handle(scanned: String) {
        guard !isDone else {
            return
        }
        guard let (accepted, message) = delegate?.checkScannedOutput(line: scanned) else {
            scannerOutput.text = scanned
            return
        }
        scannerOutput.text = message
        UIAccessibility.post(notification: .announcement, argument: message)
        guard accepted else {
            return
        }
        isDone = true
        captureSession?.stopRunning()
        dataScanner?.stopScanning()
        delegate?.handleScannedOutput(line: scanned)
        DispatchQueue.main.async {
            Feedback.success()
            self.close()
        }
    }

    private func close() {
        guard let navigationController, navigationController.viewControllers.first !== self else {
            dismiss(animated: true, completion: didClose)
            return
        }
        navigationController.popViewController(animated: true)
        didClose()
    }

    func didClose() {}

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        videoPreviewLayer?.frame = view.layer.bounds
        if #unavailable(iOS 26.0) {
            statusView.layer.cornerRadius = statusView.bounds.height / 2
        }
    }

    /// The status, in a capsule over the camera, replacing the plain label some storyboards still have.
    private func addScannerOutput() {
        scannerOutput?.removeFromSuperview()

        let label = UILabel()
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false

        let capsule = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        if #available(iOS 26.0, *) {
            capsule.effect = UIGlassEffect()
            capsule.cornerConfiguration = .capsule()
        }
        capsule.clipsToBounds = true
        capsule.translatesAutoresizingMaskIntoConstraints = false
        capsule.contentView.addSubview(label)
        view.addSubview(capsule)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: capsule.contentView.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: capsule.contentView.trailingAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: capsule.contentView.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: capsule.contentView.bottomAnchor, constant: -12),
            capsule.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            capsule.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
            capsule.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])
        scannerOutput = label
        statusView = capsule
    }

    private func setNotDetected() {
        qrCodeFrameView?.frame = CGRect.zero
        scannerOutput.text = idleMessage
    }

    private func presentCameraSettings() {
        let alertController = UIAlertController(
            title: "NoCameraAccess".localize(),
            message: "CameraAccessDenied.".localize() | "WarningToggleCameraPermissionsResetsApp.".localize(),
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "Cancel".localize(), style: .cancel))
        alertController.addAction(
            UIAlertAction(title: "Settings".localize(), style: .default) { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        )
        present(alertController, animated: true)
    }
}

extension QRScannerController: DataScannerViewControllerDelegate {
    func dataScanner(_: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems _: [RecognizedItem]) {
        recognize(addedItems)
    }

    /// A code that changes in place, like the frames of an animated one, updates the item it was.
    func dataScanner(_: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems _: [RecognizedItem]) {
        recognize(updatedItems)
    }

    func dataScanner(_: DataScannerViewController, didRemove _: [RecognizedItem], allItems: [RecognizedItem]) {
        if allItems.isEmpty {
            setNotDetected()
        }
    }

    private func recognize(_ items: [RecognizedItem]) {
        for case let .barcode(barcode) in items {
            if let payload = barcode.payloadStringValue {
                handle(scanned: payload)
            }
        }
    }
}
