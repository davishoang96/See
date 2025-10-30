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
    @AppStorage("showFilmstrip") private var showFilmstrip = true
    
    var body: some View {
        mainContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .clipped()
            .focusable()
            .focusEffectDisabled()
            .modifier(KeyboardShortcutsModifier(viewModel: viewModel))
            .onOpenURL { url in
                viewModel.loadImageAndFolder(from: url)
            }
            .toolbar { toolbarContent }
            .toolbarRole(.automatic)
            .persistentSystemOverlays(.hidden)
    }
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            imageArea
            filmstripArea
        }
        .animation(.spring(response: 0.3), value: showFilmstrip)
    }
    
    private var imageArea: some View {
        ZStack {
            if let image = viewModel.currentImage {
                ZoomableImageView(image: image, viewModel: viewModel)
            } else {
                emptyStateView
            }
        }
    }
    
    @ViewBuilder
    private var filmstripArea: some View {
        if viewModel.imageFiles.count > 1 && showFilmstrip {
            FilmstripView(viewModel: viewModel)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            
            Text("No Image Loaded")
                .font(.title)
                .foregroundColor(.secondary)
            
            openButtons
            
            instructionText
        }
    }
    
    private var openButtons: some View {
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
    }
    
    private var instructionText: some View {
        VStack(spacing: 4) {
            Text("⌘O to open an image")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("⌘⇧O to open a folder")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            titleView
        }
        
        Group {
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
        }
        
        Group {
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
        }
        
        Group {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    viewModel.zoomOut()
                }) {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                .disabled(viewModel.currentImage == nil)
                .help("Zoom out (⌘-)")
            }
            
            ToolbarItem(placement: .automatic) {
                Button(action: { viewModel.resetZoom() }) {
                    Label("Reset Zoom", systemImage: "1.magnifyingglass")
                }
                .disabled(viewModel.currentImage == nil || viewModel.zoomScale == 1.0)
                .help("Reset zoom (⌘0)")
            }
            
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    viewModel.zoomIn()
                }) {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                .disabled(viewModel.currentImage == nil)
                .help("Zoom in (⌘+)")
            }
        }
        
        Group {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    viewModel.rotateLeft()
                }) {
                    Label("Rotate Left", systemImage: "rotate.left")
                }
                .disabled(viewModel.currentImage == nil)
                .help("Rotate left 90° (⌘[)")
            }
            
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    viewModel.rotateRight()
                }) {
                    Label("Rotate Right", systemImage: "rotate.right")
                }
                .disabled(viewModel.currentImage == nil)
                .help("Rotate right 90° (⌘])")
            }
        }
    
        ToolbarItem(placement: .automatic) {
            Button(action: {
                showFilmstrip.toggle()
            }) {
                Label(showFilmstrip ? "Hide Filmstrip" : "Show Filmstrip",
                      systemImage: showFilmstrip ? "photo.stack" : "photo.stack.fill")
            }
            .disabled(viewModel.imageFiles.count <= 1)
            .help("Toggle filmstrip")
        }
    }
    
    @ViewBuilder
    private var titleView: some View {
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
}

struct KeyboardShortcutsModifier: ViewModifier {
    @ObservedObject var viewModel: ImageViewModel
    
    func body(content: Content) -> some View {
        content
            .onKeyPress(.leftArrow) {
                viewModel.previousImage()
                return .handled
            }
            .onKeyPress(.rightArrow) {
                viewModel.nextImage()
                return .handled
            }
            .onKeyPress(characters: .init(charactersIn: "+=")) { press in
                if press.modifiers.contains(.command) {
                    viewModel.zoomIn()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(characters: .init(charactersIn: "-")) { press in
                if press.modifiers.contains(.command) {
                    viewModel.zoomOut()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(characters: .init(charactersIn: "0")) { press in
                if press.modifiers.contains(.command) {
                    viewModel.resetZoom()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(characters: .init(charactersIn: "[")) { press in
                if press.modifiers.contains(.command) {
                    viewModel.rotateLeft()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(characters: .init(charactersIn: "]")) { press in
                if press.modifiers.contains(.command) {
                    viewModel.rotateRight()
                    return .handled
                }
                return .ignored
            }
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

struct ZoomableImageView: View {
    let image: NSImage
    @ObservedObject var viewModel: ImageViewModel
    @State private var lastMagnification: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .rotationEffect(viewModel.rotationAngle)
                .animation(.easeInOut(duration: 0.3), value: viewModel.rotationAngle)
                .scaleEffect(viewModel.zoomScale)
                .offset(viewModel.imageOffset)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                .gesture(magnificationGesture(in: geometry.size))
                .simultaneousGesture(dragGesture)
                .onTapGesture(count: 2) {
                    handleDoubleTap(in: geometry.size)
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        viewModel.mouseLocation = location
                    case .ended:
                        break
                    }
                }
                .onAppear {
                    viewModel.viewSize = geometry.size
                    lastOffset = viewModel.imageOffset
                }
                .onChange(of: geometry.size) { _, newSize in
                    viewModel.viewSize = newSize
                }
                .onChange(of: viewModel.imageOffset) { _, newOffset in
                    // Sync lastOffset when the offset changes (unless we're actively dragging)
                    if !isDragging {
                        lastOffset = newOffset
                    }
                }
        }
    }
    
    private func handleDoubleTap(in size: CGSize) {
        // Double each time you double-click (up to max zoom)
        let newScale = viewModel.zoomScale * 2.0
        viewModel.setZoom(newScale, at: viewModel.mouseLocation, in: size)
    }
    
    private func magnificationGesture(in size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                viewModel.setZoom(lastMagnification * value, at: viewModel.mouseLocation, in: size)
            }
            .onEnded { _ in
                lastMagnification = viewModel.zoomScale
                lastOffset = viewModel.imageOffset
            }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard viewModel.zoomScale > 1.0 else { return }
                isDragging = true
                let newOffset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                viewModel.updateOffset(newOffset)
            }
            .onEnded { _ in
                isDragging = false
                lastOffset = viewModel.imageOffset
            }
    }
}

#Preview {
    ContentView()
}
