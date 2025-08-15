#!/usr/bin/env swift
import AppKit
import Foundation
import QuickLookUI // QLPreviewView (macOS 10.15+)

// MARK: - Root path from argv (defaults to CWD)
let rootPath = (CommandLine.arguments.count > 1)
  ? CommandLine.arguments[1]
  : FileManager.default.currentDirectoryPath

// Keep windows/controllers alive for the life of the process
var __windowControllers: [NSWindowController] = []

// MARK: - Allowed Types / Filtering
struct FileFilter {
    let allowedExts: Set<String>
    
    func isAllowed(url: URL, isDirectory: Bool) -> Bool {
        // Always show directories to allow drilling
        if isDirectory {
            if url.lastPathComponent.hasPrefix(".") { return false }
            return true
        }
        if url.lastPathComponent.hasPrefix(".") { return false }
        
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty && allowedExts.contains(ext) { return true }
        return false
    }
}

// MARK: - Utilities
func listChildren(of dir: URL) -> [URL] {
    let opts: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
    return (try? FileManager.default.contentsOfDirectory(
        at: dir,
        includingPropertiesForKeys: [.isDirectoryKey, .contentTypeKey, .isHiddenKey],
        options: opts
    )) ?? []
}

func isDirectory(_ url: URL) -> Bool {
    ((try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory) ?? false
}

func exitSuccess(with url: URL) -> Never {
    print(url.path)
    fflush(stdout)
    exit(0)
}

func exitCancel() -> Never {
    exit(1)
}

// MARK: - Quick Look helper
@available(macOS 10.15, *)
final class PreviewItem: NSObject, QLPreviewItem {
    private let url: URL
    init(_ url: URL) { self.url = url }
    var previewItemURL: URL? { url }
}

// MARK: - Preview Pane
final class PreviewPane: NSView {
    private let placeholderLabel = NSTextField(labelWithString: "Select a file to preview")
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private var qlView: AnyObject? // store without importing QL types in signatures

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        // Placeholder
        placeholderLabel.alignment = .center
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.font = NSFont.systemFont(ofSize: 14)
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        // Text view fallback (hidden by default)
        textView.isEditable = false
        textView.isSelectable = true
        textView.usesFontPanel = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.isHidden = true

        addSubview(placeholderLabel)
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            placeholderLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Show a preview for the URL; if nil or directory, clear preview.
    func show(url: URL?) {
        guard let url = url, !isDirectory(url) else {
            removeQLViewIfNeeded()
            textView.string = ""
            scrollView.isHidden = true
            placeholderLabel.isHidden = false
            return
        }

        // Prefer Quick Look (nice Markdown rendering). If it fails, fallback to text.
        if #available(macOS 10.15, *) {
            // Create QLPreviewView lazily; unwrap failable initializer safely
            if qlView == nil {
                if let newQL = QLPreviewView(frame: bounds, style: .normal) {
                    newQL.autoresizingMask = [.width, .height]
                    addSubview(newQL, positioned: .below, relativeTo: placeholderLabel)
                    qlView = newQL
                }
            }
            if let ql = qlView as? QLPreviewView {
                ql.isHidden = false
                placeholderLabel.isHidden = true
                scrollView.isHidden = true
                ql.previewItem = PreviewItem(url)
                return
            }
        }

        // Fallback to plain text display
        removeQLViewIfNeeded()
        placeholderLabel.isHidden = true
        scrollView.isHidden = false
        do {
            if let data = try? Data(contentsOf: url),
               let str = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .macOSRoman)
                    ?? String(data: data, encoding: .isoLatin1) {
                textView.string = str
            } else {
                textView.string = try String(contentsOf: url, encoding: .utf8)
            }
        } catch {
            textView.string = "Unable to load preview: \(error.localizedDescription)"
        }
    }

    private func removeQLViewIfNeeded() {
        if let ql = qlView as? NSView {
            ql.removeFromSuperview()
        }
        qlView = nil
    }
}

// MARK: - NSBrowser (Columns)
final class BrowserDelegate: NSObject, NSBrowserDelegate {
    let root: URL
    let filter: FileFilter
    
    init(root: URL, filter: FileFilter) {
        self.root = root
        self.filter = filter
    }

    func browser(_ browser: NSBrowser, willDisplayCell cell: Any, atRow row: Int, column: Int) {
        if column == 0 && row == 0 {
            DispatchQueue.main.async {
                if browser.selectedRow(inColumn: 0) == -1 {
                    browser.selectRow(0, inColumn: 0)
                    (browser.target as? BrowserPickerVC)?.updateSelectionUI()
                }
            }
        }
    }
    
    func rootItem(for browser: NSBrowser) -> Any? { root as NSURL }
    
    func browser(_ browser: NSBrowser, numberOfChildrenOfItem item: Any?) -> Int {
        let base = (item as? URL) ?? root
        return listChildren(of: base).filter { u in
            let d = isDirectory(u)
            return filter.isAllowed(url: u, isDirectory: d)
        }.count
    }

