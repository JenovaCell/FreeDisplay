import SwiftUI
import CoreGraphics

/// "虚拟显示器" management section shown in the MenuBarView tools area.
/// Lists all saved virtual display configurations and allows creating / deleting them.
struct VirtualDisplayView: View {
    @StateObject private var service = VirtualDisplayService.shared
    @State private var showCreateForm = false
    @State private var configToDelete: UUID?
    @State private var isCreating: Bool = false
    @State private var createError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if service.configs.isEmpty {
                Text("No virtual displays")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(service.configs) { config in
                    configRow(config: config)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                }
            }

            // "+" create button
            Button(action: { showCreateForm.toggle() }) {
                HStack {
                    Image(systemName: showCreateForm ? "minus.circle.fill" : "plus.circle.fill")
                        .foregroundColor(.accentColor)
                    Text(showCreateForm ? "Cancel" : "Create Virtual Display")
                        .font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .help("Create a new virtual display")

            if let err = createError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            if showCreateForm {
                CreateVirtualDisplayForm(isCreating: $isCreating, onConfirm: { config in
                    isCreating = true
                    createError = nil
                    Task { @MainActor in
                        let success = await service.addAndCreate(config)
                        isCreating = false
                        if success {
                            showCreateForm = false
                        } else {
                            createError = "Failed to create virtual display. Please try again."
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 3_000_000_000)
                                createError = nil
                            }
                        }
                    }
                })
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Config Row

    /// Shows the normal row, or an inline confirmation when this config is pending deletion.
    /// (A system `.alert` can't be used here: the menu bar window dismisses itself when the
    /// alert takes focus, so the confirmation never completes.)
    @ViewBuilder
    private func configRow(config: VirtualDisplayService.VirtualDisplayConfig) -> some View {
        if configToDelete == config.id {
            deleteConfirmationRow(config: config)
        } else {
            normalRow(config: config)
        }
    }

    @ViewBuilder
    private func deleteConfirmationRow(config: VirtualDisplayService.VirtualDisplayConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(service.isActive(config.id)
                 ? "\"\(config.name)\" is active and will be removed immediately."
                 : "Delete \"\(config.name)\"?")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel") { configToDelete = nil }
                    .controlSize(.small)
                Spacer()
                Button("Delete") {
                    service.removeConfig(id: config.id)
                    configToDelete = nil
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.red.opacity(0.10))
        )
    }

