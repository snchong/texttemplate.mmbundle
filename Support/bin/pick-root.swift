#!/usr/bin/env swift
import AppKit
import Foundation

// Root directory comes from argv or defaults to CWD
let rootPath = (CommandLine.arguments.count > 1)
  ? CommandLine.arguments[1]
  : FileManager.default.currentDirectoryPath

let app = NSApplication.shared
app.setActivationPolicy(.accessory)           // don't show a Dock icon
app.activate(ignoringOtherApps: true)         // bring panel to front

DispatchQueue.main.async {
  let panel = NSOpenPanel()
  panel.directoryURL = URL(fileURLWithPath: rootPath, isDirectory: true)
  panel.canChooseFiles = false
  panel.canChooseDirectories = true
  panel.canCreateDirectories = true
  panel.allowsMultipleSelection = false
  panel.title = "Choose a root directory for templates"
  panel.prompt = "Choose root directory"
  panel.resolvesAliases = true
  panel.showsHiddenFiles = false

  panel.begin { resp in
    if resp == .OK, let url = panel.url {
      print(url.path)
      fflush(stdout)
      exit(0)                                  // return success
    } else {
      exit(1)                                  // return non-zero on cancel
    }
  }
}

app.run()                                      // keep the event loop alive
