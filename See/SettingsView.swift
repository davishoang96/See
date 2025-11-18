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
    @AppStorage("thumbnailSize") private var thumbnailSize: Double = 64
    @AppStorage("fitWindowToImage") private var fitWindowToImage: Bool = false
    @AppStorage("maximizeWindowOnOpen") private var maximizeWindowOnOpen: Bool = false
    @AppStorage("loadFullResolutionImages") private var loadFullResolutionImages: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                GeneralSettingsSection(
                    showFilmstrip: $showFilmstrip,
                    thumbnailSize: $thumbnailSize,
                    fitWindowToImage: $fitWindowToImage,
                    maximizeWindowOnOpen: $maximizeWindowOnOpen,
                    loadFullResolutionImages: $loadFullResolutionImages
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
    @Binding var thumbnailSize: Double
    @Binding var fitWindowToImage: Bool
    @Binding var maximizeWindowOnOpen: Bool
    @Binding var loadFullResolutionImages: Bool
    
    var body: some View {
        Section("General") {
            Toggle("Fit window to image", isOn: $fitWindowToImage)
                .help("Automatically resize the window to fit the image size")
            
            Toggle("Maximize window when opening image", isOn: $maximizeWindowOnOpen)
                .help("Automatically maximize the window when a new image loads")

            Toggle("Load full-resolution images", isOn: $loadFullResolutionImages)
                .help("Decode images at their original pixel dimensions. Uses more memory but keeps very large photos sharp.")
            
            Toggle("Show filmstrip by default", isOn: $showFilmstrip)
                .help("Show the filmstrip at the bottom when viewing images")
            
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

