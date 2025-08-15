#!/usr/bin/env swift
import AppKit
import Foundation

// Root directory comes from argv or defaults to CWD
let rootPath = (CommandLine.arguments.count > 1)
  ? CommandLine.arguments[1]
  : FileManager.default.currentDirectoryPath


// Keep windows/controllers alive for the life of the process
var __windowControllers: [NSWindowController] = []


// MARK: - Allowed Types / Filtering -------------------------------------------

struct FileFilter {
    let allowedExts: Set<String>
    
    func isAllowed(url: URL, isDirectory: Bool) -> Bool {
        // Always show directories to allow drilling
        if isDirectory {
            if url.lastPathComponent.hasPrefix(".") { return false }
            return true
        }
        if url.lastPathComponent.hasPrefix(".") { return false }
        
        // Prefer UTType check, fall back to extension
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty && allowedExts.contains(ext) { return true }
        return false
    }
}

// MARK: - Utilities ------------------------------------------------------------

func listChildren(of dir: URL) -> [URL] {
    let opts: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
    return (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .contentTypeKey, .isHiddenKey], options: opts)) ?? []
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

// MARK: - MODE 3: NSBrowser (Columns) -----------------------------------------

final class BrowserDelegate: NSObject, NSBrowserDelegate {
    func browser(_ browser: NSBrowser, willDisplayCell cell: Any, atRow row: Int, column: Int) {
        if column == 0 && row == 0 {
            DispatchQueue.main.async {
                // Only select the first row if nothing is selected in the first column
                if browser.selectedRow(inColumn: 0) == -1 {
                    browser.selectRow(0, inColumn: 0)
                    (browser.target as? BrowserPickerVC)?.updateChooseButton()
                }
            }
        }
    }
    let root: URL
    let filter: FileFilter
    
    init(root: URL, filter: FileFilter) {
        self.root = root
               self.filter = filter
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

// Wrapper VC for browser
final class BrowserPickerVC: NSViewController {
    let browser = NSBrowser()
    let delegateObj: BrowserDelegate
    let onChoose: (URL) -> Void
    let chooseButton = NSButton(title: "Choose", target: nil, action: nil)
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)

    init(root: URL, filter: FileFilter, onChoose: @escaping (URL) -> Void) {
        self.delegateObj = BrowserDelegate(root: root, filter: filter)
        self.onChoose = onChoose
        super.init(nibName: nil, bundle: nil)
        browser.delegate = delegateObj
        browser.takesTitleFromPreviousColumn = true
        browser.minColumnWidth = 220
        browser.separatesColumns = true
        browser.target = self
        browser.action = #selector(selectionChanged)
        chooseButton.target = self
        chooseButton.action = #selector(chooseAction)
        chooseButton.isEnabled = false
        cancelButton.target = self
        cancelButton.action = #selector(cancelAction)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView()
        browser.translatesAutoresizingMaskIntoConstraints = false
        chooseButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(browser)
        view.addSubview(chooseButton)
        view.addSubview(cancelButton)
        NSLayoutConstraint.activate([
            browser.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            browser.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            browser.topAnchor.constraint(equalTo: view.topAnchor),
            browser.bottomAnchor.constraint(equalTo: chooseButton.topAnchor, constant: -12),
            cancelButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            cancelButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            chooseButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -12),
            chooseButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])
    }
    override func viewDidAppear() {
        super.viewDidAppear()
        browser.reloadColumn(0)
        view.window?.makeFirstResponder(browser)
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
    func updateChooseButton() {
        if let url = selectedURL(), !isDirectory(url) {
            chooseButton.isEnabled = true
        } else {
            chooseButton.isEnabled = false
        }
    }
    @objc private func selectionChanged() {
        updateChooseButton()
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


} // End of BrowserPickerVC class

// MARK: - Window Helper --------------------------------------------------------
func presentController(_ vc: NSViewController, title: String) {
    let w = NSWindow(contentViewController: vc)
    w.styleMask = [.titled, .closable, .resizable]
    w.setContentSize(NSSize(width: 720, height: 480))
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

// MARK: - Main -----------------------------------------------------------------
let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)

let filter = FileFilter(allowedExts: Set(["txt", "md", "text", "mdown", "mkd", "markdown", "mdown", "mkdn", "mdwn"]))

let vc = BrowserPickerVC(root: URL(fileURLWithPath: rootPath), filter: filter) { url in exitSuccess(with: url) }
presentController(vc, title: "Choose Template")

app.run() // keep event loop alive
