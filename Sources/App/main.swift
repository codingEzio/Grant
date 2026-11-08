import AppKit
import Combine
import Security
import SwiftUI

let grantPreferencesChanged = Notification.Name("com.alex.Grant.preferences-changed")
let grantPreferenceResult = Notification.Name("com.alex.Grant.preference-result")
func grantSettingsURL() -> URL {
  let args = CommandLine.arguments
  if let index = args.firstIndex(of: "--state-dir"), args.indices.contains(index + 1) {
    return URL(fileURLWithPath: args[index + 1]).appendingPathComponent("settings.json")
  }
  let shared = URL(fileURLWithPath: "/Library/Application Support/Grant/Preferences")
  if FileManager.default.fileExists(atPath: shared.path) {
    return shared.appendingPathComponent("settings.json")
  }
  return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
    "Library/Application Support/Grant/settings.json")
}
func grantSystemActive() -> Bool? {
  var definition: CFDictionary?
  guard AuthorizationRightGet("authenticate", &definition) == errAuthorizationSuccess,
    let rule = definition as? [String: Any]
  else { return nil }
  return (rule["mechanisms"] as? [String])?.first == "Grant:credentials"
}

func grantPluginVersion() -> String? {
  Bundle(path: "/Library/Security/SecurityAgentPlugins/Grant.bundle")?
    .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
}
func grantSystemNeedsUpdate() -> Bool {
  grantSystemActive() == true && grantPluginVersion() !=
    (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
}

struct GrantSettings: Codable, Equatable {
  var schemaVersion = 1
  var style = "paper"
  var appearance = "system"
  var typography = "theme"
  var terminalSudo = true
  var language = "zh-Hans"
  var fontOverrides: [String: [String]] = [:]
  var appearanceFontOverrides: [String: [String: [String]]] = [:]
  init() {}
  enum CodingKeys: String, CodingKey {
    case schemaVersion, style, appearance, typography, terminalSudo, language, fontOverrides,
      appearanceFontOverrides
  }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
    style = try values.decode(String.self, forKey: .style)
    appearance = try values.decode(String.self, forKey: .appearance)
    typography = try values.decode(String.self, forKey: .typography)
    terminalSudo = try values.decodeIfPresent(Bool.self, forKey: .terminalSudo) ?? true
    language = try values.decode(String.self, forKey: .language)
    fontOverrides =
      try values.decodeIfPresent([String: [String]].self, forKey: .fontOverrides) ?? [:]
    appearanceFontOverrides =
      try values.decodeIfPresent(
        [String: [String: [String]]].self, forKey: .appearanceFontOverrides) ?? [:]
  }
  var dictionary: [String: Any] {
    [
      "schemaVersion": schemaVersion, "style": style, "appearance": appearance,
      "typography": typography, "terminalSudo": terminalSudo, "language": language,
      "fontOverrides": fontOverrides,
      "appearanceFontOverrides": appearanceFontOverrides,
    ]
  }
}

@MainActor final class PreviewStore: ObservableObject {
  @Published var settings = GrantSettings()
  @Published var error: String?
  private var url: URL
  private var persistedSettings: GrantSettings?
  init() {
    if let defaults = GRGrantView.defaultSettings(),
      let data = try? JSONSerialization.data(withJSONObject: defaults),
      let decoded = try? JSONDecoder().decode(GrantSettings.self, from: data)
    {
      settings = decoded
    }
    url = grantSettingsURL()
    if FileManager.default.fileExists(atPath: url.path) {
      do {
        let originalData = try Data(contentsOf: url)
        var read = try JSONDecoder().decode(GrantSettings.self, from: originalData)
        let oldJSON = try JSONSerialization.jsonObject(with: originalData) as? [String: Any]
        let migrate =
          read.style == "nothing" || read.style == "module" || read.typography == "dots"
          || oldJSON?["fontOverrides"] == nil || oldJSON?["appearanceFontOverrides"] == nil || oldJSON?["terminalSudo"] == nil
        if read.style == "nothing" { read.style = "paper" }
        if read.style == "module" { read.style = "dot" }
        for (legacy, current) in [("nothing", "paper"), ("module", "dot")] {
          if read.fontOverrides[current] == nil {
            read.fontOverrides[current] = read.fontOverrides[legacy]
          }
          if read.appearanceFontOverrides[current] == nil {
            read.appearanceFontOverrides[current] = read.appearanceFontOverrides[legacy]
          }
        }
        if read.typography == "dots" { read.typography = "theme" }
        let view = GRGrantView(frame: .zero)
        guard view.apply(settings: read.dictionary, preview: true) else {
          throw NSError(
            domain: "Grant", code: 1,
            userInfo: [
              NSLocalizedDescriptionKey:
                text("invalidSavedPreferences")
            ])
        }
        settings = read
        persistedSettings = migrate ? nil : read
        if migrate {
          let backup = url.deletingLastPathComponent().appendingPathComponent(
            "settings.before-selected-themes.json")
          if !FileManager.default.fileExists(atPath: backup.path) {
            try originalData.write(to: backup, options: .atomic)
          }
          save()
        }
      } catch { self.error = error.localizedDescription }
    }
  }
  var strings: [String: String] {
    GRGrantView.strings(language: settings.language) as? [String: String] ?? [:]
  }
  func text(_ key: String) -> String { strings[key] ?? key }
  func reloadPreferences() {
    objectWillChange.send() // Refresh live system-policy status even if appearance is unchanged.
    url = grantSettingsURL()
    do {
      let read = try JSONDecoder().decode(GrantSettings.self, from: Data(contentsOf: url))
      guard GRGrantView(frame: .zero).apply(settings: read.dictionary, preview: true) else {
        throw NSError(domain: "Grant", code: 1)
      }
      error = nil
      persistedSettings = read
      if read != settings { settings = read }
    } catch { self.error = text("invalidSavedPreferences") }
  }
  func styleName(_ style: String) -> String {
    let keys = [
      "paper": "stylePaper", "nothing": "stylePaper", "dot": "styleDot",
      "module": "styleDot", "swiss": "styleSwiss", "hard-edge": "styleHardEdge",
      "blueprint": "styleBlueprint", "original": "styleOriginal",
    ]
    return text(keys[style] ?? "stylePaper")
  }
  var originalAvailable: Bool {
    grantSystemActive() != true || (grantPluginVersion() ?? "0").compare("0.2.3", options: .numeric) != .orderedAscending
  }
  @discardableResult func save() -> Bool {
    guard settings.style != "original" || originalAvailable else {
      error = text("originalUpdateNeeded"); return false
    }
    guard error == nil else { return false }
    if persistedSettings == settings { return true }
    url = grantSettingsURL()
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(settings).write(to: url, options: .atomic)
      // Cosmetic preferences must be readable by the unprivileged SecurityAgent.
      try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
      let readback = try JSONDecoder().decode(GrantSettings.self, from: Data(contentsOf: url))
      guard readback == settings else { throw NSError(domain: "Grant", code: 2) }
      persistedSettings = readback
      DistributedNotificationCenter.default().postNotificationName(
        grantPreferencesChanged, object: nil, userInfo: nil, deliverImmediately: true)
      return true
    } catch { self.error = error.localizedDescription; return false }
  }
  func selectAppearance(_ key: String, value: String) -> Bool {
    let allowed = [
      "style": ["paper", "dot", "swiss", "hard-edge", "blueprint", "original"],
      "appearance": ["system", "light", "dark"], "typography": ["theme", "system"],
      "language": ["en", "zh-Hans", "zh-Hant"],
    ]
    guard allowed[key]?.contains(value) == true else { return false }
    guard key != "style" || value != "original" || originalAvailable else { error = text("originalUpdateNeeded"); return false }
    // Re-read before merging so a menu cannot replace more recent font stacks.
    if FileManager.default.fileExists(atPath: url.path) { reloadPreferences() }
    guard error == nil else { return false }
    var candidate = settings.dictionary
    candidate[key] = value
    guard GRGrantView(frame: .zero).apply(settings: candidate, preview: true),
      let data = try? JSONSerialization.data(withJSONObject: candidate),
      let decoded = try? JSONDecoder().decode(GrantSettings.self, from: data)
    else { return false }
    settings = decoded
    return save()
  }
}

