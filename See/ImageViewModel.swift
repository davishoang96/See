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
    @Published var rotationAngle: Angle = .zero
    @Published var saveError: String?
    
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
                    if url.startAccessingSecurityScopedResource() {
                        accessedFolders.append(url)
                    } else {
                        staleBookmarks.append(path)
                    }
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
            
            // Keep track of accessed folders (check by path, not instance)
            if !accessedFolders.contains(where: { $0.path == url.path }) {
                if url.startAccessingSecurityScopedResource() {
                    accessedFolders.append(url)
                }
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
        panel.message = "Select a folder to view images\n\nThis will grant read and write permissions to save rotated images."
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
            folderPanel.message = "Grant read and write access to this folder\n\nThis allows viewing images and saving rotated images."
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
        resetRotation()
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
    
    // MARK: - Rotation Methods
    
    func rotateLeft() {
        rotationAngle -= .degrees(90)
    }
    
    func rotateRight() {
        rotationAngle += .degrees(90)
    }
    
    func resetRotation() {
        rotationAngle = .zero
    }
    
    // MARK: - Delete Methods
    
    func deleteCurrentImage() {
        guard let imagePath = currentImagePath,
              !imageFiles.isEmpty else {
            saveError = "No image to delete"
            return
        }
        
        // Show confirmation dialog
        let alert = NSAlert()
        alert.messageText = "Delete Image?"
        alert.informativeText = "Are you sure you want to move \"\(imagePath.lastPathComponent)\" to the Trash? This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            performDelete(at: imagePath)
        }
    }
    
    private func performDelete(at url: URL) {
        do {
            // Move to trash
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            
            // Remove from our arrays
            if let index = imageFiles.firstIndex(of: url) {
                imageFiles.remove(at: index)
                thumbnails.removeValue(forKey: url)
                
                // Navigate to next image or previous if at the end
                if imageFiles.isEmpty {
                    // No more images
                    currentImage = nil
                    currentImagePath = nil
                    currentIndex = 0
                } else {
                    // Adjust index if we deleted the last image
                    if index >= imageFiles.count {
                        currentIndex = imageFiles.count - 1
                    } else {
                        currentIndex = index
                    }
                    loadCurrentImage()
                }
            }
            
            saveError = nil
        } catch {
            print("Failed to delete image: \(error)")
            saveError = "Failed to delete the image: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Save Methods
    
    func saveImage() {
        guard let image = currentImage,
              let imagePath = currentImagePath else {
            saveError = "No image loaded"
            return
        }
        
        // Only save if there's a rotation applied
        guard rotationAngle.degrees != 0 else {
            return
        }
        
        // Apply rotation to the image
        let rotatedImage = rotateImage(image, by: rotationAngle.degrees)
        
        // Try to save with security-scoped access
        let folderURL = imagePath.deletingLastPathComponent()
        
        // Check if we have a bookmark for this folder
        var hasAccess = false
        for accessedFolder in accessedFolders {
            if folderURL.path.hasPrefix(accessedFolder.path) {
                hasAccess = true
                break
            }
        }
        
        // If we don't have access, request it
        if !hasAccess {
            // Request access to the folder
            let openPanel = NSOpenPanel()
            openPanel.message = "Grant write permission to save the rotated image\n\nPlease select the folder containing the image."
            openPanel.prompt = "Grant Write Access"
            openPanel.canChooseFiles = false
            openPanel.canChooseDirectories = true
            openPanel.canCreateDirectories = false
            openPanel.directoryURL = folderURL
            
            openPanel.begin { [weak self] response in
                guard let self = self else { return }
                
                if response == .OK, let selectedURL = openPanel.url {
                    // Save the bookmark (this also starts accessing the resource)
                    self.saveBookmark(for: selectedURL)
                    
                    // Now try to save
                    self.performSave(rotatedImage, to: imagePath)
                } else {
                    self.saveError = "Permission denied to save the file"
                }
            }
        } else {
            // We have access, just save
            performSave(rotatedImage, to: imagePath)
        }
    }
    
    private func performSave(_ rotatedImage: NSImage, to url: URL) {
        if saveImage(rotatedImage, to: url) {
            // Reset rotation angle after saving
            rotationAngle = .zero
            saveError = nil
            // Reload the image to show the saved version
            loadCurrentImage()
            // Update the thumbnail for this image
            updateThumbnail(for: url)
        } else {
            saveError = "Failed to save the image. Please check file permissions."
        }
    }
    
    private func updateThumbnail(for url: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            if let image = NSImage(contentsOf: url) {
                let thumbnail = self.createThumbnail(from: image)
                
                DispatchQueue.main.async {
                    self.thumbnails[url] = thumbnail
                }
            }
        }
    }
    
    private func rotateImage(_ image: NSImage, by degrees: Double) -> NSImage {
        // Normalize the angle to 0, 90, 180, or 270
        let normalizedDegrees = Int(degrees.truncatingRemainder(dividingBy: 360))
        let rotationDegrees = ((normalizedDegrees % 360) + 360) % 360
        
        guard rotationDegrees != 0 else { return image }
        
        // Get the image representation
        guard let imageData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: imageData) else {
            return image
        }
        
        // Calculate new size based on rotation
        let originalWidth = bitmap.pixelsWide
        let originalHeight = bitmap.pixelsHigh
        
        let newWidth: Int
        let newHeight: Int
        
        if rotationDegrees == 90 || rotationDegrees == 270 {
            newWidth = originalHeight
            newHeight = originalWidth
        } else {
            newWidth = originalWidth
            newHeight = originalHeight
        }
        
        // Create a new bitmap context with the rotated size
        let newBitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: newWidth,
            pixelsHigh: newHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        
        guard let newBitmap = newBitmap else { return image }
        
        // Create graphics context and apply rotation
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: newBitmap)
        NSGraphicsContext.current = context
        
        let transform = NSAffineTransform()
        
        // Note: NSAffineTransform rotates counter-clockwise for positive angles,
        // but SwiftUI's rotationEffect rotates clockwise, so we need to negate
        switch rotationDegrees {
        case 90:
            // Rotate 90° clockwise = -90° in NSAffineTransform
            transform.translateX(by: 0, yBy: CGFloat(newHeight))
            transform.rotate(byDegrees: -90)
        case 180:
            transform.translateX(by: CGFloat(newWidth), yBy: CGFloat(newHeight))
            transform.rotate(byDegrees: -180)
        case 270:
            // Rotate 270° clockwise = -270° in NSAffineTransform
            transform.translateX(by: CGFloat(newWidth), yBy: 0)
            transform.rotate(byDegrees: -270)
        default:
            break
        }
        
        transform.concat()
        
        // Draw the original image
        let rect = NSRect(x: 0, y: 0, width: originalWidth, height: originalHeight)
        bitmap.draw(in: rect)
        
        NSGraphicsContext.restoreGraphicsState()
        
        // Create new image from the rotated bitmap
        let rotatedImage = NSImage(size: NSSize(width: newWidth, height: newHeight))
        rotatedImage.addRepresentation(newBitmap)
        
        return rotatedImage
    }
    
    private func saveImage(_ image: NSImage, to url: URL) -> Bool {
        guard let imageData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: imageData) else {
            return false
        }
        
        // Determine the file type from the URL extension
        let fileExtension = url.pathExtension.lowercased()
        let imageFileType: NSBitmapImageRep.FileType
        
        switch fileExtension {
        case "jpg", "jpeg":
            imageFileType = .jpeg
        case "png":
            imageFileType = .png
        case "tiff", "tif":
            imageFileType = .tiff
        case "bmp":
            imageFileType = .bmp
        case "gif":
            imageFileType = .gif
        default:
            imageFileType = .png
        }
        
        // Get image data in the appropriate format
        let properties: [NSBitmapImageRep.PropertyKey: Any]
        if imageFileType == .jpeg {
            properties = [.compressionFactor: 0.9]
        } else {
            properties = [:]
        }
        
        guard let data = bitmap.representation(using: imageFileType, properties: properties) else {
            return false
        }
        
        // Write to file (security-scoped access already active from loadSavedBookmarks)
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            print("Failed to save image: \(error)")
            saveError = error.localizedDescription
            return false
        }
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

