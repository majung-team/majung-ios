import AVFoundation
import SwiftUI
import UIKit
import VisionKit

struct VehicleQRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var vehicleLinks: VehicleLinkViewModel

    @State private var linkDraft = ""
    @State private var validationError: String?
    @State private var cameraPermissionDenied = false

    let onConnected: () -> Void

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable && !cameraPermissionDenied
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
                VehicleQRDataScanner { scanned in
                    Task { await submitRawText(scanned) }
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("vehicle-qr-camera-preview")
                Text("차량 디스플레이의 연결 QR 코드를 사각형 안에 비춰주세요.")
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
            Text("차량 화면이나 공유 링크(`https://majung.cloud/#vehicle/...`, `majung://vehicle/...`)를 붙여넣으세요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("https://majung.cloud/#vehicle/...", text: $linkDraft)
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
        guard DataScannerViewController.isSupported else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermissionDenied = false
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraPermissionDenied = !granted
        default:
            cameraPermissionDenied = true
        }
    }

    private func submitRawText(_ raw: String) async {
        validationError = nil
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

private struct VehicleQRDataScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var lastHandledPayload: String?

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            handleItems(addedItems, scanner: dataScanner)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didTapOn item: RecognizedItem
        ) {
            handleItems([item], scanner: dataScanner)
        }

        private func handleItems(_ items: [RecognizedItem], scanner: DataScannerViewController) {
            for item in items {
                guard case .barcode(let barcode) = item,
                      let payload = barcode.payloadStringValue,
                      payload != lastHandledPayload,
                      VehiclePairingTarget(rawText: payload) != nil else {
                    continue
                }
                lastHandledPayload = payload
                scanner.stopScanning()
                onScan(payload)
                return
            }
        }
    }
}