struct CredentialPreview: NSViewRepresentable {
  var settings: GrantSettings
  @ObservedObject var store: PreviewStore
  func makeNSView(context: Context) -> GRGrantView {
    let view = GRGrantView(frame: .zero)
    view.appearanceChangeRequested = { [weak store = store] key, value in
      guard let key, let value else { return }
      _ = store?.selectAppearance(key, value: value)
    }
    view.settingsRequested = { section in
      let delegate = NSApp.delegate as? GrantAppDelegate
      if section == "fonts" { delegate?.showFontSettings(style: store.settings.style) }
      else { delegate?.showPreviewSettings() }
    }
    return view
  }
  func updateNSView(_ view: GRGrantView, context: Context) {
    view.showsActions = true
    view.credentialsOnly = true
    if !view.apply(settings: settings.dictionary, preview: true) {
      view.showError(
        (GRGrantView.strings(language: settings.language)?["styleError"] as? String)
          ?? "Grant style could not be loaded.")
    }
  }
}

struct GrantPanel: View {
  @ObservedObject var store: PreviewStore
  @Environment(\.colorScheme) private var colorScheme
  private var effectiveSettings: GrantSettings {
    var selected = store.settings
    if selected.appearance == "system" {
      selected.appearance = colorScheme == .dark ? "dark" : "light"
    }
    return selected
  }
  private var cardSize: NSSize {
    GRGrantView.size(style: store.settings.style, showsActions: true, credentialsOnly: true)
  }
  var body: some View {
    VStack(spacing: 6) {
      CredentialPreview(settings: effectiveSettings, store: store)
        .frame(width: cardSize.width, height: cardSize.height)
      HStack {
        Text(store.text("preview")).font(.system(size: 9)).foregroundStyle(.secondary)
        Spacer(minLength: 8)
      }.padding(.horizontal, 8).frame(height: 18)
      if let error = store.error {
        Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
      }
    }
    .padding(8).frame(width: cardSize.width + 16)
    .onChange(of: store.settings) { _, _ in store.save() }
  }
}

