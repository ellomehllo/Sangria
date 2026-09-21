//
//  main.swift
//  Harness
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

// Headless verification harness for the Whisky DX build.
//
// Links the repo's WhiskyKit and drives the same code paths the app uses
// (runtime install, bottle creation, Program.launchWithUserMode, env
// composition, DXMT deployment, log verification), so results reflect the app.
// It has no bundle identifier, so WhiskyKit resolves the app's folders through
// Bundle.whiskyBundleIdentifier's fallback: local.bluevsh.WhiskyDX.

import CryptoKit
import Foundation
import SemanticVersion
import WhiskyKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func option(_ name: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}

func flag(_ name: String, in args: [String]) -> Bool {
    args.contains(name)
}

@MainActor
func bottle(named name: String) -> Bottle {
    var data = BottleData()
    guard let bottle = data.loadBottles().first(where: { $0.settings.name == name }) else {
        fail("no bottle named \(name)")
    }
    return bottle
}

func parseBackend(_ raw: String) -> GraphicsBackend {
    guard let backend = GraphicsBackend(rawValue: raw) else {
        fail("unknown backend \(raw); one of \(GraphicsBackend.allCases.map(\.rawValue))")
    }
    return backend
}

/// winebuild stamps "Wine builtin DLL" at 0x40 in the DOS stub of builtins.
func peKind(_ url: URL) -> String {
    guard let data = try? Data(contentsOf: url) else { return "absent" }
    guard data.count >= 0x50 else { return "short" }
    return String(decoding: data[0x40 ..< 0x50], as: UTF8.self) == "Wine builtin DLL" ? "builtin" : "native"
}

func sha(_ url: URL) -> String {
    guard let data = try? Data(contentsOf: url) else { return "missing" }
    return SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
}

// MARK: - Commands

@MainActor
func installRuntime() async throws {
    if WhiskyWineInstaller.isWhiskyWineInstalled() {
        print("runtime already installed: \(WhiskyWineInstaller.whiskyWineVersion().map { "\($0)" } ?? "?")")
        return
    }
    let versionURL = URL(string: DistributionConfig.versionPlistURL)!
    print("fetching \(versionURL)")
    let (plistData, _) = try await URLSession.shared.data(from: versionURL)
    let info = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: plistData)
    let version = "\(info.version.major).\(info.version.minor).\(info.version.patch)"
    let downloadURL = URL(string: DistributionConfig.librariesURL(version: version))!
    print("downloading runtime \(version) from \(downloadURL)")
    let (tempURL, response) = try await URLSession.shared.download(from: downloadURL)
    if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
        fail("HTTP \(http.statusCode)")
    }
    let tarball = FileManager.default.temporaryDirectory.appending(path: "Libraries.tar.gz")
    try? FileManager.default.removeItem(at: tarball)
    try FileManager.default.moveItem(at: tempURL, to: tarball)
    if let expected = info.sha256 {
        let actual = WhiskyWineInstaller.sha256(ofFileAt: tarball)
        guard actual?.lowercased() == expected.lowercased() else {
            fail("sha256 mismatch: expected \(expected), got \(actual ?? "nil")")
        }
        print("sha256 verified: \(expected)")
    } else {
        print("warning: no sha256 advertised")
    }
    try WhiskyWineInstaller.install(from: tarball)
    WhiskyWineInstaller.cleanupTarball(at: tarball)
    print("installed runtime \(WhiskyWineInstaller.whiskyWineVersion().map { "\($0)" } ?? "?"), " +
        "DXMT \(WhiskyWineInstaller.whiskyWineDXMTVersion() ?? "none"), " +
        "DXVK \(WhiskyWineInstaller.whiskyWineDXVKVersion() ?? "none")")
}

