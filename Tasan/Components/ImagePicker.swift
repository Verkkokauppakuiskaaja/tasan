import SwiftUI
import UIKit

struct ImagePicker: UIViewControllerRepresentable {
  let sourceType: UIImagePickerController.SourceType
  let onImagePicked: (UIImage) -> Void
  let onCancel: () -> Void

  init(
    sourceType: UIImagePickerController.SourceType,
    onImagePicked: @escaping (UIImage) -> Void,
    onCancel: @escaping () -> Void = {}
  ) {
    self.sourceType = sourceType
    self.onImagePicked = onImagePicked
    self.onCancel = onCancel
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(
      onImagePicked: onImagePicked,
      onCancel: onCancel
    )
  }

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = sourceType
    picker.delegate = context.coordinator
    picker.allowsEditing = false
    picker.modalPresentationStyle = .fullScreen
    return picker
  }

  func updateUIViewController(
    _ uiViewController: UIImagePickerController,
    context: Context
  ) {}

  final class Coordinator: NSObject,
    UINavigationControllerDelegate,
    UIImagePickerControllerDelegate
  {
    private let onImagePicked: (UIImage) -> Void
    private let onCancel: () -> Void

    init(
      onImagePicked: @escaping (UIImage) -> Void,
      onCancel: @escaping () -> Void
    ) {
      self.onImagePicked = onImagePicked
      self.onCancel = onCancel
    }

    func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      defer {
        picker.dismiss(animated: true)
      }

      guard let image = info[.originalImage] as? UIImage else {
        onCancel()
        return
      }

      onImagePicked(image)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      onCancel()
      picker.dismiss(animated: true)
    }
  }
}