struct PreviewSettingsPanel: View {
  @ObservedObject var store: PreviewStore
  let onDone: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Form {
        Picker(store.text("style"), selection: $store.settings.style) {
          Text(store.text("stylePaper")).tag("paper")
          Text(store.text("styleDot")).tag("dot")
          Text(store.text("styleSwiss")).tag("swiss")
          Text(store.text("styleHardEdge")).tag("hard-edge")
          Text(store.text("styleBlueprint")).tag("blueprint")
          Text(store.text("styleOriginal")).tag("original").disabled(!store.originalAvailable)
        }.accessibilityIdentifier("grant.style")
        Picker(store.text("appearance"), selection: $store.settings.appearance) {
          Text(store.text("system")).tag("system")
          Text(store.text("light")).tag("light")
          Text(store.text("dark")).tag("dark")
        }.accessibilityIdentifier("grant.appearance")
        Picker(store.text("language"), selection: $store.settings.language) {
          Text("简体中文").tag("zh-Hans")
          Text("繁體中文").tag("zh-Hant")
          Text("English").tag("en")
        }.accessibilityIdentifier("grant.language")
        Picker(store.text("typography"), selection: $store.settings.typography) {
          Text(store.text("themeFonts")).tag("theme")
          Text(store.text("system")).tag("system")
        }.accessibilityIdentifier("grant.typography")
      }
      Toggle(store.text("terminalSudo"), isOn: $store.settings.terminalSudo)
        .accessibilityIdentifier("grant.terminalSudo")
      Text(store.text("terminalSudoHint")).font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Button(store.text("fontSettings")) {
        (NSApp.delegate as? GrantAppDelegate)?.showFontSettings(style: store.settings.style)
      }.accessibilityIdentifier("grant.fontSettings")
      Divider()
      Button(store.text("openOriginal")) {
        let original = Bundle.main.resourceURL!.appendingPathComponent(
          "Original/GrantSetupReference.app")
        if !NSWorkspace.shared.open(original) { store.error = store.text("originalMissing") }
      }.accessibilityIdentifier("grant.original")
      Text(store.text("originalRouteNote"))
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      Button(store.text("openGuide")) {
        let name =
          store.settings.language == "en" ? "INTEGRATION" : "INTEGRATION.\(store.settings.language)"
        if let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "Guides")
        {
          NSWorkspace.shared.open(url)
        }
      }.accessibilityIdentifier("grant.guide")
      Text(
        store.text(
          grantSystemNeedsUpdate() ? "systemUpdateAvailable" : grantSystemActive() == true
            ? "systemEnabled" : grantSystemActive() == false ? "notActive" : "systemUnknown")
      )
      .font(.caption).foregroundStyle(.secondary)
      if grantSystemActive() != true || grantSystemNeedsUpdate() {
        Button(store.text(grantSystemNeedsUpdate() ? "systemUpdate" : "systemSetup")) {
          if let url = Bundle.main.url(forResource: "GrantSystemSetup", withExtension: "command") {
            NSWorkspace.shared.open(url)
          }
        }.accessibilityIdentifier("grant.systemSetup")
      } else {
        Button(store.text("systemRestore")) {
          if let url = Bundle.main.url(forResource: "GrantSystemRestore", withExtension: "command")
          {
            NSWorkspace.shared.open(url)
          }
        }.accessibilityIdentifier("grant.systemRestore")
      }
      HStack {
        Text(store.text("version")).font(.system(size: 10, design: .monospaced)).foregroundStyle(
          .secondary)
        Spacer()
        Button(store.text("done")) { onDone() }.keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("grant.settings.done")
      }
    }.padding(20).frame(width: 370)
  }
}

struct FontSettingsPanel: View {
  @ObservedObject var store: PreviewStore
  let style: String
  let onDone: () -> Void
  @State private var preferred = ""
  @State private var fallbacks = ""
  @State private var validationError: String?
  @State private var fontAppearance = "both"
  private var report: [String: Any] {
    var selected = store.settings
    selected.style = style
    selected.appearance = fontAppearance == "both" ? "light" : fontAppearance
    if fontAppearance == "both" { selected.appearanceFontOverrides.removeValue(forKey: style) }
    return GRGrantView.fontReport(settings: selected.dictionary) as? [String: Any] ?? [:]
  }
  private func load() {
    let names = report["configured"] as? [String] ?? []
    preferred = names.first ?? ""
    fallbacks = names.dropFirst().joined(separator: "\n")
  }
  private func apply() {
    let names = ([preferred] + fallbacks.components(separatedBy: .newlines))
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    var candidate = store.settings
    if fontAppearance == "both" {
      candidate.fontOverrides[style] = names
    } else {
      candidate.appearanceFontOverrides[style, default: [:]][fontAppearance] = names
    }
    var validation = candidate
    validation.style = style
    validation.appearance = fontAppearance == "both" ? "light" : fontAppearance
    if fontAppearance == "both" { validation.appearanceFontOverrides.removeValue(forKey: style) }
    let candidateReport =
      GRGrantView.fontReport(settings: validation.dictionary) as? [String: Any] ?? ["error": true]
    guard candidateReport["error"] == nil else {
      validationError = store.text("fontConfigurationError")
      return
    }
    validationError = nil
    store.settings = candidate
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("\(store.styleName(style)) · \(store.text("typography"))")
        .font(.title2.weight(.semibold))
      Picker(store.text("fontScope"), selection: $fontAppearance) {
        Text(store.text("allAppearances")).tag("both")
        Text(store.text("light")).tag("light")
        Text(store.text("dark")).tag("dark")
      }.pickerStyle(.segmented).accessibilityIdentifier("grant.font.appearance")
      if fontAppearance != "both",
        store.settings.appearanceFontOverrides[style]?[fontAppearance] == nil
      {
        Text(store.text("inheritAppearanceFonts")).font(.caption).foregroundStyle(.secondary)
      }
      Text(store.text("fontHelp")).font(.caption).foregroundStyle(.secondary).fixedSize(
        horizontal: false, vertical: true)
      Text(store.text("preferredFont")).font(.caption).foregroundStyle(.secondary)
      TextField(store.text("preferredFont"), text: $preferred)
        .textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
        .accessibilityIdentifier("grant.font.preferred")
      Text(store.text("fallbackFonts")).font(.caption).foregroundStyle(.secondary)
      TextEditor(text: $fallbacks).font(.system(size: 12, design: .monospaced))
        .frame(height: 100).border(.separator).accessibilityIdentifier("grant.font.fallbacks")
      VStack(alignment: .leading, spacing: 5) {
        ForEach(
          Array((report["availability"] as? [[String: Any]] ?? []).enumerated()), id: \.offset
        ) { _, font in
          HStack {
            Text(font["name"] as? String ?? "").font(.system(size: 10.5, design: .monospaced))
            Spacer()
            Text(store.text((font["available"] as? Bool == true) ? "fontAvailable" : "fontMissing"))
              .font(.caption).foregroundStyle(
                (font["available"] as? Bool == true) ? Color.secondary : Color.orange)
          }
        }
      }
      Text(store.text("actualFonts")).font(.caption.weight(.semibold))
      let providers = (report["runs"] as? [[String: Any]] ?? []).compactMap {
        $0["font"] as? String
      }
      Text(
        providers.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(
          separator: " · ")
      )
      .font(.system(size: 10.5, design: .monospaced)).fixedSize(horizontal: false, vertical: true)
      Text(store.text("fallbackAlways")).font(.caption).foregroundStyle(.secondary)
      if store.settings.typography == "system" {
        Text(store.text("fontModeSystemNote")).font(.caption).foregroundStyle(.secondary)
      }
      if let validationError { Text(validationError).font(.caption).foregroundStyle(.red) }
      HStack {
        Button(store.text("useThemeDefaults")) {
          if fontAppearance == "both" {
            store.settings.fontOverrides.removeValue(forKey: style)
          } else {
            store.settings.appearanceFontOverrides[style]?.removeValue(forKey: fontAppearance)
          }
          validationError = nil
          load()
        }
        Spacer()
        Button(store.text("apply")) { apply() }.accessibilityIdentifier("grant.font.apply")
        Button(store.text("done")) { onDone() }.keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("grant.font.done")
      }
    }.padding(24).frame(width: 600).onAppear { load() }
      .onChange(of: fontAppearance) { _, _ in
        validationError = nil
        load()
      }
  }
}