/// Mirrors BottleVM.createBottleTask.
@MainActor
func createBottle(name: String) async throws {
    guard WhiskyWineInstaller.isWhiskyWineInstalled() else { fail("runtime not installed") }
    var data = BottleData()
    if data.loadBottles().contains(where: { $0.settings.name == name }) { fail("bottle exists") }
    let url = BottleData.defaultBottleDir.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let bottle = Bottle(bottleUrl: url, inFlight: true)
    bottle.settings.windowsVersion = .win10
    bottle.settings.name = name
    bottle.settings.graphicsBackend = GraphicsBackendResolver.defaultForNewBottle()
    _ = try await Wine.changeWinVersion(bottle: bottle, win: .win10)
    let wineVersion = try await Wine.wineVersion()
    bottle.settings.wineVersion = SemanticVersion(wineVersion) ?? SemanticVersion(0, 0, 0)
    BottleFontBootstrap.copySystemFonts(toPrefix: url)
    bottle.saveBottleSettings()
    data.paths.append(url)
    print("created bottle \(name) at \(url.path)")
    print("wine \(wineVersion), backend \(bottle.settings.graphicsBackend.rawValue)")
}

@MainActor
func status() {
    print("runtime installed: \(WhiskyWineInstaller.isWhiskyWineInstalled())")
    print("runtime version: \(WhiskyWineInstaller.whiskyWineVersion().map { "\($0)" } ?? "-")")
    print("DXMT payload: \(WhiskyWineInstaller.whiskyWineDXMTVersion() ?? "-"), native: \(Wine.isDXMTRuntimeNative())")
    print("DXVK payload: \(WhiskyWineInstaller.whiskyWineDXVKVersion() ?? "-")")
    print("D3DMetal installed: \(WhiskyWineInstaller.isD3DMetalInstalled())")
    for backend in GraphicsBackend.allCases {
        print("  available \(backend.rawValue): \(WhiskyWineInstaller.isBackendAvailable(backend))")
    }
    print("recommended (no program): \(GraphicsBackendResolver.resolveWithReason())")
    print("new bottle default: \(GraphicsBackendResolver.defaultForNewBottle().rawValue)")
    var data = BottleData()
    for bottle in data.loadBottles() {
        print("bottle \(bottle.settings.name): backend \(bottle.settings.graphicsBackend.rawValue), " +
            "dxmt fps \(bottle.settings.dxmtFrameRateLimit), metalFX \(bottle.settings.dxmtMetalFXSpatial) " +
            "\(bottle.url.path)")
    }
}

