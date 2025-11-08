//
//  SettingsView.swift
//  See
//
//  Created by davis on 27/10/2025.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("showFilmstrip") private var showFilmstrip = true
    @AppStorage("imageDecodeQuality") private var imageDecodeQuality: Double = 800
    @AppStorage("thumbnailSize") private var thumbnailSize: Double = 64
    @AppStorage("fitWindowToImage") private var fitWindowToImage: Bool = false
    @AppStorage("maximizeWindowOnOpen") private var maximizeWindowOnOpen: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                GeneralSettingsSection(
                    showFilmstrip: $showFilmstrip,
                    imageDecodeQuality: $imageDecodeQuality,
                    thumbnailSize: $thumbnailSize,
                    fitWindowToImage: $fitWindowToImage,
                    maximizeWindowOnOpen: $maximizeWindowOnOpen
                )
                
                AboutSection()
            }
            .formStyle(.grouped)
            .frame(width: 600, height: 500)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.escape)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

struct GeneralSettingsSection: View {
    @Binding var showFilmstrip: Bool
    @Binding var imageDecodeQuality: Double
    @Binding var thumbnailSize: Double
    @Binding var fitWindowToImage: Bool
    @Binding var maximizeWindowOnOpen: Bool
    
    var body: some View {
        Section("General") {
            Toggle("Fit window to image", isOn: $fitWindowToImage)
                .help("Automatically resize the window to fit the image size")
            
            Toggle("Maximize window when opening image", isOn: $maximizeWindowOnOpen)
                .help("Automatically maximize the window when a new image loads")
            
            Toggle("Show filmstrip by default", isOn: $showFilmstrip)
                .help("Show the filmstrip at the bottom when viewing images")
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Image decode quality")
                    Spacer()
                    Text("\(Int(imageDecodeQuality))px")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                
                Slider(value: $imageDecodeQuality, in: 400...2000, step: 100) {
                    Text("Image decode quality")
                }
                .help("Higher values provide better quality but slower loading. Recommended: 800-1200px")
                
                Text("Controls the maximum pixel dimension for decoded images. Lower values load faster.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Thumbnail size")
                    Spacer()
                    Text("\(Int(thumbnailSize))×\(Int(thumbnailSize))")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                
                Slider(value: $thumbnailSize, in: 32...128, step: 8) {
                    Text("Thumbnail size")
                }
                .help("Size of thumbnails in the filmstrip")
                
                Text("Size of thumbnails displayed in the filmstrip at the bottom.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct AboutSection: View {
    var body: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Build")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            
            Link("GitHub", destination: URL(string: "https://github.com")!)
                .foregroundColor(.accentColor)
        }
    }
}

#Preview {
    SettingsView()
}