@MainActor final class GrantAppDelegate: NSObject, NSApplicationDelegate {
  var window: NSWindow?
  var store: PreviewStore?
  var appearanceSubscription: AnyCancellable?
  var settingsWindow: NSPanel?
  var fontWindow: NSPanel?
  var fontWindowStyle: String?
  var pendingURLs: [URL] = []
  var deferredSettingsSection: String?
  var helperIdleExit: DispatchWorkItem?
  private func scheduleHelperExit() {
    helperIdleExit?.cancel()
    guard window == nil, deferredSettingsSection == nil,
      CommandLine.arguments.contains("--settings-agent") else { return }
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.window == nil, self.deferredSettingsSection == nil,
        self.pendingURLs.isEmpty else { return }
      NSApp.terminate(nil)
    }
    helperIdleExit = work
    // One owner app, bounded idle lifetime; another URL cancels this exit.
    DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
  }
  private func presentSettingsSection(_ section: String) {
    if window == nil { showMainInterface() }
    NSApp.setActivationPolicy(.regular)
    if section == "fonts", let store { showFontSettings(style: store.settings.style) }
    else { showPreviewSettings() }
  }
  func applicationDidBecomeActive(_ notification: Notification) {
    if let section = deferredSettingsSection {
      deferredSettingsSection = nil
      presentSettingsSection(section)
    }
  }
  func application(_ application: NSApplication, open urls: [URL]) {
    helperIdleExit?.cancel()
    guard store != nil else {
      pendingURLs = Array((pendingURLs + urls).prefix(8))
      return
    }
    for url in urls.prefix(8) {
      guard url.scheme == "grant", url.user == nil, url.password == nil,
        url.port == nil, url.fragment == nil,
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { continue }
      if url.host == "appearance" {
        let path = url.pathComponents.filter { $0 != "/" }
        let requests = components.queryItems?.filter { $0.name == "request" } ?? []
        guard path.count == 2, requests.count == 1,
          components.queryItems?.count == 1, let request = requests[0].value,
          UUID(uuidString: request) != nil, let store
        else { continue }
        let saved = store.selectAppearance(path[0], value: path[1])
        DistributedNotificationCenter.default().postNotificationName(
          grantPreferenceResult, object: nil,
          userInfo: ["request": request, "saved": saved], deliverImmediately: true)
      } else if url.host == "settings",
        ["", "/", "/fonts"].contains(url.path) {
        let section = url.path == "/fonts" ? "fonts" : "all"
        if let query = components.queryItems {
          guard query.count == 1, query[0].name == "handoff",
            UUID(uuidString: query[0].value ?? "") != nil else { continue }
          // The host starts us without activation. It cancels its request before
          // activating us; only that later activation presents the settings UI.
          deferredSettingsSection = section
          NSApp.setActivationPolicy(.regular)
          if NSApp.isActive {
            deferredSettingsSection = nil
            presentSettingsSection(section)
          }
        } else {
          presentSettingsSection(section)
          NSApp.activate(ignoringOtherApps: true)
        }
      }
    }
    scheduleHelperExit()
  }
  @objc func preferencesChanged(_ notification: Notification) { store?.reloadPreferences() }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    store?.reloadPreferences()
    if window == nil { showMainInterface() }
    showPreviewSettings()
    return true
  }
  @objc func showPreviewSettings() {
    guard let store else { return }
    if let settingsWindow, settingsWindow.isVisible {
      settingsWindow.makeKeyAndOrderFront(nil)
      return
    }
    let panel = NSPanel(
      contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
    panel.title = store.text("settings")
    panel.identifier = NSUserInterfaceItemIdentifier("grant.settings.window")
    panel.isReleasedWhenClosed = false
    panel.isFloatingPanel = false
    panel.hidesOnDeactivate = false
    let content = NSHostingView(
      rootView: PreviewSettingsPanel(store: store, onDone: { [weak panel] in panel?.close() }))
    panel.contentView = content
    panel.setContentSize(content.fittingSize)
    panel.appearance = window?.appearance
    panel.center()
    panel.makeKeyAndOrderFront(nil)
    settingsWindow = panel
  }
  func showFontSettings(style: String) {
    guard let store else { return }
    if let fontWindow, fontWindow.isVisible, fontWindowStyle == style {
      fontWindow.makeKeyAndOrderFront(nil)
      return
    }
    fontWindow?.close()
    let panel = NSPanel(
      contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
    panel.title = "\(store.styleName(style)) · \(store.text("typography"))"
    panel.identifier = NSUserInterfaceItemIdentifier("grant.fonts")
    panel.isReleasedWhenClosed = false
    panel.isFloatingPanel = false
    panel.hidesOnDeactivate = false
    let view = NSHostingView(
      rootView: FontSettingsPanel(
        store: store, style: style, onDone: { [weak panel] in panel?.close() }))
    panel.contentView = view
    panel.setContentSize(view.fittingSize)
    panel.appearance = window?.appearance
    panel.center()
    panel.makeKeyAndOrderFront(nil)
    fontWindow = panel
    fontWindowStyle = style
  }
  func applicationDidFinishLaunching(_ notification: Notification) {
    self.store = PreviewStore()
    DistributedNotificationCenter.default().addObserver(
      self, selector: #selector(preferencesChanged(_:)), name: grantPreferencesChanged, object: nil)
    if !CommandLine.arguments.contains("--settings-agent") { showMainInterface() }
    let urls = pendingURLs; pendingURLs = []
    if !urls.isEmpty { application(NSApp, open: urls) }
  }
  func showMainInterface() {
    guard window == nil, let store else { return }
    let view = NSHostingView(rootView: GrantPanel(store: store))
    let size = view.fittingSize
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = store.text("previewWindowTitle")
    window.identifier = NSUserInterfaceItemIdentifier("grant.preview")
    window.contentView = view
    window.center()
    window.makeKeyAndOrderFront(nil)
    self.window = window
    NSApp.activate(ignoringOtherApps: true)
    let menu = NSMenu()
    let appItem = NSMenuItem()
    menu.addItem(appItem)
    let appMenu = NSMenu()
    appItem.submenu = appMenu
    let settingsItem = NSMenuItem(
      title: store.text("settings"), action: #selector(showPreviewSettings), keyEquivalent: ",")
    settingsItem.target = self
    appMenu.addItem(settingsItem)
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: "Quit Grant", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    NSApp.mainMenu = menu
    appearanceSubscription = store.$settings.sink { [weak window, weak self] settings in
      window?.appearance =
        settings.appearance == "system"
        ? nil : NSAppearance(named: settings.appearance == "dark" ? .darkAqua : .aqua)
      self?.fontWindow?.appearance = window?.appearance
      self?.settingsWindow?.appearance = window?.appearance
      let strings = GRGrantView.strings(language: settings.language) as? [String: String] ?? [:]
      appMenu.items.last?.title = strings["quit"] ?? "Quit Grant"
      settingsItem.title = strings["settings"] ?? "Settings…"
      window?.title = strings["previewWindowTitle"] ?? "Grant · Preview"
      self?.settingsWindow?.title = strings["settings"] ?? "Settings…"
      if let theme = self?.fontWindowStyle {
        self?.fontWindow?.title =
          "\(store.styleName(theme)) · \(strings["typography"] ?? "Typography")"
      }
    }
    if CommandLine.arguments.contains("--show-fonts") { showFontSettings(style: store.settings.style) }
    else if !CommandLine.arguments.contains("--state-dir")
      || CommandLine.arguments.contains("--show-settings")
    {
      showPreviewSettings()
    }
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor func renderFixtures(to path: String) throws {
  let root = URL(fileURLWithPath: path, isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  var files: [String] = []
  var catalog: [[String: Any]] = []
  func capture(_ settings: GrantSettings, actions: Bool, account: Bool, suffix: String, liveInput: Bool = false) throws {
    let view = GRGrantView(frame: .zero)
    view.showsActions = actions
    view.credentialsOnly = !account
    guard view.apply(settings: settings.dictionary, preview: actions && !liveInput) else {
      throw NSError(domain: "Grant", code: 3)
    }
    let window = NSWindow(
      contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: settings.appearance == "dark" ? .darkAqua : .aqua)
    window.contentView = view
    if liveInput {
      view.usernameField.stringValue = "preview-admin"
      view.setLiveContext("", account: account ? "" : "preview-admin")
      guard window.makeFirstResponder(view.passwordField) else {
        throw NSError(domain: "Grant", code: 14, userInfo: [NSLocalizedDescriptionKey: "Native input focus was not acquired."])
      }
    }
    view.layoutSubtreeIfNeeded()
    let layout = view.typographyEvidence() as? [String: Any] ?? [:]
    let bundledTitles = [
      "hard-edge": "BlackOpsOne-Regular", "blueprint": "SairaStencilOne-Regular",
    ]
    if suffix.isEmpty, settings.language == "en", let expected = bundledTitles[settings.style] {
      let runs = layout["runs"] as? [[String: Any]] ?? []
      guard
        runs.contains(where: {
          $0["font"] as? String == expected
            && ($0["file"] as? String)?.contains("/Grant.app/Contents/Resources/Fonts/") == true
        })
      else {
        throw NSError(
          domain: "Grant", code: 13,
          userInfo: [
            NSLocalizedDescriptionKey:
              "Selected theme title did not use its bundled face: \(expected)"
          ])
      }
    }
    guard layout["singleLine"] as? Bool == true else {
      throw NSError(
        domain: "Grant", code: 6,
        userInfo: [NSLocalizedDescriptionKey: "Title exceeds available width: \(settings.style)"])
    }
    guard layout["contextFits"] as? Bool == true, layout["detailsIsIcon"] as? Bool == true else {
      throw NSError(
        domain: "Grant", code: 9,
        userInfo: [NSLocalizedDescriptionKey: "Context or details layout failed: \(settings.style)"]
      )
    }
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
      throw NSError(domain: "Grant", code: 4)
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
      throw NSError(domain: "Grant", code: 5)
    }
    let name = "\(settings.style)-\(settings.appearance)-\(settings.language)\(suffix).png"
    try data.write(to: root.appendingPathComponent(name))
    files.append(name)
    catalog.append([
      "file": name, "style": settings.style, "language": settings.language,
      "appearance": settings.appearance, "typography": settings.typography,
      "size": ["width": view.bounds.width, "height": view.bounds.height],
      "systemHostLayout": !actions, "accountRequired": account,
      "credentialEntryEditable": view.passwordField.isEditable,
      "nativeInputFixture": liveInput,
      "passwordIsEmpty": view.passwordField.stringValue.isEmpty,
      "fontReport": GRGrantView.fontReport(settings: settings.dictionary) ?? [:],
      "titleLayout": layout,
    ])
    window.close()
  }
  for style in ["paper", "dot", "swiss", "hard-edge", "blueprint", "original"] {
    for language in ["en", "zh-Hans", "zh-Hant"] {
      for appearance in ["light", "dark"] {
        var settings = GrantSettings()
        settings.style = style
        settings.language = language
        settings.appearance = appearance
        try capture(settings, actions: true, account: false, suffix: "")
      }
    }
    for appearance in ["light", "dark"] {
      var live = GrantSettings()
      live.style = style; live.language = "en"; live.appearance = appearance
      try capture(live, actions: true, account: false, suffix: "-native-focus", liveInput: true)
      if appearance == "light" {
        try capture(live, actions: true, account: true, suffix: "-native-account", liveInput: true)
      }
    }
    var settings = GrantSettings()
    settings.style = style
    settings.language = "en"
    settings.appearance = "light"
    settings.typography = "system"
    try capture(settings, actions: true, account: false, suffix: "-system")
    settings.typography = "dots"
    try capture(settings, actions: false, account: true, suffix: "-host-layout")
    settings.typography = "theme"
    settings.fontOverrides[style] = [
      "Grant-Missing-Font-For-QA", "Doto", "DeparturePixelZhCompact-Regular",
    ]
    let report = GRGrantView.fontReport(settings: settings.dictionary) as? [String: Any] ?? [:]
    let availability = report["availability"] as? [[String: Any]] ?? []
    let providers = report["runs"] as? [[String: Any]] ?? []
    guard availability.first?["available"] as? Bool == false,
      providers.contains(where: { ($0["font"] as? String) == "DeparturePixelZhCompact-Regular" }),
      providers.contains(where: {
        ($0["file"] as? String)?.contains("/Grant.app/Contents/Resources/Fonts/") == true
      })
    else {
      throw NSError(
        domain: "Grant", code: 7,
        userInfo: [
          NSLocalizedDescriptionKey: "Missing-font fallback was not resolved to bundled glyphs."
        ])
    }
    try capture(settings, actions: true, account: false, suffix: "-fallback")
    settings.fontOverrides[style] = ["Grant-Missing-Font-For-QA"]
    let lastResort = GRGrantView.fontReport(settings: settings.dictionary) as? [String: Any] ?? [:]
    guard !(lastResort["runs"] as? [[String: Any]] ?? []).isEmpty else {
      throw NSError(
        domain: "Grant", code: 8,
        userInfo: [NSLocalizedDescriptionKey: "System last-resort fallback failed."])
    }
    try capture(settings, actions: true, account: false, suffix: "-system-fallback")
    settings.fontOverrides[style] = ["@system-mono"]
    settings.appearanceFontOverrides[style] = ["light": ["Impact"], "dark": ["HelveticaNeue-Bold"]]
    for (appearance, expected) in [("light", "Impact"), ("dark", "HelveticaNeue-Bold")] {
      settings.appearance = appearance
      let scoped = GRGrantView.fontReport(settings: settings.dictionary) as? [String: Any] ?? [:]
      guard (scoped["configured"] as? [String]) == [expected],
        (scoped["runs"] as? [[String: Any]] ?? []).contains(where: {
          $0["font"] as? String == expected
        })
      else {
        throw NSError(
          domain: "Grant", code: 10,
          userInfo: [NSLocalizedDescriptionKey: "Appearance font override failed."])
      }
      try capture(settings, actions: true, account: false, suffix: "-appearance-font")
    }
    settings.appearanceFontOverrides[style]?.removeValue(forKey: "dark")
    let inherited = GRGrantView.fontReport(settings: settings.dictionary) as? [String: Any] ?? [:]
    guard inherited["configured"] as? [String] == ["@system-mono"] else {
      throw NSError(
        domain: "Grant", code: 11,
        userInfo: [NSLocalizedDescriptionKey: "Appearance did not inherit the theme stack."])
    }
    try capture(settings, actions: true, account: false, suffix: "-inherited-font")
    settings.appearanceFontOverrides[style]?["dark"] = ["@invalid-font-token"]
    let invalid = GRGrantView.fontReport(settings: settings.dictionary) as? [String: Any] ?? [:]
    guard invalid["error"] != nil else {
      throw NSError(
        domain: "Grant", code: 12,
        userInfo: [NSLocalizedDescriptionKey: "Invalid appearance stack was accepted."])
    }
  }
  let data = try JSONSerialization.data(
    withJSONObject: [
      "files": files, "catalog": catalog,
      "font": GRGrantView.fontEvidence() ?? ["error": "missing font evidence"],
      "scope":
        "Real native views in unordered windows. Host-layout images are geometry evidence; no system authorization or SecurityAgent host was invoked.",
    ], options: [.prettyPrinted, .sortedKeys])
  try data.write(to: root.appendingPathComponent("render.json"))
  print(
    "Rendered \(files.count) native fixtures across six themes; no windows shown or authorization requested."
  )
}

func probeAuthorization(isolated: Bool = true) -> Int32 {
  let rightName = isolated ? "com.alex.Grant.probe" : "system.privilege.admin"
  var definition: CFDictionary?
  guard AuthorizationRightGet(rightName, &definition) == errAuthorizationSuccess,
    let rule = definition as? [String: Any],
    (!isolated || (rule["mechanisms"] as? [String])?.first == "Grant:credentials")
  else {
    fputs("Isolated Grant probe is not installed. No authorization requested.\n", stderr)
    return 2
  }
  var authorization: AuthorizationRef?
  var status = AuthorizationCreate(nil, nil, [], &authorization)
  guard status == errAuthorizationSuccess, let authorization else { return 2 }
  status = rightName.withCString { name in
    var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
    return withUnsafeMutablePointer(to: &item) { pointer in
      var rights = AuthorizationRights(count: 1, items: pointer)
      return AuthorizationCopyRights(
        authorization, &rights, nil, [.interactionAllowed, .extendRights], nil)
    }
  }
  AuthorizationFree(authorization, [.destroyRights])
  print("\(isolated ? "Isolated Grant probe" : "System administrator request") status: \(status). No privileged operation was executed.")
  return status == errAuthorizationSuccess ? 0 : 1
}


// sudo owns authentication and command execution. This controller only collects
// a single response in its native field, then releases it through the pipe.
@MainActor final class SudoPromptController: NSObject, NSApplicationDelegate, NSWindowDelegate {
  let channel: GRSudoChannel
  let prompt: String
  let store = PreviewStore()
  let card = GRGrantView(frame: .zero)
  var panel: NSPanel?
  var timer: Timer?
  var result: Int32 = 1
  var finished = false
  var submitting = false
  var inputErrorKey: String?
  var signals: [DispatchSourceSignal] = []
  init(channel: GRSudoChannel, prompt: String) {
    self.channel = channel
    self.prompt = String(prompt.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(512))
  }
  func applicationDidFinishLaunching(_ notification: Notification) {
    guard store.error == nil, channel.isValid() else { finish(); return }
    card.showsActions = true; card.credentialsOnly = true; card.sudoPrompt = prompt
    guard card.apply(settings: store.settings.dictionary, preview: false) else { finish(); return }
    card.setLiveContext(prompt, account: "") // sudo's prompt owns the account name, not -u.
    card.submitRequested = { [weak self] in
      guard let self, !self.finished, !self.submitting else { return }
      self.submitting = true
      self.inputErrorKey = nil
      // Read and commit the active native editor before changing its state.
      let status = self.channel.submit(field: self.card.passwordField)
      if status == -2 || status == -3 {
        self.submitting = false
        let key = status == -2 ? "sudoPasswordRequired" : "sudoPasswordError"
        self.inputErrorKey = key
        self.card.showError(self.store.text(key))
        self.focusPassword()
        return
      }
      self.card.setInteractionEnabled(false)
      self.result = status == 1 ? 0 : 1
      self.finish()
    }
    card.credentialsChanged = { [weak self] in
      guard let self, self.inputErrorKey != nil else { return }
      self.inputErrorKey = nil
      self.card.showError("")
    }
    card.cancelRequested = { [weak self] in self?.finish() }
    card.appearanceChangeRequested = { [weak self] key, value in
      guard let self, let key, let value, self.store.selectAppearance(key, value: value) else { return }
      self.refresh()
    }
    card.settingsRequested = { [weak self] section in
      guard let self else { return }
      let config = NSWorkspace.OpenConfiguration(); config.createsNewApplicationInstance = true; config.arguments = [section == "fonts" ? "--show-fonts" : "--show-settings"]
      let app = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Grant.app")
      // Cancel and clear before asking another app process to show Settings.
      self.card.closeSettingsMenu(); self.card.clearPassword(); self.card.setInteractionEnabled(false); self.panel?.orderOut(nil)
      NSWorkspace.shared.openApplication(at: app, configuration: config) { [weak self] _, _ in
        DispatchQueue.main.async { self?.finish() }
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.finish() }
    }
    let panel = NSPanel(contentRect: NSRect(origin: .zero, size: card.preferredSize),
      styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
    panel.title = "Grant · sudo"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
    panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
    for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { panel.standardWindowButton(button)?.isHidden = true }
    panel.contentView = card; panel.delegate = self; self.panel = panel
    panel.initialFirstResponder = card.passwordField
    card.layoutSubtreeIfNeeded()
    panel.center(); panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    focusPassword()
    DistributedNotificationCenter.default().addObserver(
      self, selector: #selector(preferencesChanged(_:)), name: grantPreferencesChanged, object: nil)
    timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { if let self, !self.channel.isValid() { self.finish() } }
    }
    for number in [SIGINT, SIGTERM, SIGHUP] {
      signal(number, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
      source.setEventHandler { [weak self] in self?.finish() }; source.resume(); signals.append(source)
    }
  }
  func refresh() {
    guard channel.isValid(), card.apply(settings: store.settings.dictionary, preview: false) else { finish(); return }
    if let inputErrorKey { card.showError(store.text(inputErrorKey)) }
    panel?.setContentSize(card.preferredSize); focusPassword()
  }
  func focusPassword() {
    guard !finished, !submitting, let panel else { return }
    // AppKit activation/key-window notifications can arrive after launch. Lay
    // out the field before asking it to create its native field editor.
    card.layoutSubtreeIfNeeded()
    if let editor = card.passwordField.currentEditor(), panel.firstResponder === editor { return }
    panel.makeFirstResponder(card.passwordField)
  }
  func applicationDidBecomeActive(_ notification: Notification) { focusPassword() }
  func windowDidBecomeKey(_ notification: Notification) { focusPassword() }
  @objc func preferencesChanged(_ notification: Notification) {
    guard !finished else { return }
    store.reloadPreferences()
    guard store.error == nil else { return }
    refresh()
  }
  func windowShouldClose(_ sender: NSWindow) -> Bool { finish(); return false }
  func finish() {
    guard !finished else { return }; finished = true
    timer?.invalidate(); signals.forEach { $0.cancel() }; card.closeSettingsMenu(); card.clearPassword()
    panel?.orderOut(nil); NSApp.stop(nil)
    NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: false)
  }
}

@MainActor func runGrant() {
  let app = NSApplication.shared
  let arguments = CommandLine.arguments
  if arguments.dropFirst().first == "--sudo-askpass" {
    guard arguments.count == 3, let channel = GRSudoChannel.open() else {
      fputs("Grant askpass requires its local sudo parent and private pipe.\n", stderr); exit(2)
    }
    let controller = SudoPromptController(channel: channel, prompt: arguments[2])
    app.setActivationPolicy(.accessory); app.delegate = controller
    app.run()
    exit(controller.result)
  } else if let index = arguments.firstIndex(of: "--render"), arguments.indices.contains(index + 1) {
    app.setActivationPolicy(.prohibited)
    do { try renderFixtures(to: arguments[index + 1]) } catch {
      fputs("Render failed: \(error)\n", stderr)
      exit(1)
    }
  } else if arguments.contains("--quit-preview") || arguments.contains("--verify-running") {
    app.setActivationPolicy(.prohibited)
    let ownURL = Bundle.main.bundleURL.standardizedFileURL
    let ownedRoot: String? = {
      guard let index = arguments.firstIndex(of: "--owned-root"),
        arguments.indices.contains(index + 1)
      else { return nil }
      return URL(fileURLWithPath: arguments[index + 1]).standardizedFileURL.path
    }()
    let running = NSRunningApplication.runningApplications(
      withBundleIdentifier: "com.alex.Grant.Preview"
    ).filter {
      $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        && ($0.bundleURL?.standardizedFileURL == ownURL
          || (ownedRoot != nil
            && ($0.bundleURL?.path.hasPrefix(ownedRoot! + "/Local/Builds/") == true
              || $0.bundleURL?.path == ownedRoot! + "/Local/Grant.app")))
    }
    if arguments.contains("--quit-preview") {
      for candidate in running { candidate.terminate() }
      let deadline = Date(timeIntervalSinceNow: 3)
      while running.contains(where: { !$0.isTerminated }) && Date() < deadline {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
      }
      if running.contains(where: { !$0.isTerminated }) {
        fputs("Previous Grant preview did not quit; no forced termination was attempted.\n", stderr)
        exit(1)
      }
    } else {
      guard !running.isEmpty else {
        fputs("Grant preview process is not running.\n", stderr)
        exit(1)
      }
      print("Grant preview running from \(ownURL.path)")
    }
  } else if arguments.contains("--request-auth") {
    app.setActivationPolicy(.prohibited)
    exit(probeAuthorization(isolated: false))
  } else if arguments.contains("--probe-auth") {
    app.setActivationPolicy(.prohibited)
    exit(probeAuthorization())
  } else if arguments.contains("--notify-settings") {
    app.setActivationPolicy(.prohibited)
    DistributedNotificationCenter.default().postNotificationName(
      grantPreferencesChanged, object: nil, userInfo: nil, deliverImmediately: true)
  } else if arguments.contains("--system-status") {
    app.setActivationPolicy(.prohibited)
    let active = grantSystemActive()
    print(
      "System authorization: \(active == true ? "Grant selected" : active == false ? "stock Apple UI" : "unavailable")"
    )
    print(
      "Plugin installed: \(FileManager.default.fileExists(atPath: "/Library/Security/SecurityAgentPlugins/Grant.bundle"))"
    )
    print("Plugin version: \(grantPluginVersion() ?? "not installed")")
    print("Settings app version: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")")
  } else if let index = arguments.firstIndex(where: { $0 == "--validate-settings" || $0 == "--validate-compatible-settings" }),
    arguments.indices.contains(index + 1)
  {
    app.setActivationPolicy(.prohibited)
    do {
      let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: arguments[index + 1]))
      defer { try? handle.close() }
      let data = try handle.read(upToCount: 65537) ?? Data()
      guard data.count <= 65536 else { throw NSError(domain: "Grant", code: 1) }
      let settings = try JSONDecoder().decode(GrantSettings.self, from: data)
      if arguments.contains("--validate-compatible-settings"), settings.style == "original", grantSystemActive() == true,
        (grantPluginVersion() ?? "0").compare("0.2.3", options: .numeric) == .orderedAscending {
        fputs("Update the system plugin before selecting Setup Original.\n", stderr); exit(1)
      }
      guard GRGrantView(frame: .zero).apply(settings: settings.dictionary, preview: true) else {
        throw NSError(domain: "Grant", code: 1)
      }
    } catch {
      fputs("Invalid Grant appearance preferences.\n", stderr)
      exit(1)
    }
  } else {
    app.setActivationPolicy(arguments.contains("--settings-agent") ? .accessory : .regular)
    let delegate = GrantAppDelegate()
    app.delegate = delegate
    app.run()
  }
}
MainActor.assumeIsolated { runGrant() }