@MainActor
func run(_ args: [String]) async throws {
    guard args.count >= 2 else { fail("run <bottle> <exe> [options]") }
    let target = bottle(named: args[0])
    let exe = URL(fileURLWithPath: args[1])
    let program = Program(url: exe, bottle: target)
    if let raw = option("--program-backend", in: args) {
        var overrides = program.settings.overrides ?? ProgramOverrides()
        overrides.graphicsBackend = raw == "inherit" ? nil : parseBackend(raw)
        program.settings.overrides = overrides
    }
    // --fps-limit N|inherit: the per-program frame rate limit (0 runs uncapped)
    if let raw = option("--fps-limit", in: args) {
        var overrides = program.settings.overrides ?? ProgramOverrides()
        overrides.frameRateLimit = raw == "inherit" ? nil : Int(raw)
        program.settings.overrides = overrides
    }
    // --win-version win7|win10|…|inherit: the per-program Windows version override
    if let raw = option("--win-version", in: args) {
        var overrides = program.settings.overrides ?? ProgramOverrides()
        if raw == "inherit" {
            overrides.windowsVersion = nil
        } else if let version = WinVersion(rawValue: raw) {
            overrides.windowsVersion = version
        } else {
            fail("unknown Windows version \(raw)")
        }
        program.settings.overrides = overrides
    }
    // --dll d3d11=n,b (repeatable): per-program DLL overrides, the same field
    // the app's UI writes. Needed because constructWineEnvironment composes
    // WINEDLLOVERRIDES itself and overwrites any value passed as --env.
    var dllOverrides: [DLLOverrideEntry] = []
    for (index, arg) in args.enumerated() where arg == "--dll" && index + 1 < args.count {
        let parts = args[index + 1].split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2, let mode = DLLOverrideMode(rawValue: parts[1]) else {
            fail("--dll NAME=n,b|n|b|b,n|'' (empty disables)")
        }
        dllOverrides.append(DLLOverrideEntry(dllName: parts[0], mode: mode))
    }
    if !dllOverrides.isEmpty {
        var overrides = program.settings.overrides ?? ProgramOverrides()
        overrides.dllOverrides = dllOverrides
        program.settings.overrides = overrides
        print("dll overrides: " + dllOverrides.map { "\($0.dllName)=\($0.mode.rawValue)" }.joined(separator: " "))
    }

    var debug = program.settings.effectiveGraphicsDebug
    debug.metalAPIValidation = flag("--api-validation", in: args)
    debug.metalShaderValidation = flag("--shader-validation", in: args)
    debug.writeGraphicsLogs = !flag("--no-logs", in: args)
    debug.measureFrameRate = flag("--measure", in: args)
    program.settings.effectiveGraphicsDebug = debug
    program.settings.arguments = option("--args", in: args) ?? ""
    program.settings.environment = [:]
    for (index, arg) in args.enumerated() where arg == "--env" && index + 1 < args.count {
        let pair = args[index + 1].split(separator: "=", maxSplits: 1).map(String.init)
        if pair.count == 2 { program.settings.environment[pair[0]] = pair[1] }
    }

    let preview = Wine.previewGraphics(
        for: exe,
        bottleBackend: target.settings.graphicsBackend,
        programBackend: program.settings.overrides?.graphicsBackend
    )
    print("preview: \(preview.decision.summary)")
    print("api: \(preview.profile?.summary ?? "n/a"), assessment: \(preview.assessment.message ?? "compatible")")

    var capture: FrameCaptureRequest?
    if let name = option("--capture", in: args) {
        capture = FrameCaptureRequest(
            executableName: name, automaticFrame: option("--auto-frame", in: args).flatMap(Int.init)
        )
    }
    let started = Date()
    let result = await program.launchWithUserMode(
        useTerminal: false, frameCapture: capture, skipGraphicsAPICheck: flag("--skip-api-check", in: args)
    )
    switch result {
    case .launchedSuccessfully:
        print("launched: \(program.lastBackendDecision?.summary ?? "?")")
    case let .launchFailed(_, message):
        print("LAUNCH REFUSED/FAILED: \(message)")
        return
    case .launchedInTerminal:
        break
    }

    // Wait for the bottle to go idle (the probe exits on its own) or time out.
    let timeout = option("--wait", in: args).flatMap(Double.init) ?? 60
    try await Task.sleep(for: .seconds(2))
    while Date().timeIntervalSince(started) < timeout {
        if await !Wine.isWineserverRunning(for: target) { break }
        try await Task.sleep(for: .seconds(1))
    }
    let elapsed = Date().timeIntervalSince(started)
    print(String(format: "session ended after %.1fs", elapsed))
    report(program: program, since: started)
}

