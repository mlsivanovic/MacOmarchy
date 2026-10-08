import CoreFoundation
import CoreGraphics
import Foundation

@_silgen_name("SLSMainConnectionID")
func SLSMainConnectionID() -> Int32

@_silgen_name("SLSCopyManagedDisplaySpaces")
func SLSCopyManagedDisplaySpaces(_ cid: Int32) -> Unmanaged<CFArray>

@_silgen_name("SLSCopyBestManagedDisplayForPoint")
func SLSCopyBestManagedDisplayForPoint(_ cid: Int32, _ point: CGPoint) -> Unmanaged<CFString>?

@_silgen_name("SLSManagedDisplaySetCurrentSpace")
func SLSManagedDisplaySetCurrentSpace(_ cid: Int32, _ uuid: CFString, _ sid: UInt64)

struct ScreenSpaces {
    let uuid: String
    let current: UInt64
    let spaces: [UInt64]
}

func allScreens() -> [ScreenSpaces] {
    let raw = SLSCopyManagedDisplaySpaces(SLSMainConnectionID()).takeRetainedValue() as NSArray
    var result: [ScreenSpaces] = []
    for item in raw {
        guard let display = item as? NSDictionary else { continue }
        let uuid = (display["Display Identifier"] as? String) ?? ""
        let current = ((display["Current Space"] as? NSDictionary)?["id64"] as? NSNumber)?.uint64Value ?? 0
        var spaces: [UInt64] = []
        if let list = display["Spaces"] as? NSArray {
            for space in list {
                if let dict = space as? NSDictionary, let id = dict["id64"] as? NSNumber {
                    spaces.append(id.uint64Value)
                }
            }
        }
        if !uuid.isEmpty && current != 0 && !spaces.isEmpty {
            result.append(ScreenSpaces(uuid: uuid, current: current, spaces: spaces))
        }
    }
    return result
}

func screenUnderMouse() -> ScreenSpaces? {
    let screens = allScreens()
    let mouse = CGEvent(source: nil)?.location ?? .zero
    let cid = SLSMainConnectionID()
    if let uuidRef = SLSCopyBestManagedDisplayForPoint(cid, mouse)?.takeRetainedValue() {
        let uuid = uuidRef as String
        if let match = screens.first(where: { $0.uuid == uuid }) {
            return match
        }
    }
    return screens.first
}

guard CommandLine.arguments.count == 2 else {
    fputs("usage: space-switch next|prev\n", stderr)
    exit(1)
}

let direction = CommandLine.arguments[1]
let step: Int
switch direction {
case "next": step = 1
case "prev": step = -1
default:
    fputs("usage: space-switch next|prev\n", stderr)
    exit(1)
}

guard let screen = screenUnderMouse() else { exit(1) }
guard screen.spaces.count > 1, let index = screen.spaces.firstIndex(of: screen.current) else {
    exit(2)
}

var nextIndex = index + step
if nextIndex >= screen.spaces.count { nextIndex = 0 }
if nextIndex < 0 { nextIndex = screen.spaces.count - 1 }
let target = screen.spaces[nextIndex]
if target == screen.current { exit(2) }

SLSManagedDisplaySetCurrentSpace(SLSMainConnectionID(), screen.uuid as CFString, target)
