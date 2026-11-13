import AppKit
import Darwin

enum Jumper {
    private static let helperToApp = ["dev.herdr.core": "dev.herdr.app"]

    static func hostApp(pid: Int32) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<40 {
            if let app = NSRunningApplication(processIdentifier: current) {
                if app.activationPolicy == .regular { return app }
                if let bundle = app.bundleIdentifier, let target = helperToApp[bundle],
                   let host = NSRunningApplication.runningApplications(withBundleIdentifier: target).first {
                    return host
                }
            }
            guard let parent = processInfo(current)?.kp_eproc.e_ppid, parent > 1 else { return nil }
            current = parent
        }
        return nil
    }

    static func hostAppName(pid: Int32) -> String {
        hostApp(pid: pid)?.localizedName ?? "terminal"
    }

    static func activate(pid: Int32) {
        guard let app = hostApp(pid: pid) else {
            NSSound.beep()
            return
        }
        app.activate()
        if app.bundleIdentifier == "com.googlecode.iterm2", let tty = ttyName(pid) {
            selectITermSession(tty: tty)
        }
        if app.bundleIdentifier == "dev.herdr.app" {
            DispatchQueue.global(qos: .userInitiated).async { focusHerdrTerminal(pid: pid) }
        }
    }

    private static let localBin = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin")

    private static func focusHerdrTerminal(pid: Int32) {
        let hc = localBin.appendingPathComponent("hc").path
        guard let list = runJSON(hc, ["ls", "--json"]),
              let terminals = list["terminals"] as? [[String: Any]] else { return }
        for terminal in terminals {
            guard let address = terminal["address"] as? String,
                  let detail = runJSON(hc, ["get", address, "--json"]) else { continue }
            let shellPid = (detail["pid"] as? NSNumber)?.int32Value
            let foregroundPid = ((detail["foreground"] as? [String: Any])?["pid"] as? NSNumber)?.int32Value
            if shellPid == pid || foregroundPid == pid {
                let app = localBin.appendingPathComponent("herdr-app").path
                _ = run(app, ["do", "agent.focus", "{\"terminal\":\"\(address)\"}"])
                return
            }
        }
    }

    private static func runJSON(_ path: String, _ args: [String]) -> [String: Any]? {
        guard let data = run(path, args) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func run(_ path: String, _ args: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    private static func processInfo(_ pid: Int32) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }

    private static func ttyName(_ pid: Int32) -> String? {
        guard let device = processInfo(pid)?.kp_eproc.e_tdev, device != -1,
              let name = devname(device, S_IFCHR)
        else { return nil }
        return "/dev/" + String(cString: name)
    }

    private static func selectITermSession(tty: String) {
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            select w
                            select t
                            select s
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }
}