@MainActor
func report(program: Program, since: Date) {
    let history = RunLogStore.load(for: program.name, in: program.bottle.url)
    if let run = history.entries.max(by: { $0.startTime < $1.startTime }) {
        print("run log: backend=\(run.graphicsBackendName ?? "-") choice=\(run.graphicsBackendChoiceName ?? "-") " +
            "reason=\(run.graphicsBackendReason ?? "-") logging=\(run.graphicsLoggingEnabled ?? false) " +
            "capture=\(run.frameCaptureArmed ?? false)")
        if let backend = run.graphicsBackend {
            let verification = GraphicsLogInspector.verify(
                expected: backend, since: run.startTime, programURL: program.url,
                bottleURL: program.bottle.url, loggingEnabled: run.graphicsLoggingEnabled ?? false
            )
            print("verification: \(verification.summary)")
        }
    }
    for file in GraphicsLogInspector.logFiles(programURL: program.url, bottleURL: program.bottle.url)
        where file.modified >= since.addingTimeInterval(-2) {
        print("log \(file.backend.rawValue)/\(file.url.lastPathComponent) (\(file.size) bytes)")
        for line in GraphicsLogInspector.tail(of: file.url, maxBytes: 1_500).split(separator: "\n").suffix(8) {
            print("    \(line)")
        }
    }
    let system32 = program.bottle.url.appending(path: "drive_c/windows/system32")
    for dll in ["d3d11.dll", "dxgi.dll", "d3d10core.dll", "winemetal.dll", "d3d9.dll"] {
        let url = system32.appending(path: dll)
        let native = peKind(url)
        print("system32/\(dll): \(native) \(sha(url))")
    }
    let results = program.url.deletingPathExtension().appendingPathExtension("results.txt")
    if let text = try? String(contentsOf: results, encoding: .utf8),
       let attributes = try? FileManager.default.attributesOfItem(atPath: results.path),
       let modified = attributes[.modificationDate] as? Date, modified >= since {
        print("probe results:\n" + text.split(separator: "\n").map { "    \($0)" }.joined(separator: "\n"))
    } else {
        print("probe results: none written this run")
    }
    if let run = history.entries.max(by: { $0.startTime < $1.startTime }), run.frameRateMeasured == true {
        let log = Wine.logsFolder.appending(path: run.logFileName)
        print("metal HUD: \(MetalHUDLog.measurement(inLogAt: log)?.summary ?? "no samples")")
    }
    for capture in FrameCaptureLocator.captures(near: program.url) {
        print("capture: \(capture.path)")
    }
    // The Whisky run log header, which names the backend on its own.
    if let log = program.settings.lastLogFileURL, let text = try? String(contentsOf: log, encoding: .utf8) {
        for line in text.split(separator: "\n") where line.hasPrefix("Graphics Backend")
            || line.hasPrefix("Detected Graphics API") {
            print("wine log: \(line)")
        }
        let interesting = text.split(separator: "\n").filter {
            $0.localizedCaseInsensitiveContains("dxmt") || $0.contains("err:") || $0.contains("DXVK")
        }
        for line in interesting.prefix(12) {
            print("    | \(line)")
        }
    }
}

