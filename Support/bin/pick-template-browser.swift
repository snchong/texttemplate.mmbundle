#!/usr/bin/env swift
import AppKit
import Foundation
import QuickLookUI

// MARK: - Feature flags / platform checks
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

// MARK: - File Filtering
struct FileFilter {
    /// Allowed filename extensions (lowercased, without the dot)
    let allowedExts: Set<String>

    /// Returns true if the URL should be visible in the browser.
    func isAllowed(url: URL, isDirectory: Bool) -> Bool {
        if isDirectory {
            return !url.lastPathComponent.hasPrefix(".")
        }
        guard !url.lastPathComponent.hasPrefix(".") else { return false }

        #if canImport(UniformTypeIdentifiers)
        if #available(macOS 11.0, *) {
            if let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType {
                if let markdownType = UTType(filenameExtension: "md") {
                    if type.conforms(to: .plainText) || type.conforms(to: markdownType) {
                        return true
                    }
                } else if type.conforms(to: .plainText) {
                    return true
                }
            }
        }
        #endif
        let ext = url.pathExtension.lowercased()
        return !ext.isEmpty && allowedExts.contains(ext)
    }
}


// MARK: - URL helpers
private extension URL {
    var isDirectoryURL: Bool { ((try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory) ?? false }
}

// MARK: - Filesystem utilities
final class DirectoryLister {
    private let fm = FileManager.default
    private let keys: [URLResourceKey] = [.isDirectoryKey, .contentTypeKey, .isHiddenKey]
    private let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]

    /// Simple in-memory cache to avoid repeated enumeration for the same directory
    private var cache: [URL: [URL]] = [:]

    func children(of directory: URL) -> [URL] {
        if let cached = cache[directory] { return cached }
        let urls = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: options)) ?? []
        cache[directory] = urls
        return urls
    }
}

// MARK: - Process exit helpers
@inline(__always)
func exitSuccess(with url: URL) -> Never {
    print(url.path)
    fflush(stdout)
    exit(0)
}

@inline(__always)
func exitCancel() -> Never { exit(1) }

// MARK: - Quick Look Preview Item
@available(macOS 10.15, *)
final class PreviewItem: NSObject, QLPreviewItem {
    private let _url: URL
    init(_ url: URL) { self._url = url }
    var previewItemURL: URL? { _url }
}

// MARK: - Preview Pane
final class PreviewPane: NSView {
    private let placeholderLabel = NSTextField(labelWithString: "Select a file to preview")
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private var qlView: QLPreviewView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        placeholderLabel.alignment = .center
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.font = .systemFont(ofSize: 14)
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.usesFontPanel = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
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

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Show a preview for the URL; if nil or directory, clear preview.
    func show(url: URL?) {
        guard let url = url, !url.isDirectoryURL else {
            removeQLViewIfNeeded()
            textView.string = ""
            scrollView.isHidden = true
            placeholderLabel.isHidden = false
            return
        }

        if #available(macOS 10.15, *) {
            if qlView == nil {
                qlView = QLPreviewView(frame: bounds, style: .normal)
                qlView?.autoresizingMask = [.width, .height]
                if let ql = qlView { addSubview(ql, positioned: .below, relativeTo: placeholderLabel) }
            }
            if let ql = qlView {
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
        qlView?.removeFromSuperview()
        qlView = nil
    }
}

// MARK: - NSBrowser Data Source / Delegate
final class BrowserDelegate: NSObject, NSBrowserDelegate {
    private let root: URL
    private let filter: FileFilter
    private let lister: DirectoryLister

    init(root: URL, filter: FileFilter, lister: DirectoryLister) {
        self.root = root
        self.filter = filter
        self.lister = lister
    }

    func rootItem(for browser: NSBrowser) -> Any? { root as NSURL }

    func browser(_ browser: NSBrowser, numberOfChildrenOfItem item: Any?) -> Int {
        let base = (item as? URL) ?? root
        return lister.children(of: base).filter { filter.isAllowed(url: $0, isDirectory: $0.isDirectoryURL) }.count
    }

    func browser(_ browser: NSBrowser, child index: Int, ofItem item: Any?) -> Any {
        let base = (item as? URL) ?? root
        let list = lister.children(of: base)
            .filter { filter.isAllowed(url: $0, isDirectory: $0.isDirectoryURL) }
            .sorted { a, b in
                let ad = a.isDirectoryURL ? 0 : 1
                let bd = b.isDirectoryURL ? 0 : 1
                if ad != bd { return ad < bd }
                return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
            }
        return list[index] as NSURL
    }

    func browser(_ browser: NSBrowser, isLeafItem item: Any?) -> Bool {
        let url = (item as? URL) ?? root
        return !url.isDirectoryURL
    }

    func browser(_ browser: NSBrowser, objectValueForItem item: Any?) -> Any? {
        (item as? URL)?.lastPathComponent
    }

