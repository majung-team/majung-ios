import AVFoundation
import SwiftUI
import UIKit

struct VehicleQRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var vehicleLinks: VehicleLinkViewModel

    @State private var linkDraft = ""
    @State private var validationError: String?
    @State private var cameraPermissionDenied = false
    @State private var cameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized

    let onConnected: () -> Void

    private var hasVideoDevice: Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    private var scannerAvailable: Bool {
        hasVideoDevice && cameraAuthorized && !cameraPermissionDenied
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    cameraSection
                    manualEntryCard
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("차량 QR 연결")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .task {
                await checkCameraAuthorization()
            }
        }
    }

    @ViewBuilder
    private var cameraSection: some View {
        MajungCard {
            Text("차량 화면 QR 스캔")
                .font(.headline)
            if scannerAvailable {
                VehicleCameraQRScanner(
                    onValidScan: { scanned in
                        Task { await submitRawText(scanned) }
                    },
                    onUnsupportedPayload: {
                        validationError = "차량 연결용 QR 코드가 아니에요. 차량 앱의 연결 QR을 비춰주세요."
                    }
                )
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("vehicle-qr-camera-preview")
                Text("차량 디스플레이의 연결 QR 코드를 카메라에 비추면 자동으로 연결해요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Label(
                    cameraPermissionDenied
                        ? "카메라 권한이 꺼져 있어요. 설정에서 카메라를 허용하거나 아래 링크 입력을 이용해주세요."
                        : "이 기기나 시뮬레이터에서는 카메라 QR 스캔 대신 링크를 직접 입력할 수 있어요.",
                    systemImage: cameraPermissionDenied ? "camera.fill.badge.ellipsis" : "qrcode"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var manualEntryCard: some View {
        MajungCard {
            Text("연결 링크 직접 입력")
                .font(.headline)
            Text("차량 화면이나 공유 링크(`https://majung.cloud/account#enroll/...`, `#vehicle/...`)를 붙여넣으세요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("https://majung.cloud/account#enroll/...", text: $linkDraft)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .accessibilityIdentifier("vehicle-qr-link-field")

            HStack(spacing: 10) {
                Button("붙여넣기") {
                    if let pasted = UIPasteboard.general.string {
                        linkDraft = pasted
                        validationError = nil
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("vehicle-qr-paste-button")

                Button(vehicleLinks.busy ? "요청 중…" : "차량 연결 요청") {
                    Task { await submitRawText(linkDraft) }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(linkDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vehicleLinks.busy)
                .accessibilityIdentifier("vehicle-qr-submit-button")
            }

            #if DEBUG
            if ProcessInfo.processInfo.environment["MAJUNG_TEST_PORT"] == nil,
               DevServerConfig.shared.mode != .production {
                Button("테스트용 차량 QR 링크 채우기") {
                    Task {
                        validationError = nil
                        if DevServerConfig.shared.mode == .demo {
                            linkDraft = SoloDemoServer.shared.sampleVehicleQRString
                        } else if let (data, _) = try? await URLSession.shared.data(
                            from: APIBaseURL.root.appendingPathComponent("dev").appendingPathComponent("state")
                        ),
                                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                  let qr = json["vehicleQr"] as? [String: Any],
                                  let link = qr["link"] as? String {
                            linkDraft = link
                        }
                    }
                }
                .font(.footnote.weight(.semibold))
            }
            #endif

            if let validationError {
                Text(validationError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if let serverError = vehicleLinks.error {
                Text(serverError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func checkCameraAuthorization() async {
        guard hasVideoDevice else {
            cameraAuthorized = false
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermissionDenied = false
            cameraAuthorized = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraPermissionDenied = !granted
            cameraAuthorized = granted
        default:
            cameraPermissionDenied = true
            cameraAuthorized = false
        }
    }

    private func submitRawText(_ raw: String) async {
        validationError = nil
        linkDraft = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let target = VehiclePairingTarget(rawText: raw) else {
            validationError = "유효한 차량 연결 QR 또는 링크가 아니에요."
            return
        }
        let succeeded = await vehicleLinks.handleTarget(target)
        if succeeded {
            onConnected()
            dismiss()
        }
    }
}

private struct VehicleCameraQRScanner: UIViewControllerRepresentable {
    let onValidScan: (String) -> Void
    let onUnsupportedPayload: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onValidScan: onValidScan, onUnsupportedPayload: onUnsupportedPayload)
    }

    func makeUIViewController(context: Context) -> CameraScannerController {
        let controller = CameraScannerController()
        controller.coordinator = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraScannerController, context: Context) {
        uiViewController.coordinator = context.coordinator
    }

    final class CameraScannerController: UIViewController {
        var coordinator: Coordinator?

        private let sessionQueue = DispatchQueue(label: "app.majung.ios.qrscanner.session")
        private let captureSession = AVCaptureSession()
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var configured = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black

            let preview = AVCaptureVideoPreviewLayer(session: captureSession)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            view.layer.addSublayer(preview)
            previewLayer = preview
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            startSessionIfNeeded()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            sessionQueue.async { [captureSession] in
                if captureSession.isRunning {
                    captureSession.stopRunning()
                }
            }
        }

        private func startSessionIfNeeded() {
            guard let coordinator else { return }
            sessionQueue.async { [weak self, captureSession] in
                guard let self else { return }
                if !self.configured {
                    self.configured = true
                    captureSession.beginConfiguration()
                    if let videoDevice = AVCaptureDevice.default(for: .video),
                       let input = try? AVCaptureDeviceInput(device: videoDevice),
                       captureSession.canAddInput(input) {
                        captureSession.addInput(input)
                    }
                    let metadataOutput = AVCaptureMetadataOutput()
                    if captureSession.canAddOutput(metadataOutput) {
                        captureSession.addOutput(metadataOutput)
                        metadataOutput.setMetadataObjectsDelegate(coordinator, queue: .main)
                        if metadataOutput.availableMetadataObjectTypes.contains(.qr) {
                            metadataOutput.metadataObjectTypes = [.qr]
                        }
                    }
                    captureSession.commitConfiguration()
                }
                if !captureSession.isRunning {
                    captureSession.startRunning()
                }
            }
        }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let onValidScan: (String) -> Void
        private let onUnsupportedPayload: () -> Void
        private var lastHandledValidPayload: String?
        private var lastUnsupportedAt: Date = .distantPast

        init(onValidScan: @escaping (String) -> Void, onUnsupportedPayload: @escaping () -> Void) {
            self.onValidScan = onValidScan
            self.onUnsupportedPayload = onUnsupportedPayload
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            for object in metadataObjects {
                guard let readable = object as? AVMetadataMachineReadableCodeObject,
                      readable.type == .qr,
                      let raw = readable.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !raw.isEmpty else {
                    continue
                }
                if VehiclePairingTarget(rawText: raw) != nil {
                    guard raw != lastHandledValidPayload else { return }
                    lastHandledValidPayload = raw
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onValidScan(raw)
                    return
                } else if Date().timeIntervalSince(lastUnsupportedAt) > 2.5 {
                    lastUnsupportedAt = Date()
                    onUnsupportedPayload()
                }
            }
        }
    }
}
