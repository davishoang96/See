# See

A minimalist, fast image viewer for macOS with an elegant AMOLED black interface.

## Features

### Core Functionality
- **Fast Image Viewing** - Opens and displays images instantly
- **Folder Navigation** - Browse all images in a folder with left/right arrow keys
- **Auto Window Sizing** - Window automatically resizes to fit image while maintaining aspect ratio
- **AMOLED Black Theme** - Pure black background for optimal viewing and battery savings on OLED displays

### Navigation
- **Keyboard Shortcuts**
  - `←` / `→` - Navigate between images
  - `⌘O` - Open image file
  - `⌘⇧O` - Open folder
  - `⌘+` / `⌘=` - Zoom in
  - `⌘-` - Zoom out
  - `⌘0` - Reset zoom to 100%
- **Filmstrip View** - Visual thumbnail strip at bottom for quick image selection
  - Click thumbnails to jump to any image
  - Toggle visibility with toolbar button
  - Preference saved across sessions

### Zoom & Pan
- **Zoom Controls** - Zoom from 10% to 1000% (10x magnification)
  - Toolbar buttons for zoom in/out/reset
  - Keyboard shortcuts (⌘+, ⌘-, ⌘0)
  - Pinch gesture on trackpad to zoom
  - **Double-click** to progressively zoom in (2x each click: 100% → 200% → 400% → 800%)
  - Drag to pan when zoomed beyond 100%
- **Zoom to Cursor** - Intelligent zoom behavior
  - Toolbar buttons & keyboard shortcuts: Zoom to center (keeps image centered)
  - Trackpad pinch & double-click: Zooms towards cursor position
  - Natural and intuitive for both mouse and trackpad users
- **Smart Zoom** - Automatically resets to 100% when:
  - Switching to a different image
  - Zooming out below 100%
  - Pressing reset zoom (⌘0)

### Smart Folder Access
- **Persistent Permissions** - Grant folder access once, use forever
- **Security-Scoped Bookmarks** - Remembers folder permissions using macOS sandboxing
- **Automatic Detection** - Filters out broken/corrupted images

### User Experience
- **Compact Interface** - Hidden title bar with auto-hide in fullscreen
- **Centered Info** - Filename and image count displayed in top bar
- **64x64 Thumbnails** - Center-cropped square thumbnails for consistent appearance
- **Smooth Animations** - Filmstrip slides in/out with spring animation
- **Auto Focus** - App automatically comes to foreground when opening images

## Supported Formats

- JPEG/JPG
- PNG
- GIF
- BMP
- TIFF
- HEIC
- WebP

## Requirements

- macOS 15.0 or later
- Xcode 16.0 or later (for building)

## Installation

### Option 1: Build from Source
1. Clone this repository
2. Open `See.xcodeproj` in Xcode
3. Build and run (⌘R)

### Option 2: Set as Default Viewer
1. Build and export the app
2. Right-click any image → Get Info
3. Open with: → Choose "See"
4. Click "Change All..." to set as default for that file type

## Usage

### First Time
1. Launch See
2. Click "Open Image" or press `⌘O`
3. Select an image file
4. Grant folder access when prompted (one-time per folder)

### After Setup
- Double-click any image to open in See (if set as default)
- Use arrow keys to navigate through images
- Toggle filmstrip for thumbnail navigation

## Privacy & Security

See is fully sandboxed and only accesses:
- Images you explicitly select
- Folders you grant permission to
- Permissions are stored locally using security-scoped bookmarks

## License

[Your License Here]

## Author

Created by davis

