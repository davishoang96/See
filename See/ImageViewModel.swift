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
    @Published var exifData: [String: String] = [:]
    
    var mouseLocation: CGPoint = .zero
    var viewSize: CGSize = .zero
    
    private let supportedImageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "webp"]
    private var thumbnailSize: NSSize {
        let size = UserDefaults.standard.double(forKey: "thumbnailSize")
        let dimension = size > 0 ? size : 64 // Default to 64 if not set
        return NSSize(width: dimension, height: dimension)
    }
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
        
        // Set path immediately and load image asynchronously
        currentImagePath = url
        loadImageAsync(from: url)
        
        // Get the parent directory
        let directory = url.deletingLastPathComponent()
        
        // Check if we already have access to this folder
        if hasSavedAccess(to: directory) {
            // We already have access, load all images from folder
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
                    
                    // Load all images from the directory
                    self.loadImagesFromDirectory(folderURL, selectedFile: url)
                } else {
                    // User denied access, just show the single image
                    self.imageFiles = [url]
                    self.currentIndex = 0
                }
            }
        }
    }
    
    // Fast async image loading - never blocks main thread
    private func loadImageAsync(from url: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let image = self.loadImageWithCorrectOrientation(from: url)
            DispatchQueue.main.async {
                // Only apply if still on same image
                if self.currentImagePath == url {
                    self.currentImage = image
                    self.resetZoom()
                    self.resetRotation()
                }
            }
        }
    }
    
    private func loadImagesFromDirectory(_ directory: URL, selectedFile: URL?) {
        // Do file listing off main thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let fileManager = FileManager.default
                let contents = try fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
                
                // Ultra-fast filter: just by extension
                // Files from contentsOfDirectory already exist, no need to check
                let extensionFiltered = contents.filter { url in
                    let ext = url.pathExtension.lowercased()
                    return self.supportedImageExtensions.contains(ext)
                }
                
                // Immediately show the file list (no validation blocking)
                // Broken files will be filtered out later during thumbnail generation
                var sortedFiles = extensionFiltered.sorted { $0.lastPathComponent < $1.lastPathComponent }
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    // Set files immediately for instant UI update
                    self.imageFiles = sortedFiles
                    
                    // Find selected file index
                    if let selectedFile = selectedFile, let index = sortedFiles.firstIndex(of: selectedFile) {
                        self.currentIndex = index
                        // Image already loading via loadImageAsync, no need to load again
                    } else if !sortedFiles.isEmpty {
                        self.currentIndex = 0
                        // Load first image if no selection
                        if self.currentImage == nil {
                            self.loadCurrentImage()
                        }
                    }
                }
                
                // Generate thumbnails in background
                // This will also filter out any broken files
                DispatchQueue.main.async {
                    self.generateThumbnails()
                }
                
            } catch {
                print("Error loading directory contents: \(error)")
                DispatchQueue.main.async {
                    if let selectedFile = selectedFile {
                        self.imageFiles = [selectedFile]
                        self.currentIndex = 0
                    } else {
                        self.imageFiles = []
                        self.currentIndex = 0
                    }
                }
            }
        }
    }
    
    // Note: File validation removed from initial load for speed
    // Broken files are filtered out during thumbnail generation instead
    
    func regenerateThumbnails() {
        // Clear existing thumbnails and regenerate with new settings
        thumbnails.removeAll()
        generateThumbnails()
    }
    
    private func generateThumbnails() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            // Capture current file list to avoid race conditions
            let filesToProcess = self.imageFiles
            let brokenFiles = NSMutableArray()
            let lock = NSLock()
            
            // Generate thumbnails in parallel
            DispatchQueue.concurrentPerform(iterations: filesToProcess.count) { index in
                let url = filesToProcess[index]
                let ext = url.pathExtension.lowercased()
                guard self.supportedImageExtensions.contains(ext) else { return }
                
                autoreleasepool {
                    // Try to load thumbnail - this validates the file
                    if let thumbnail = self.loadThumbnail(for: url) {
                        // Update thumbnail on main thread
                        DispatchQueue.main.async {
                            self.thumbnails[url] = thumbnail
                        }
                    } else {
                        // File is broken, mark for removal
                        lock.lock()
                        brokenFiles.add(url)
                        lock.unlock()
                    }
                }
            }
            
            // Remove broken files on main thread (batch update for efficiency)
            if brokenFiles.count > 0 {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    let broken = brokenFiles.compactMap { $0 as? URL }
                    var updatedFiles = self.imageFiles
                    var indexAdjustment = 0
                    
                    for brokenUrl in broken {
                        if let index = updatedFiles.firstIndex(of: brokenUrl) {
                            updatedFiles.remove(at: index)
                            if index <= self.currentIndex {
                                indexAdjustment += 1
                            }
                        }
                    }
                    
                    if !broken.isEmpty {
                        self.imageFiles = updatedFiles
                        if self.currentIndex >= indexAdjustment {
                            self.currentIndex -= indexAdjustment
                        } else {
                            self.currentIndex = 0
                        }
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
        
        // Decode off the main thread to keep UI responsive
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let image = self.loadImageWithCorrectOrientation(from: url)
            DispatchQueue.main.async {
                // Only apply if still on same image
                if self.currentImagePath == url {
                    self.currentImage = image
                    self.resetZoom()
                    self.resetRotation()
                }
            }
        }
    }
    
    func refreshEXIF() {
        guard let url = currentImagePath else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.extractEXIFData(from: url)
        }
    }

    private func extractEXIFData(from url: URL) {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            exifData = [:]
            return
        }
        
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            exifData = [:]
            return
        }
        
        var metadata: [String: String] = [:]
        
        // Basic image properties
        if let width = properties[kCGImagePropertyPixelWidth] as? Int {
            metadata["Dimensions"] = "\(width)"
        }
        if let height = properties[kCGImagePropertyPixelHeight] as? Int {
            if let existing = metadata["Dimensions"] {
                metadata["Dimensions"] = "\(existing) × \(height)"
            } else {
                metadata["Dimensions"] = "× \(height)"
            }
        }
        
        if let dpi = properties[kCGImagePropertyDPIWidth] as? Double {
            metadata["DPI"] = String(format: "%.0f", dpi)
        }
        
        if let colorModel = properties[kCGImagePropertyColorModel] as? String {
            metadata["Color Model"] = colorModel
        }
        
        if let depth = properties[kCGImagePropertyDepth] as? Int {
            metadata["Depth"] = "\(depth) bits"
        }
        
        // File info
        if let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            metadata["File Size"] = formatter.string(fromByteCount: fileSize)
        }
        
        metadata["File Type"] = url.pathExtension.uppercased()
        
        // EXIF data
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let dateTime = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                metadata["Date Taken"] = dateTime
            }
            if let camera = exif[kCGImagePropertyExifLensMake] as? String {
                metadata["Camera"] = camera
            } else if let make = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
                      let makeName = make[kCGImagePropertyTIFFMake] as? String {
                metadata["Camera Make"] = makeName
            }
            
            if let model = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
               let modelName = model[kCGImagePropertyTIFFModel] as? String {
                metadata["Camera Model"] = modelName
            }
            
            if let fNumber = exif[kCGImagePropertyExifFNumber] as? Double {
                metadata["Aperture"] = String(format: "f/%.1f", fNumber)
            }
            
            if let exposureTime = exif[kCGImagePropertyExifExposureTime] as? Double {
                if exposureTime < 1 {
                    metadata["Shutter Speed"] = String(format: "1/%.0f s", 1.0 / exposureTime)
                } else {
                    metadata["Shutter Speed"] = String(format: "%.1f s", exposureTime)
                }
            }
            
            if let iso = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let isoValue = iso.first {
                metadata["ISO"] = "\(isoValue)"
            }
            
            if let focalLength = exif[kCGImagePropertyExifFocalLength] as? Double {
                metadata["Focal Length"] = String(format: "%.1f mm", focalLength)
            }
            
            if let flash = exif[kCGImagePropertyExifFlash] as? Int {
                metadata["Flash"] = flash & 1 == 1 ? "On" : "Off"
            }
        }
        
        // GPS data
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            if let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
               let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String,
               let lon = gps[kCGImagePropertyGPSLongitude] as? Double,
               let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String {
                metadata["GPS"] = String(format: "%.6f° %@, %.6f° %@", lat, latRef, lon, lonRef)
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.exifData = metadata
        }
    }
    
    private func loadImageWithCorrectOrientation(from url: URL) -> NSImage? {
        // Fast path: decode directly without reading properties first
        // This avoids double file opening which is slow
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return NSImage(contentsOf: url)
        }

        // Base decode quality in points (tuned for sharper desktop displays)
        let baseDecodeQuality: CGFloat = 1600
        let loadFullResolution = UserDefaults.standard.bool(forKey: "loadFullResolutionImages")
        
        // Determine screen-based minimum to avoid blurry fit-to-screen rendering
        let mainScreen = NSScreen.main ?? NSScreen.screens.first
        let screenScale = mainScreen?.backingScaleFactor ?? 2.0
        let screenMaxDimension = max(mainScreen?.frame.width ?? 1440, mainScreen?.frame.height ?? 900)
        let minimumPixelSize = Int(screenMaxDimension * screenScale)
        
        var maxPixelSize = max(Int(baseDecodeQuality * screenScale), minimumPixelSize)
        
        if loadFullResolution,
           let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
           let height = properties[kCGImagePropertyPixelHeight] as? CGFloat {
            let fullSize = Int(max(width, height))
            if fullSize > 0 {
                maxPixelSize = min(fullSize, 16000) // cap to avoid excessive memory usage
            }
        }

        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldAllowFloat: false, // Disable float for faster decoding
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // Apply EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return NSImage(contentsOf: url)
        }

        let size = NSSize(width: cgImage.width, height: cgImage.height)
        let image = NSImage(size: size)
        image.addRepresentation(NSBitmapImageRep(cgImage: cgImage))
        return image
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
            
            // Skip files not supported by the app
            let ext = url.pathExtension.lowercased()
            guard self.supportedImageExtensions.contains(ext) else { return }

            autoreleasepool(invoking: {
                if let thumbnail = self.loadThumbnail(for: url) {
                    DispatchQueue.main.async {
                        self.thumbnails[url] = thumbnail
                    }
                }
            })
        }
    }

    // Decode a fast, small thumbnail using CGImageSource without loading full image
    private func loadThumbnail(for url: URL) -> NSImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        // If the primary image index can't be read cleanly, treat as corrupted and skip
        let status = CGImageSourceGetStatusAtIndex(imageSource, 0)
        guard status == .statusComplete else {
            return nil
        }

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let maxSide = max(thumbnailSize.width, thumbnailSize.height)
        let maxPixel = Int(maxSide * scale)

        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }

        let size = NSSize(width: cgImage.width, height: cgImage.height)
        let image = NSImage(size: size)
        image.addRepresentation(NSBitmapImageRep(cgImage: cgImage))

        // Finally crop/fit to our square thumbnail canvas
        return createThumbnail(from: image)
    }
    
    // Ultra-fast validity check - skip file opening entirely for speed
    // Validation happens later during thumbnail generation
    private func isValidImageFileFast(_ url: URL) -> Bool {
        // No-op: validation deferred to thumbnail generation for speed
        // This function is kept for API compatibility but not used anymore
        return true
    }
    
    // More thorough check (used when we need to ensure decodability)
    private func isValidImageFile(_ url: URL) -> Bool {
        guard isValidImageFileFast(url) else { return false }
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        // Try to create a tiny thumbnail to ensure decodability
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 64
        ]
        return CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) != nil
    }

    // No placeholder; failed thumbnails are simply omitted
    
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
        // Get the bitmap representation directly from the image
        guard let bitmap = image.representations.first as? NSBitmapImageRep else {
            // Fallback: create a new bitmap from the image
            guard let imageData = image.tiffRepresentation,
                  let fallbackBitmap = NSBitmapImageRep(data: imageData) else {
                return false
            }
            return saveBitmap(fallbackBitmap, to: url)
        }
        
        return saveBitmap(bitmap, to: url)
    }
    
    private func saveBitmap(_ bitmap: NSBitmapImageRep, to url: URL) -> Bool {
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
        
        // Create fresh bitmap data without any metadata
        guard let cgImage = bitmap.cgImage else {
            return false
        }
        
        // Create a new destination for the image
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            imageFileType == .jpeg ? UTType.jpeg.identifier as CFString :
            imageFileType == .png ? UTType.png.identifier as CFString :
            imageFileType == .tiff ? UTType.tiff.identifier as CFString :
            imageFileType == .bmp ? UTType.bmp.identifier as CFString :
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return false
        }
        
        // Set properties with explicit orientation = 1 (normal, no rotation)
        var properties: [CFString: Any] = [
            kCGImagePropertyOrientation: 1  // Explicitly set to normal orientation
        ]
        
        if imageFileType == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.9
        }
        
        // Add the image to the destination with our properties
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        
        // Finalize and write
        let success = CGImageDestinationFinalize(destination)
        
        if !success {
            print("Failed to save image")
            saveError = "Failed to save the image"
        }
        
        return success
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

