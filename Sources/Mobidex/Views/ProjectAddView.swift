import SwiftUI

struct ProjectAddView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppViewModel
    @State private var path = ""
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Remote Path") {
                    TextField("/home/user/project", text: $path)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(add)
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("projectValidationMessage")
                    }
                }
            }
            .navigationTitle("Add Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        add()
                    }
                }
            }
            .onChange(of: path) { _, _ in
                validationMessage = nil
            }
        }
    }

    private func add() {
        if model.addProject(path: path) {
            dismiss()
        } else {
            validationMessage = model.statusMessage ?? "Mobidex could not save this project."
        }
    }
}