    func browser(_ browser: NSBrowser, willDisplayCell cell: Any, atRow row: Int, column: Int) {
        // Select the first row in the first column on first display
        if column == 0 && row == 0 {
            DispatchQueue.main.async {
                if browser.selectedRow(inColumn: 0) == -1 {
                    browser.selectRow(0, inColumn: 0)
                    (browser.target as? BrowserPickerVC)?.updateSelectionUI()
                }
            }
        }
    }
}

// MARK: - View Controller: Browser + Preview + Buttons
final class BrowserPickerVC: NSViewController {
    private let browser = NSBrowser()
    private let delegateObj: BrowserDelegate
    private let onChoose: (URL) -> Void
    private let chooseButton = NSButton(title: "Choose", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let splitView = NSSplitView()
    private let preview = PreviewPane()

    init(root: URL, filter: FileFilter, lister: DirectoryLister, onChoose: @escaping (URL) -> Void) {
        self.delegateObj = BrowserDelegate(root: root, filter: filter, lister: lister)
        self.onChoose = onChoose
        super.init(nibName: nil, bundle: nil)

        browser.delegate = delegateObj
        browser.takesTitleFromPreviousColumn = true
        browser.minColumnWidth = 220
        browser.separatesColumns = true
        browser.target = self
        browser.action = #selector(selectionChanged)
        browser.allowsMultipleSelection = false
        browser.allowsEmptySelection = false
        browser.hasHorizontalScroller = true

        chooseButton.target = self
        chooseButton.action = #selector(chooseAction)
        chooseButton.isEnabled = false

        cancelButton.target = self
        cancelButton.action = #selector(cancelAction)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView()

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false

        let browserContainer = NSView()
        browserContainer.translatesAutoresizingMaskIntoConstraints = false
        browser.translatesAutoresizingMaskIntoConstraints = false
        browserContainer.addSubview(browser)
        NSLayoutConstraint.activate([
            browser.leadingAnchor.constraint(equalTo: browserContainer.leadingAnchor),
            browser.trailingAnchor.constraint(equalTo: browserContainer.trailingAnchor),
            browser.topAnchor.constraint(equalTo: browserContainer.topAnchor),
            browser.bottomAnchor.constraint(equalTo: browserContainer.bottomAnchor)
        ])

        let previewContainer = NSView()
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        preview.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(preview)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            preview.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            preview.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor)
        ])

        splitView.addArrangedSubview(browserContainer)
        splitView.addArrangedSubview(previewContainer)

        chooseButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

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
            chooseButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])

        browserContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        browser.reloadColumn(0)
        view.window?.makeFirstResponder(browser)
        if splitView.subviews.count == 2 {
            let total = splitView.bounds.width
            splitView.setPosition(total * 0.67, ofDividerAt: 0)
        }
    }

    func updateSelectionUI() {
        let url = selectedURL()
        chooseButton.isEnabled = (url?.isDirectoryURL == false)
        preview.show(url: url)
    }

    private func selectedURL() -> URL? {
        let col = browser.selectedColumn
        guard col >= 0 else { return nil }
        let row = browser.selectedRow(inColumn: col)
        guard row >= 0 else { return nil }
        if let u = browser.item(atRow: row, inColumn: col) as? URL { return u }
        if let nu = browser.item(atRow: row, inColumn: col) as? NSURL { return nu as URL }
        return nil
    }

    @objc private func selectionChanged() { updateSelectionUI() }

    @objc private func chooseAction() {
        if let url = selectedURL(), !url.isDirectoryURL { onChoose(url) }
    }

    @objc private func cancelAction() {
        view.window?.close()
        exitCancel()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36: // Return
            if let url = selectedURL(), !url.isDirectoryURL { onChoose(url); return }
        default: break
        }
        super.keyDown(with: event)
    }
}

// MARK: - Window / App plumbing
final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) { exitCancel() }
}

final class AppController {
    private let app = NSApplication.shared
    private var windowControllers: [NSWindowController] = [] // Keep strong refs
    private var windowDelegates: [WindowCloseDelegate] = []  // Keep strong refs (NSWindow keeps weak delegate)

    func run(rootPath: String) {
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)

        let lister = DirectoryLister()
        let filter = FileFilter(allowedExts: ["txt", "md", "text", "mdown", "mkd", "markdown", "mkdn", "mdwn"])

        let rootURL = URL(fileURLWithPath: rootPath)
        let vc = BrowserPickerVC(root: rootURL, filter: filter, lister: lister) { url in
            exitSuccess(with: url)
        }
        presentController(vc, title: "Choose Template")
        app.run()
    }

    private func presentController(_ vc: NSViewController, title: String) {
        let window = NSWindow(contentViewController: vc)
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 900, height: 600))
        window.title = title
        window.center()
        window.isReleasedWhenClosed = false

        let closeDelegate = WindowCloseDelegate()
        window.delegate = closeDelegate
        windowDelegates.append(closeDelegate) // retain delegate strongly

        let wc = NSWindowController(window: window)
        windowControllers.append(wc) // retain window controller strongly
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Entry point (script-friendly)
let rootPath: String = {
    if CommandLine.arguments.count > 1 { return CommandLine.arguments[1] }
    return FileManager.default.currentDirectoryPath
}()

AppController().run(rootPath: rootPath)
