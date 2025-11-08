//
//  SeeApp.swift
//  See
//
//  Created by davis on 27/10/2025.
//

import SwiftUI
import Combine
import AppKit

@main
struct SeeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
                .background(WindowAccessor())
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                // Remove default "New" command
            }
            
            CommandGroup(after: .appSettings) {
                Button("Settings...") {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
    }
}

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.isOpaque = true
                window.backgroundColor = .black
                window.hasShadow = true
                if let contentView = window.contentView {
                    contentView.wantsLayer = true
                    contentView.layer?.backgroundColor = NSColor.black.cgColor
                }
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            window.isOpaque = true
            window.backgroundColor = .black
            if let contentView = window.contentView {
                contentView.wantsLayer = true
                contentView.layer?.backgroundColor = NSColor.black.cgColor
            }
        }
    }
}