    @ViewBuilder
    private func normalRow(config: VirtualDisplayService.VirtualDisplayConfig) -> some View {
        let active = service.isActive(config.id)

        HStack(spacing: 8) {
            Image(systemName: "display.2")
                .foregroundColor(active ? .blue : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(config.name)
                    .font(.body)
                    .lineLimit(1)
                Text("\(config.width)×\(config.height)\(config.hiDPI ? " · HiDPI" : "") · \(Int(config.refreshRate))Hz\(config.extraModes.map { " · +\($0.count) more" } ?? "")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Active / inactive badge
            if active {
                Text("Active")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .cornerRadius(4)
            }

            // Delete button
            Button(action: {
                configToDelete = config.id
            }) {
                Label("Delete", systemImage: "trash")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("Delete this virtual display")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.secondary.opacity(0.08))
        )
        .contextMenu {
            Button(role: .destructive) {
                configToDelete = config.id
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Create Form

/// Inline form for creating a new virtual display configuration.
struct CreateVirtualDisplayForm: View {
    @Binding var isCreating: Bool
    let onConfirm: (VirtualDisplayService.VirtualDisplayConfig) -> Void

    @State private var name: String = "Virtual Display"
    @State private var selectedPreset: Int = 0
    @State private var hiDPI: Bool = true
    @State private var autoCreate: Bool = true
    @State private var customWidth: String = "1728"
    @State private var customHeight: String = "1117"
    @State private var customRefresh: String = "60"
    @State private var extraModesText: String = ""
    @State private var validationError: String?

    private let presets: [(label: String, width: Int, height: Int)] = [
        ("1920×1080 (FHD)", 1920, 1080),
        ("2560×1440 (QHD)", 2560, 1440),
        ("3840×2160 (4K)",  3840, 2160),
    ]

    /// Picker tag for the "Custom…" entry (one past the built-in presets).
    private var customTag: Int { presets.count }
    private var isCustom: Bool { selectedPreset == customTag }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Name field
            HStack {
                Text("Name")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .leading)
                TextField("Display Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            // Resolution preset picker
            HStack {
                Text("Resolution")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .leading)
                Picker("", selection: $selectedPreset) {
                    ForEach(presets.indices, id: \.self) { i in
                        Text(presets[i].label).tag(i)
                    }
                    Text("Custom…").tag(customTag)
                }
                .pickerStyle(.menu)
                .font(.caption)
                .labelsHidden()
                .help("Choose virtual display resolution")
            }

            // Custom width × height @ refresh rate
            if isCustom {
                HStack(spacing: 4) {
                    TextField("Width", text: $customWidth)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    Text("×").font(.caption).foregroundColor(.secondary)
                    TextField("Height", text: $customHeight)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    Text("@").font(.caption).foregroundColor(.secondary)
                    TextField("Hz", text: $customRefresh)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(width: 44)
                }
                .help("Width × height in pixels @ refresh rate (Hz)")
            }

            // Additional resolutions offered on the same display
            VStack(alignment: .leading, spacing: 2) {
                Text("Extra resolutions (optional)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                TextField("e.g. 1440x900, 2048x1152", text: $extraModesText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .help("Comma-separated WIDTHxHEIGHT list. These appear in the display's mode list so you can switch between them.")
            }

            if let validationError {
                Text(validationError)
                    .font(.caption2)
                    .foregroundColor(.red)
            }

            // HiDPI toggle
            HStack {
                Text("HiDPI")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .leading)
                Toggle("", isOn: $hiDPI)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
                    .help("Enable high-resolution mode (Retina)")
                Text("Enable HiDPI scaling")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Auto-create toggle
            HStack {
                Text("Auto")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .leading)
                Toggle("", isOn: $autoCreate)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
                Text("Create automatically at launch")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Confirm button
            Button(action: confirm) {
                HStack(spacing: 6) {
                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                    }
                    Text(isCreating ? "Creating..." : "Create")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isCreating)
        }
        .padding(.vertical, 4)
    }

    /// Parses "1440x900, 2048×1152" into resolutions. Returns nil if any entry is invalid.
    private func parseExtraModes(_ text: String) -> [VirtualDisplayService.Resolution]? {
        var result: [VirtualDisplayService.Resolution] = []
        let entries = text.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
        for entry in entries {
            let parts = entry
                .lowercased()
                .replacingOccurrences(of: "×", with: "x")
                .split(separator: "x")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]),
                  VirtualDisplayService.validSizeRange.contains(w),
                  VirtualDisplayService.validSizeRange.contains(h)
            else { return nil }
            result.append(.init(width: w, height: h))
        }
        return result
    }

    private func confirm() {
        guard !isCreating else { return }

        let width: Int
        let height: Int
        var refresh = 60.0
        if isCustom {
            guard let w = Int(customWidth.trimmingCharacters(in: .whitespaces)),
                  let h = Int(customHeight.trimmingCharacters(in: .whitespaces)),
                  VirtualDisplayService.validSizeRange.contains(w),
                  VirtualDisplayService.validSizeRange.contains(h)
            else {
                let r = VirtualDisplayService.validSizeRange
                validationError = "Width and height must be whole numbers from \(r.lowerBound) to \(r.upperBound)."
                return
            }
            guard let hz = Double(customRefresh.trimmingCharacters(in: .whitespaces)),
                  VirtualDisplayService.validRefreshRange.contains(hz)
            else {
                validationError = "Refresh rate must be between 24 and 240 Hz."
                return
            }
            width = w; height = h; refresh = hz
        } else {
            width = presets[selectedPreset].width
            height = presets[selectedPreset].height
        }

        guard let extras = parseExtraModes(extraModesText) else {
            let r = VirtualDisplayService.validSizeRange
            validationError = "Extra resolutions must look like 1440x900, 2048x1152 (\(r.lowerBound)–\(r.upperBound) px)."
            return
        }
        validationError = nil

        let config = VirtualDisplayService.VirtualDisplayConfig(
            name: name.isEmpty ? "Virtual Display" : name,
            width: width,
            height: height,
            refreshRate: refresh,
            hiDPI: hiDPI,
            autoCreate: autoCreate,
            extraModes: extras.isEmpty ? nil : extras
        )
        onConfirm(config)
    }
}
