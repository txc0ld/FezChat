import SwiftUI
import UIKit

// MARK: - SystemImagePicker

/// UIKit-backed image picker for camera capture flows that PhotosPicker does not cover.
struct SystemImagePicker: UIViewControllerRepresentable {

    @Binding var isPresented: Bool
    let sourceType: UIImagePickerController.SourceType
    var allowsEditing = false
    let onImagePicked: (UIImage) -> Void

    static func isAvailable(_ sourceType: UIImagePickerController.SourceType) -> Bool {
        UIImagePickerController.isSourceTypeAvailable(sourceType)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.allowsEditing = allowsEditing
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: SystemImagePicker

        init(parent: SystemImagePicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let selectedImage = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            parent.isPresented = false

            guard let selectedImage else { return }
            DispatchQueue.main.async {
                self.parent.onImagePicked(selectedImage)
            }
        }
    }
}