@MainActor
func main() async throws {
    var args = Array(CommandLine.arguments.dropFirst())
    guard !args.isEmpty else {
        fail("commands: install-runtime | create-bottle NAME | status | import-gptk PATH | " +
            "set-backend BOTTLE BACKEND | set-dxmt BOTTLE fps metalfx factor | preview BOTTLE EXE | run BOTTLE EXE ...")
    }
    let command = args.removeFirst()
    switch command {
    case "install-runtime":
        try await installRuntime()
    case "create-bottle":
        guard let name = args.first else { fail("create-bottle NAME") }
        try await createBottle(name: name)
    case "status":
        status()
    case "import-gptk":
        guard let path = args.first, let root = GPTKImporter.locatePayload(under: URL(fileURLWithPath: path)) else {
            fail("no GPTK payload under that path")
        }
        let payload = try GPTKImporter.validatePayload(at: root)
        let record = try GPTKImporter.importPayload(payload)
        print("imported GPTK payload: \(record)")
        // Same as GPTKSettingsSection: deploy right after importing.
        // The app only deploys onto a GPTK-capable engine; so does this.
        print("runtime GPTK-capable: \(GPTKImporter.isRuntimeGPTKCapable())")
        if GPTKImporter.isRuntimeGPTKCapable() {
            try GPTKImporter.deployStoredPayload()
        }
        print("deployed: \(GPTKImporter.isDeployed())")
    case "bottle-path":
        guard let name = args.first else { fail("bottle-path BOTTLE") }
        print(bottle(named: name).url.path(percentEncoded: false))
    case "deploy-gptk":
        // What the app does when a capable engine is installed or the GPTK
        // settings section appears: deploy the already-imported store, gated.
        print("stored payload: \(GPTKImporter.storedRecord().map { "\($0)" } ?? "none")")
        print("runtime GPTK-capable: \(GPTKImporter.isRuntimeGPTKCapable())")
        print("deployed now: \(GPTKImporter.deployStoredPayloadIfCapable())")
        print("deployed: \(GPTKImporter.isDeployed()), D3DMetal installed: \(WhiskyWineInstaller.isD3DMetalInstalled())")
    case "undeploy-gptk":
        try GPTKImporter.removeDeployedPayload()
        print("deployed: \(GPTKImporter.isDeployed()), D3DMetal installed: \(WhiskyWineInstaller.isD3DMetalInstalled())")
        print("D3DMetal installed: \(WhiskyWineInstaller.isD3DMetalInstalled())")
    case "set-backend":
        guard args.count == 2 else { fail("set-backend BOTTLE BACKEND") }
        let target = bottle(named: args[0])
        target.settings.graphicsBackend = parseBackend(args[1])
        target.saveBottleSettings()
        print("bottle \(args[0]) backend = \(target.settings.graphicsBackend.rawValue)")
    case "set-fps":
        // set-fps BOTTLE N: the bottle's frame rate limit, 0 for off. The app
        // ships the limiter in its Resources; point SANGRIA_FPS_LIBRARY at one.
        guard args.count == 2, let limit = Int(args[1]) else { fail("set-fps BOTTLE FPS") }
        let target = bottle(named: args[0])
        target.settings.frameRateLimit = limit
        target.saveBottleSettings()
        print("bottle \(args[0]) frame rate limit = \(target.settings.frameRateLimit), " +
            "limiter: \(FrameRateLimiter.libraryURL()?.path(percentEncoded: false) ?? "none")")
    case "set-dxmt":
        guard args.count == 4 else { fail("set-dxmt BOTTLE FPS on|off FACTOR") }
        let target = bottle(named: args[0])
        target.settings.dxmtFrameRateLimit = Int(args[1]) ?? 0
        target.settings.dxmtMetalFXSpatial = args[2] == "on"
        target.settings.dxmtUpscaleFactor = Double(args[3]) ?? 2
        target.saveBottleSettings()
        print(DXMTConfiguration.render(settings: target.settings))
    case "preview":
        guard args.count == 2 else { fail("preview BOTTLE EXE") }
        let target = bottle(named: args[0])
        let program = Program(url: URL(fileURLWithPath: args[1]), bottle: target)
        let preview = Wine.previewGraphics(
            for: program.url,
            bottleBackend: target.settings.graphicsBackend,
            programBackend: program.settings.overrides?.graphicsBackend
        )
        print("decision: \(preview.decision.summary)")
        print("api: \(preview.profile?.summary ?? "n/a")")
        print("assessment: \(preview.assessment)")
    case "run":
        try await run(args)
    case "add-note":
        // add-note TITLE BACKEND STATUS --fps N --api A --notes N --bottle B --path P --verification V
        guard args.count >= 3 else { fail("add-note TITLE BACKEND STATUS [options]") }
        guard let status = CompatibilityStatus(rawValue: args[2]) else { fail("status working|partial|broken") }
        let note = CompatibilityNote(
            title: args[0],
            backend: parseBackend(args[1]),
            status: status,
            notes: option("--notes", in: args) ?? "",
            lastTested: Date(),
            averageFPS: option("--fps", in: args).flatMap(Double.init),
            graphicsAPI: option("--api", in: args),
            bottleName: option("--bottle", in: args),
            programPath: option("--path", in: args),
            backendVerification: option("--verification", in: args)
        )
        var database = CompatibilityDatabase.load()
        database.upsert(note)
        try database.save()
        print("saved note \(note.title) / \(note.backend.rawValue) to \(CompatibilityDatabase.defaultURL.path)")
    default:
        fail("unknown command \(command)")
    }
}

try await main()
