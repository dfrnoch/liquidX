import Foundation
import LiquidUpdateSupport

// LiquidX's update installer (docs/updates.md). An XPC service embedded in the Mac
// app at Contents/XPCServices. Unlike the app it isn't sandboxed: replacing the app
// bundle in /Applications needs that. It accepts connections only from LiquidX
// signed by the same team, checks every update itself (whatever the app claims)
// and never installs anything that isn't a newer, correctly signed LiquidX.

#if DEBUG
// Development builds are signed with Apple Development and not notarized.
let updateRequirement = UpdateSupport.teamRequirement
#else
let updateRequirement = UpdateSupport.updateRequirement
#endif

final class Installer: NSObject, UpdateInstalling {
    func installUpdate(fromArchive archive: FileHandle, sha256: String, replacingAppAtPath installedPath: String,
                       relaunchAfterProcess pid: Int32, arguments: [String],
                       withReply reply: @escaping @Sendable (String?) -> Void) {
        let installed = URL(fileURLWithPath: installedPath).standardizedFileURL
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiquidXUpdate-\(UUID().uuidString)", isDirectory: true)
        do throws(UpdateSupport.Failure) {
            guard installed.pathExtension == "app" else { throw .notAnApplication }
            try UpdateSupport.verifySignature(of: installed, requirement: UpdateSupport.teamRequirement)
            try UpdateSupport.installArchive(from: archive, expectedSHA256: sha256, replacing: installed,
                                             requirement: updateRequirement, workDirectory: work)
            try UpdateSupport.scheduleRelaunch(of: installed, after: pid, arguments: arguments)
            reply(nil)
        } catch {
            reply(error.description)
        }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Only LiquidX itself may ask for an install.
        connection.setCodeSigningRequirement(UpdateSupport.teamRequirement)
        connection.exportedInterface = NSXPCInterface(with: (any UpdateInstalling).self)
        connection.exportedObject = Installer()
        connection.resume()
        return true
    }
}

let delegate = ListenerDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
