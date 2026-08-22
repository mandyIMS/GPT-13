import MobileCoreServices
import GeckoView
import UIKit

@MainActor
final class GPTFilePicker: NSObject {
    private weak var presenter: UIViewController?
    private var continuation: CheckedContinuation<[String: Any]?, Never>?
    private var allowsMultipleSelection = false

    func present(
        request: FilePickerPromptRequest,
        from presenter: UIViewController
    ) async -> [String: Any]? {
        self.presenter = presenter
        allowsMultipleSelection = request.mode == "multiple"

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            presentSourceMenu()
        }
    }

    func cancel() {
        presenter?.presentedViewController?.dismiss(animated: false)
        finish(nil)
    }

    private func presentSourceMenu() {
        guard let presenter else {
            finish(nil)
            return
        }

        let alert = UIAlertController(title: "添加附件", message: nil, preferredStyle: .actionSheet)
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            alert.addAction(UIAlertAction(title: "照片图库", style: .default) { [weak self] _ in
                self?.presentMediaPicker(sourceType: .photoLibrary)
            })
        }
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            alert.addAction(UIAlertAction(title: "拍照", style: .default) { [weak self] _ in
                self?.presentMediaPicker(sourceType: .camera)
            })
        }
        alert.addAction(UIAlertAction(title: "选取文件", style: .default) { [weak self] _ in
            self?.presentDocumentPicker()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
            self?.finish(nil)
        })

        if let popover = alert.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.maxY,
                width: 1,
                height: 1
            )
        }
        presenter.present(alert, animated: true)
    }

    private func presentDocumentPicker() {
        guard let presenter else {
            finish(nil)
            return
        }
        let picker = UIDocumentPickerViewController(
            documentTypes: [kUTTypeItem as String],
            in: .open
        )
        picker.delegate = self
        picker.allowsMultipleSelection = allowsMultipleSelection
        presenter.present(picker, animated: true)
    }

    private func presentMediaPicker(sourceType: UIImagePickerController.SourceType) {
        guard let presenter else {
            finish(nil)
            return
        }
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = sourceType
        presenter.present(picker, animated: true)
    }

    private func stage(urls: [URL]) -> [String: Any]? {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReynardGPTUploads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var paths: [String] = []
            for source in urls {
                let accessed = source.startAccessingSecurityScopedResource()
                defer { if accessed { source.stopAccessingSecurityScopedResource() } }
                let name = source.lastPathComponent.isEmpty ? UUID().uuidString : source.lastPathComponent
                let destination = root.appendingPathComponent(name)
                try FileManager.default.copyItem(at: source, to: destination)
                paths.append(destination.path)
            }
            return paths.isEmpty ? nil : ["files": paths]
        } catch {
            return nil
        }
    }

    private func stage(image: UIImage) -> [String: Any]? {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReynardGPTUploads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = root.appendingPathComponent("photo.jpg")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            return ["files": [destination.path]]
        } catch {
            return nil
        }
    }

    private func finish(_ result: [String: Any]?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: result)
    }
}

extension GPTFilePicker: UIDocumentPickerDelegate {
    nonisolated func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        Task { @MainActor [weak self] in
            self?.finish(self?.stage(urls: urls))
        }
    }

    nonisolated func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        Task { @MainActor [weak self] in self?.finish(nil) }
    }
}

extension GPTFilePicker: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        Task { @MainActor [weak self] in
            picker.dismiss(animated: true)
            self?.finish(nil)
        }
    }

    nonisolated func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        let mediaURL = info[.mediaURL] as? URL
        let imageURL = info[.imageURL] as? URL
        let image = info[.originalImage] as? UIImage
        Task { @MainActor [weak self] in
            picker.dismiss(animated: true)
            if let mediaURL {
                self?.finish(self?.stage(urls: [mediaURL]))
            } else if let imageURL {
                self?.finish(self?.stage(urls: [imageURL]))
            } else if let image {
                self?.finish(self?.stage(image: image))
            } else {
                self?.finish(nil)
            }
        }
    }
}
