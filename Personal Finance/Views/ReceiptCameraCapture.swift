#if os(iOS)
import SwiftUI
import VisionKit

struct ReceiptCameraCapture: UIViewControllerRepresentable {
    let maximumPages: Int
    let onComplete: (Result<[AttachmentDraft], Error>) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) { }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: ReceiptCameraCapture
        init(parent: ReceiptCameraCapture) { self.parent = parent }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.onCancel() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onComplete(.failure(error))
        }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            do {
                guard scan.pageCount <= parent.maximumPages else { throw AttachmentFailure.count }
                let attachments = try (0..<scan.pageCount).map { index in
                    guard let data = scan.imageOfPage(at: index).jpegData(compressionQuality: 0.85) else { throw AttachmentFailure.format }
                    return try AttachmentDraft(filename: "Scontrino \(index + 1).jpg", data: data)
                }
                parent.onComplete(.success(attachments))
            } catch { parent.onComplete(.failure(error)) }
        }
    }
}
#endif
