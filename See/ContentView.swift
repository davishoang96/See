//
//  ContentView.swift
//  See
//
//  Created by davis on 27/10/2025.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var viewModel = ImageViewModel()
    @State private var isHoveringOverImage = false
    @AppStorage("showFilmstrip") private var showFilmstrip = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Main image area
            ZStack {
                if let image = viewModel.currentImage {
                    GeometryReader { geometry in
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    }
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 80))
                            .foregroundColor(.secondary)
                        
                        Text("No Image Loaded")
                            .font(.title)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            Button("Open Image") {
                                viewModel.openImage()
                            }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut("o", modifiers: .command)
                            
                            Button("Open Folder") {
                                viewModel.openFolder()
                            }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut("o", modifiers: [.command, .shift])
                        }
                        
                        VStack(spacing: 4) {
                            Text("⌘O to open an image")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("⌘⇧O to open a folder")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
            }
            
            // Filmstrip
            if viewModel.imageFiles.count > 1 && showFilmstrip {
                FilmstripView(viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .background(ignoresSafeAreaEdges: .all)
        .clipped()
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            viewModel.previousImage()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            viewModel.nextImage()
            return .handled
        }
        .onOpenURL { url in
            viewModel.loadImageAndFolder(from: url)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                if viewModel.currentImage != nil {
                    VStack(spacing: 2) {
                        Text(viewModel.currentFileName)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        if !viewModel.imageCountText.isEmpty {
                            Text(viewModel.imageCountText)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            ToolbarItem(placement: .navigation) {
                Button(action: { viewModel.openImage() }) {
                    Label("Open Image", systemImage: "photo")
                }
                .help("Open an image (⌘O)")
            }
            
            ToolbarItem(placement: .navigation) {
                Button(action: { viewModel.openFolder() }) {
                    Label("Open Folder", systemImage: "folder")
                }
                .help("Open a folder (⌘⇧O)")
            }
            
            ToolbarItem(placement: .navigation) {
                Button(action: { viewModel.previousImage() }) {
                    Label("Previous", systemImage: "chevron.left")
                }
                .disabled(viewModel.imageFiles.isEmpty)
                .help("Previous image (←)")
            }
            
            ToolbarItem(placement: .navigation) {
                Button(action: { viewModel.nextImage() }) {
                    Label("Next", systemImage: "chevron.right")
                }
                .disabled(viewModel.imageFiles.isEmpty)
                .help("Next image (→)")
            }
            
            ToolbarItem(placement: .automatic) {
                Button(action: { 
                    withAnimation(.spring(response: 0.3)) {
                        showFilmstrip.toggle()
                    }
                }) {
                    Label(showFilmstrip ? "Hide Filmstrip" : "Show Filmstrip", 
                          systemImage: showFilmstrip ? "photo.stack" : "photo.stack.fill")
                }
                .disabled(viewModel.imageFiles.count <= 1)
                .help("Toggle filmstrip")
            }
        }
        .toolbarRole(.automatic)
        .persistentSystemOverlays(.hidden)
    }
}

struct FilmstripView: View {
    @ObservedObject var viewModel: ImageViewModel
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(viewModel.imageFiles.enumerated()), id: \.offset) { index, url in
                        ThumbnailView(
                            url: url,
                            thumbnail: viewModel.thumbnails[url],
                            isSelected: index == viewModel.currentIndex
                        )
                        .onTapGesture {
                            viewModel.selectImage(at: index)
                        }
                        .id(index)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(height: 100)
            .background(Color.black.opacity(0.95))
            .onChange(of: viewModel.currentIndex) { oldValue, newValue in
                withAnimation {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
}

struct ThumbnailView: View {
    let url: URL
    let thumbnail: NSImage?
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 64, height: 64)
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
        }
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

#Preview {
    ContentView()
}
