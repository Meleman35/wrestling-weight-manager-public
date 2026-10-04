import UIKit

/// Camera-only snapshot presenter. Capture token closes the delayed callback race.
/// Host must call cancel() on background, navigation, lock and account/club change.
@MainActor
final class WrestlingManagerRemotePhoto: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    enum Failure: Error { case unavailable, busy, invalidImage, cancelled }
    private var picker: UIImagePickerController?
    private var completion: ((UUID, Result<(Data, Date), Error>) -> Void)?
    private var token: UUID?

    func take(token: UUID, from presenter: UIViewController,
              completion: @escaping (UUID, Result<(Data, Date), Error>) -> Void) {
        guard picker == nil else { completion(token, .failure(Failure.busy)); return }
        guard UIImagePickerController.isSourceTypeAvailable(.camera), presenter.viewIfLoaded?.window != nil,
              presenter.presentedViewController == nil else { completion(token, .failure(Failure.unavailable)); return }
        let camera = UIImagePickerController()
        camera.sourceType = .camera; camera.cameraCaptureMode = .photo
        camera.mediaTypes = ["public.image"]; camera.allowsEditing = false
        if UIImagePickerController.isCameraDeviceAvailable(.front) { camera.cameraDevice = .front }
        camera.delegate = self; camera.modalPresentationStyle = .fullScreen
        self.token = token; self.completion = completion; picker = camera
        presenter.present(camera, animated: true)
    }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        guard self.picker === picker else { return }
        let at = Date()
        guard let image = info[.originalImage] as? UIImage,
              image.size.width.isFinite, image.size.height.isFinite, image.size.width > 0, image.size.height > 0 else {
            finish(.failure(Failure.invalidImage)); return
        }
        // Rendering removes original metadata and normalizes orientation; cap both dimensions.
        let factor = min(1, 1280 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor.black.setFill(); UIRectFill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = normalized.jpegData(compressionQuality: 0.8), !jpeg.isEmpty, jpeg.count <= 5 * 1024 * 1024 else {
            finish(.failure(Failure.invalidImage)); return
        }
        finish(.success((jpeg, at)))
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        guard self.picker === picker else { return }; finish(.failure(Failure.cancelled))
    }
    func cancel() { finish(.failure(Failure.cancelled)) }
    private func finish(_ result: Result<(Data, Date), Error>) {
        guard let picker, let token else { return }
        let callback = completion
        self.picker = nil; self.token = nil; completion = nil
        picker.dismiss(animated: false)
        callback?(token, result)
    }
}