    func browser(_ browser: NSBrowser, child index: Int, ofItem item: Any?) -> Any {
        let base = (item as? URL) ?? root
        let list = listChildren(of: base).filter { u in
            let d = isDirectory(u)
            return filter.isAllowed(url: u, isDirectory: d)
        }.sorted {
            let ad = isDirectory($0) ? 0 : 1
            let bd = isDirectory($1) ? 0 : 1
            if ad != bd { return ad < bd }
            return $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
        return list[index] as NSURL
    }

    func browser(_ browser: NSBrowser, isLeafItem item: Any?) -> Bool {
        let url = (item as? URL) ?? root
        return !isDirectory(url)
    }

    func browser(_ browser: NSBrowser, objectValueForItem item: Any?) -> Any? {
        (item as? URL)?.lastPathComponent
    }
}

// MARK: - Wrapper VC for browser + preview split
final class BrowserPickerVC: NSViewController {
    let browser = NSBrowser()
    let delegateObj: BrowserDelegate
    let onChoose: (URL) -> Void
    let chooseButton = NSButton(title: "Choose", target: nil, action: nil)
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)

    let splitView = NSSplitView()
    let preview = PreviewPane()

    init(root: URL, filter: FileFilter, onChoose: @escaping (URL) -> Void) {
        self.delegateObj = BrowserDelegate(root: root, filter: filter)
        self.onChoose = onChoose
        super.init(nibName: nil, bundle: nil)

        // Browser setup
        browser.delegate = delegateObj
        browser.takesTitleFromPreviousColumn = true
        browser.minColumnWidth = 220
        browser.separatesColumns = true
        browser.target = self
        browser.action = #selector(selectionChanged)
        browser.allowsMultipleSelection = false
        browser.allowsEmptySelection = false
        // Enable horizontal scrolling when columns exceed available width
        browser.hasHorizontalScroller = true

        // Buttons
        chooseButton.target = self
        chooseButton.action = #selector(chooseAction)
        chooseButton.isEnabled = false
        cancelButton.target = self
        cancelButton.action = #selector(cancelAction)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView()

        // Configure split view
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false

        // Left: browser (NSBrowser has built-in scrolling)
        let browserContainer = NSView()
        browserContainer.translatesAutoresizingMaskIntoConstraints = false
        
        browser.translatesAutoresizingMaskIntoConstraints = false
        browserContainer.addSubview(browser)
        
        NSLayoutConstraint.activate([
            browser.leadingAnchor.constraint(equalTo: browserContainer.leadingAnchor),
            browser.trailingAnchor.constraint(equalTo: browserContainer.trailingAnchor),
            browser.topAnchor.constraint(equalTo: browserContainer.topAnchor),
            browser.bottomAnchor.constraint(equalTo: browserContainer.bottomAnchor),
        ])

        // Right: preview
        let previewContainer = NSView()
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        preview.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(preview)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            preview.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            preview.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
        ])

        // Add subviews to split view
        splitView.addArrangedSubview(browserContainer)
        splitView.addArrangedSubview(previewContainer)

        // Buttons row
        chooseButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        // Root layout
        view.addSubview(splitView)
        view.addSubview(chooseButton)
        view.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: view.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: chooseButton.topAnchor, constant: -12),

            cancelButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            cancelButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),

            chooseButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -12),
            chooseButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
        ])

        // Give the browser a sensible starting width
        browserContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        browser.reloadColumn(0)
        view.window?.makeFirstResponder(browser)
        // Set initial split: 0.67 / 0.33
        if splitView.subviews.count == 2 {
            let total = splitView.bounds.width
            splitView.setPosition(total * 0.67, ofDividerAt: 0)
        }
    }

    private func selectedURL() -> URL? {
        let col = browser.selectedColumn
        if col >= 0 {
            let row = browser.selectedRow(inColumn: col)
            if row >= 0 {
                if let u = browser.item(atRow: row, inColumn: col) as? URL { return u }
                if let nu = browser.item(atRow: row, inColumn: col) as? NSURL { return nu as URL }
            }
        }
        return nil
    }

    func updateSelectionUI() {
        let url = selectedURL()
        // Enable Choose only for files
        if let u = url, !isDirectory(u) {
            chooseButton.isEnabled = true
        } else {
            chooseButton.isEnabled = false
        }
        // Update preview
        preview.show(url: url)
    }

    @objc private func selectionChanged() {
        updateSelectionUI()
    }

    @objc private func chooseAction() {
        if let url = selectedURL(), !isDirectory(url) {
            onChoose(url)
        }
    }

    @objc private func cancelAction() {
        view.window?.close()
        exitCancel()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { // Return
            if let url = selectedURL(), !isDirectory(url) {
                onChoose(url); return
            }
        }
        super.keyDown(with: event)
    }
}

// MARK: - Window Helper
func presentController(_ vc: NSViewController, title: String) {
    let w = NSWindow(contentViewController: vc)
    w.styleMask = [.titled, .closable, .resizable]
    w.setContentSize(NSSize(width: 900, height: 600)) // Wider to make room for preview
    w.title = title
    w.center()
    w.isReleasedWhenClosed = false
    class WindowCloseDelegate: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) {
            exitCancel()
        }
    }
    let closeDelegate = WindowCloseDelegate()
    w.delegate = closeDelegate
    let wc = NSWindowController(window: w)
    __windowControllers.append(wc) // retain
    wc.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
}

// MARK: - Main
let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)

let filter = FileFilter(allowedExts: Set(["txt", "md", "text", "mdown", "mkd", "markdown", "mkdn", "mdwn"]))

let vc = BrowserPickerVC(root: URL(fileURLWithPath: rootPath), filter: filter) { url in
    exitSuccess(with: url)
}
presentController(vc, title: "Choose Template")

app.run() // keep event loop alive
