//
//  ImageViewModel.swift
//  See
//
//  Created by davis on 27/10/2025.
//

import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

class ImageViewModel: ObservableObject {
    @Published var currentImage: NSImage?
    @Published var currentImagePath: URL?
    @Published var imageFiles: [URL] = []
    @Published var currentIndex: Int = 0
    @Published var thumbnails: [URL: NSImage] = [:]
    @Published var zoomScale: CGFloat = 1.0
    @Published var imageOffset: CGSize = .zero
    
    var mouseLocation: CGPoint = .zero
    var viewSize: CGSize = .zero
    
    private let supportedImageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "webp"]
    private let thumbnailSize = NSSize(width: 64, height: 64)
    private let bookmarksKey = "FolderBookmarks"
    private var accessedFolders: [URL] = []
    private let minZoomScale: CGFloat = 0.1
    private let maxZoomScale: CGFloat = 10.0
    private let zoomStep: CGFloat = 0.2
    
    init() {
        loadSavedBookmarks()
    }
    
    deinit {
        // Stop accessing security-scoped resources
        accessedFolders.forEach { $0.stopAccessingSecurityScopedResource() }
    }
    
    // MARK: - Bookmark Management
    
    private func loadSavedBookmarks() {
        guard let bookmarksData = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] else {
            return
        }
        
        var staleBookmarks: [String] = []
        
        for (path, bookmarkData) in bookmarksData {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmarkData,
                                options: .withSecurityScope,
                                relativeTo: nil,
                                bookmarkDataIsStale: &isStale)
                
                if !isStale {
                    _ = url.startAccessingSecurityScopedResource()
                    accessedFolders.append(url)
                } else {
                    staleBookmarks.append(path)
                }
            } catch {
                print("Failed to resolve bookmark for \(path): \(error)")
                staleBookmarks.append(path)
            }
        }
        
        // Clean up stale bookmarks
        if !staleBookmarks.isEmpty {
            var updatedBookmarks = bookmarksData
            staleBookmarks.forEach { updatedBookmarks.removeValue(forKey: $0) }
            UserDefaults.standard.set(updatedBookmarks, forKey: bookmarksKey)
        }
    }
    
    private func saveBookmark(for url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope,
                                                   includingResourceValuesForKeys: nil,
                                                   relativeTo: nil)
            
            var bookmarks = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
            bookmarks[url.path] = bookmarkData
            UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
            
            // Keep track of accessed folders
            if !accessedFolders.contains(url) {
                _ = url.startAccessingSecurityScopedResource()
                accessedFolders.append(url)
            }
        } catch {
            print("Failed to create bookmark for \(url.path): \(error)")
        }
    }
    
    private func hasSavedAccess(to directory: URL) -> Bool {
        // Check if we already have this folder in our accessed list
        return accessedFolders.contains(where: { $0.path == directory.path })
    }
    
    func openImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.message = "Select an image to view"
        
        panel.begin { [weak self] response in
            guard let self = self else { return }
            
            if response == .OK, let url = panel.url {
                NSApp.activate(ignoringOtherApps: true)
                self.loadImageAndFolder(from: url)
            }
        }
    }
    
    func openFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Select a folder to view images"
        panel.prompt = "Choose Folder"
        
        panel.begin { [weak self] response in
            guard let self = self else { return }
            
            if response == .OK, let url = panel.url {
                NSApp.activate(ignoringOtherApps: true)
                // Save the bookmark for future access
                self.saveBookmark(for: url)
                self.loadImagesFromDirectory(url, selectedFile: nil)
            }
        }
    }
    
    func loadImageAndFolder(from url: URL) {
        // Activate and focus the app
        NSApp.activate(ignoringOtherApps: true)
        
        // Get the parent directory
        let directory = url.deletingLastPathComponent()
        
        // Check if we already have access to this folder
        if hasSavedAccess(to: directory) {
            // We already have access, load the image and all images from folder
            currentImagePath = url
            currentImage = NSImage(contentsOf: url)
            loadImagesFromDirectory(directory, selectedFile: url)
        } else {
            // Ask for explicit permission to access the folder first
            let folderPanel = NSOpenPanel()
            folderPanel.canChooseDirectories = true
            folderPanel.canChooseFiles = false
            folderPanel.allowsMultipleSelection = false
            folderPanel.directoryURL = directory
            folderPanel.message = "Allow access to this folder to view all images"
            folderPanel.prompt = "Grant Access"
            
            folderPanel.begin { [weak self] response in
                guard let self = self else { return }
                
                if response == .OK, let folderURL = folderPanel.url {
                    // Save the bookmark for future access
                    self.saveBookmark(for: folderURL)
                    
                    // Now load the selected image
                    self.currentImagePath = url
                    self.currentImage = NSImage(contentsOf: url)
                    
                    // Load all images from the directory
                    self.loadImagesFromDirectory(folderURL, selectedFile: url)
                } else {
                    // User denied access, just show the single image
                    self.currentImagePath = url
                    self.currentImage = NSImage(contentsOf: url)
                    self.imageFiles = [url]
                    self.currentIndex = 0
                }
            }
        }
    }
    
    private func loadImagesFromDirectory(_ directory: URL, selectedFile: URL?) {
        do {
            let fileManager = FileManager.default
            let contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            
            // Filter for valid image files only
            imageFiles = contents.filter { url in
                guard let ext = url.pathExtension.lowercased() as String? else { return false }
                guard supportedImageExtensions.contains(ext) else { return false }
                
                // Verify the image can actually be loaded
                return NSImage(contentsOf: url) != nil
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            // Find the index of the selected file, or default to first image
            if let selectedFile = selectedFile, let index = imageFiles.firstIndex(of: selectedFile) {
                currentIndex = index
            } else if !imageFiles.isEmpty {
                currentIndex = 0
                loadCurrentImage()
                // Activate app when loading folder
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            
            // Generate thumbnails in background
            generateThumbnails()
            
        } catch {
            print("Error loading directory contents: \(error)")
            if let selectedFile = selectedFile {
                imageFiles = [selectedFile]
                currentIndex = 0
            } else {
                imageFiles = []
                currentIndex = 0
            }
        }
    }
    
    private func generateThumbnails() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            for url in self.imageFiles {
                if let image = NSImage(contentsOf: url) {
                    let thumbnail = self.createThumbnail(from: image)
                    
                    DispatchQueue.main.async {
                        self.thumbnails[url] = thumbnail
                    }
                }
            }
        }
    }
    
    private func createThumbnail(from image: NSImage) -> NSImage {
        let thumbnail = NSImage(size: thumbnailSize)
        
        thumbnail.lockFocus()
        
        let imageSize = image.size
        let aspectRatio = imageSize.width / imageSize.height
        
        // Calculate source rectangle for center cropping
        var sourceRect: NSRect
        
        if aspectRatio > 1.0 {
            // Image is wider - crop from center horizontally
            let cropWidth = imageSize.height // Make it square
            let xOffset = (imageSize.width - cropWidth) / 2
            sourceRect = NSRect(x: xOffset, y: 0, width: cropWidth, height: imageSize.height)
        } else {
            // Image is taller - crop from center vertically
            let cropHeight = imageSize.width // Make it square
            let yOffset = (imageSize.height - cropHeight) / 2
            sourceRect = NSRect(x: 0, y: yOffset, width: imageSize.width, height: cropHeight)
        }
        
        // Draw the cropped portion into the 64x64 thumbnail
        image.draw(in: NSRect(origin: .zero, size: thumbnailSize),
                   from: sourceRect,
                   operation: .copy,
                   fraction: 1.0)
        
        thumbnail.unlockFocus()
        
        return thumbnail
    }
    
    func selectImage(at index: Int) {
        guard index >= 0 && index < imageFiles.count else { return }
        currentIndex = index
        loadCurrentImage()
    }
    
    func nextImage() {
        guard !imageFiles.isEmpty else { return }
        
        currentIndex = (currentIndex + 1) % imageFiles.count
        loadCurrentImage()
    }
    
    func previousImage() {
        guard !imageFiles.isEmpty else { return }
        
        currentIndex = (currentIndex - 1 + imageFiles.count) % imageFiles.count
        loadCurrentImage()
    }
    
    private func loadCurrentImage() {
        guard currentIndex >= 0 && currentIndex < imageFiles.count else { return }
        
        let url = imageFiles[currentIndex]
        currentImagePath = url
        currentImage = NSImage(contentsOf: url)
        resetZoom()
    }
    
    // MARK: - Zoom Methods
    
    func zoomIn(at point: CGPoint? = nil, in viewSize: CGSize? = nil) {
        let oldScale = zoomScale
        let newScale = min(zoomScale + zoomStep, maxZoomScale)
        zoomScale = newScale
        
        if let point = point, let viewSize = viewSize {
            adjustOffset(for: point, in: viewSize, oldScale: oldScale, newScale: newScale)
        } else {
            // Zoom to center - scale the offset proportionally
            adjustOffsetForCenterZoom(oldScale: oldScale, newScale: newScale)
        }
    }
    
    func zoomOut(at point: CGPoint? = nil, in viewSize: CGSize? = nil) {
        let oldScale = zoomScale
        let newScale = max(zoomScale - zoomStep, minZoomScale)
        zoomScale = newScale
        
        if newScale <= 1.0 {
            resetZoom()
        } else if let point = point, let viewSize = viewSize {
            adjustOffset(for: point, in: viewSize, oldScale: oldScale, newScale: newScale)
        } else {
            // Zoom to center - scale the offset proportionally
            adjustOffsetForCenterZoom(oldScale: oldScale, newScale: newScale)
        }
    }
    
    func resetZoom() {
        zoomScale = 1.0
        imageOffset = .zero
    }
    
    func setZoom(_ scale: CGFloat, at point: CGPoint? = nil, in viewSize: CGSize? = nil) {
        let oldScale = zoomScale
        let newScale = max(minZoomScale, min(scale, maxZoomScale))
        zoomScale = newScale
        
        if zoomScale <= 1.0 {
            resetZoom()
        } else if let point = point, let viewSize = viewSize {
            adjustOffset(for: point, in: viewSize, oldScale: oldScale, newScale: newScale)
        } else if oldScale != newScale {
            // Zoom to center - scale the offset proportionally
            adjustOffsetForCenterZoom(oldScale: oldScale, newScale: newScale)
        }
    }
    
    func updateOffset(_ offset: CGSize) {
        imageOffset = offset
    }
    
    private func adjustOffset(for point: CGPoint, in viewSize: CGSize, oldScale: CGFloat, newScale: CGFloat) {
        // Calculate the center of the view
        let centerX = viewSize.width / 2
        let centerY = viewSize.height / 2
        
        // Calculate the position of the mouse relative to the current offset and zoom
        // This gives us the "image coordinate" under the mouse
        let imageX = (point.x - centerX - imageOffset.width) / oldScale
        let imageY = (point.y - centerY - imageOffset.height) / oldScale
        
        // Now calculate what offset we need to keep that same image coordinate
        // at the same screen position with the new zoom level
        let newOffsetX = point.x - centerX - imageX * newScale
        let newOffsetY = point.y - centerY - imageY * newScale
        
        imageOffset = CGSize(width: newOffsetX, height: newOffsetY)
    }
    
    private func adjustOffsetForCenterZoom(oldScale: CGFloat, newScale: CGFloat) {
        // When zooming to center, scale the offset proportionally
        // This keeps the center of the image at the center of the view
        let scaleRatio = newScale / oldScale
        imageOffset = CGSize(
            width: imageOffset.width * scaleRatio,
            height: imageOffset.height * scaleRatio
        )
    }
    
    var currentFileName: String {
        currentImagePath?.lastPathComponent ?? "No image loaded"
    }
    
    var imageCountText: String {
        guard !imageFiles.isEmpty else { return "" }
        return "\(currentIndex + 1) / \(imageFiles.count)"
    }
}

