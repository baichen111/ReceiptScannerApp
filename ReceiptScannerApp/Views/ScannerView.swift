import SwiftUI
import SwiftData

struct ScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ScannerViewModel()
    @State private var showCamera = false
    @State private var showPhotoPicker = false

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .camera:
                    cameraPrompt
                case .processing:
                    processingView
                case .review:
                    reviewView
                case .error(let message):
                    errorView(message)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker(isPresented: $showCamera, sourceType: .camera) { image in
                    Task {
                        await viewModel.processImage(image)
                    }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showPhotoPicker) {
                CameraPicker(isPresented: $showPhotoPicker, sourceType: .photoLibrary) { image in
                    Task {
                        await viewModel.processImage(image)
                    }
                }
            }
        }
    }

    private var navigationTitle: String {
        switch viewModel.state {
        case .camera: return "Scan Receipt"
        case .processing: return "Processing..."
        case .review: return "Review Receipt"
        case .error: return "Error"
        }
    }

    // MARK: - Camera Prompt

    private var cameraPrompt: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            Text("Scan a Receipt")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Take a photo of your receipt or choose from your photo library")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(spacing: 12) {
                Button {
                    showCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    showPhotoPicker = true
                } label: {
                    Label("Photo Library", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.gray.opacity(0.15))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Processing

    private var processingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Recognizing text...")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Review

    private var reviewView: some View {
        Form {
            // Receipt image preview
            if let image = viewModel.capturedImage {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(maxWidth: .infinity)
                }
            }

            // Store & date
            Section("Store Info") {
                TextField("Store Name", text: $viewModel.editStoreName)
                DatePicker("Date", selection: $viewModel.editDate, displayedComponents: .date)
            }

            // Items
            Section {
                ForEach(viewModel.editItems.indices, id: \.self) { index in
                    HStack {
                        TextField("Item", text: Binding(
                            get: { viewModel.editItems[index].name },
                            set: { viewModel.editItems[index].name = $0 }
                        ))

                        TextField("Price", text: Binding(
                            get: { viewModel.editItems[index].price },
                            set: { viewModel.editItems[index].price = $0 }
                        ))
                        .keyboardType(.decimalPad)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)

                        Button {
                            viewModel.removeItem(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    viewModel.addItem()
                } label: {
                    Label("Add Item", systemImage: "plus.circle.fill")
                }
            } header: {
                HStack {
                    Text("Items")
                    Spacer()
                    Text("\(viewModel.editItems.count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Totals
            Section("Totals") {
                HStack {
                    Text("Tax")
                    Spacer()
                    TextField("0.00", text: $viewModel.editTax)
                        .keyboardType(.decimalPad)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("Total")
                        .fontWeight(.semibold)
                    Spacer()
                    TextField("0.00", text: $viewModel.editTotal)
                        .keyboardType(.decimalPad)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .fontWeight(.semibold)
                }
            }

            // Raw OCR text (collapsible)
            Section {
                DisclosureGroup("Raw OCR Text") {
                    Text(viewModel.ocrLines.joined(separator: "\n"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Save button
            Section {
                Button {
                    viewModel.save(in: modelContext)
                    dismiss()
                } label: {
                    Text("Save Receipt")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Something went wrong")
                .font(.title3)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Try Again") {
                viewModel.reset()
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
    }
}

#Preview {
    ScannerView()
        .modelContainer(for: [Receipt.self, ReceiptItem.self], inMemory: true)
}
