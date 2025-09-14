//
//  VisualEffectBridge.swift
//  VisualEffectBridge
//
//  Created by DannyFeng on 2025/9/14.
//
//  Swift dynamic library (macOS Cocoa) for exposing NSVisualEffectView to C# via C-style exports.
//
//  Usage contract:
//   - handle = ve_create_and_attach(nsWindowPtr, x, y, w, h)
//   - call setters (ve_set_*...). These are safe to call from any thread (they dispatch to main).
//   - when done: ve_remove_and_release(handle)  <-- MUST call this exactly once to avoid leak.
//   - handle is an opaque pointer (UnsafeMutableRawPointer*)
//
//  Notes:
//   - All AppKit UI ops run on main thread.
//   - ve_create_and_attach uses Unmanaged.passRetained(holder) and returns that opaque pointer.
//   - ve_remove_and_release calls takeRetainedValue() and triggers holder deinit which removes observer and view.
//
//  Enum mappings (for the *_by_int functions):
//    material:
//      0 = sidebar
//      1 = windowBackground
//      2 = titlebar
//      3 = hudWindow
//      4 = contentBackground
//
//    blending:
//      0 = withinWindow
//      1 = behindWindow
//
//    state:
//      0 = active
//      1 = inactive
//      2 = followsWindowActiveState
//

import Foundation
import AppKit

// MARK: - Holder (NSObject to allow selector-based Notification observer)
final class VEHolder: NSObject {
    // NSVisualEffectView (main-thread-only)
    let ve: NSVisualEffectView
    // weak reference to NSWindow to avoid retain cycle
    weak var window: NSWindow?

    init(ve: NSVisualEffectView, window: NSWindow) {
        self.ve = ve
        self.window = window
        super.init()

        // Ensure VE fills contentView bounds initially
        if let cv = window.contentView {
            ve.frame = cv.bounds
        }

        // Register for window resize notifications using selector (no closure capture)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(windowDidResize(_:)),
                                               name: NSWindow.didResizeNotification,
                                               object: window)
    }

    // Selector called on main thread when window resizes
    @objc func windowDidResize(_ note: Notification) {
        // This runs on main runloop; update frame
        if let w = window, let cv = w.contentView {
            ve.frame = cv.bounds
        }
    }

    deinit {
        // Remove observer and remove view from superview.
        NotificationCenter.default.removeObserver(self)
        // Removing from superview must be on main thread
        if Thread.isMainThread {
            ve.removeFromSuperview()
        } else {
            DispatchQueue.main.async { [ve] in
                ve.removeFromSuperview()
            }
        }
    }
}

// MARK: - Helpers

fileprivate func materialFrom(_ v: Int32) -> NSVisualEffectView.Material {
    switch v {
    case 1: return .windowBackground
    case 2: return .titlebar
    case 3: return .hudWindow
    case 4: return .contentBackground
    default: return .sidebar
    }
}

fileprivate func blendingFrom(_ v: Int32) -> NSVisualEffectView.BlendingMode {
    switch v {
    case 1: return .behindWindow
    default: return .withinWindow
    }
}

fileprivate func stateFrom(_ v: Int32) -> NSVisualEffectView.State {
    switch v {
    case 1: return .inactive
    case 2: return .followsWindowActiveState
    default: return .active
    }
}

// Utility: convert opaque pointer to UInt (Sendable) and back
fileprivate func uintFromPtr(_ p: UnsafeMutableRawPointer?) -> UInt {
    return UInt(bitPattern: p ?? UnsafeMutableRawPointer(bitPattern: 0)!)
}
fileprivate func ptrFromUint(_ u: UInt) -> UnsafeMutableRawPointer? {
    return UnsafeMutableRawPointer(bitPattern: u)
}

// MARK: - Exported functions

// Create and attach an NSVisualEffectView. Returns an opaque retained pointer (VEHolder*).
@_cdecl("ve_create_and_attach")
public func ve_create_and_attach(nsWindowPtr: UnsafeMutableRawPointer?,
                                 x: Double, y: Double, w: Double, h: Double) -> UnsafeMutableRawPointer? {
    // Validate input pointer
    guard let nsWindowPtr = nsWindowPtr else { return nil }

    // Convert raw pointer to integer (Sendable) to pass into closure safely
    let windowKey = UInt(bitPattern: nsWindowPtr)

    // We'll collect the returned opaque pointer as a UInt (0 means nil)
    var outKey: UInt = 0

    // All AppKit operations must run on main thread
    DispatchQueue.main.sync {
        // Reconstruct pointer inside main thread (no data race)
        guard let windowRaw = ptrFromUint(windowKey) else { return }
        let window = Unmanaged<NSWindow>.fromOpaque(windowRaw).takeUnretainedValue()
        guard let contentView = window.contentView else { return }

        // Create visual effect view
        let frame = NSRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(w), height: CGFloat(h))
        let ve = NSVisualEffectView(frame: frame)
        ve.material = .sidebar
        ve.blendingMode = .withinWindow
        ve.state = .active
        ve.autoresizingMask = [.width, .height]
        ve.wantsLayer = false

        // attach
        contentView.addSubview(ve, positioned: .below, relativeTo: nil)

        // Wrap in VEHolder and retain it
        let holder = VEHolder(ve: ve, window: window)
        let opaque = Unmanaged.passRetained(holder).toOpaque()
        outKey = UInt(bitPattern: opaque)
    }

    // Convert back to pointer to return
    if outKey == 0 { return nil }
    return ptrFromUint(outKey)
}

// Create with material/blending/state set by ints (convenience)
@_cdecl("ve_create_and_attach_full")
public func ve_create_and_attach_full(nsWindowPtr: UnsafeMutableRawPointer?,
                                      x: Double, y: Double, w: Double, h: Double,
                                      materialInt: Int32, blendingInt: Int32, stateInt: Int32) -> UnsafeMutableRawPointer? {
    guard let nsWindowPtr = nsWindowPtr else { return nil }
    let windowKey = UInt(bitPattern: nsWindowPtr)
    var outKey: UInt = 0

    DispatchQueue.main.sync {
        guard let windowRaw = ptrFromUint(windowKey) else { return }
        let window = Unmanaged<NSWindow>.fromOpaque(windowRaw).takeUnretainedValue()
        guard let contentView = window.contentView else { return }

        let frame = NSRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(w), height: CGFloat(h))
        let ve = NSVisualEffectView(frame: frame)
        ve.material = materialFrom(materialInt)
        ve.blendingMode = blendingFrom(blendingInt)
        ve.state = stateFrom(stateInt)
        ve.autoresizingMask = [.width, .height]

        contentView.addSubview(ve, positioned: .below, relativeTo: nil)

        let holder = VEHolder(ve: ve, window: window)
        let opaque = Unmanaged.passRetained(holder).toOpaque()
        outKey = UInt(bitPattern: opaque)
    }

    if outKey == 0 { return nil }
    return ptrFromUint(outKey)
}

// Set frame explicitly (async; non-blocking)
@_cdecl("ve_set_frame")
public func ve_set_frame(holderPtr: UnsafeMutableRawPointer?, x: Double, y: Double, w: Double, h: Double) {
    // Convert pointer to UInt (Sendable)
    let key = uintFromPtr(holderPtr)
    DispatchQueue.main.async {
        guard let raw = ptrFromUint(key) else { return }
        let holder = Unmanaged<VEHolder>.fromOpaque(raw).takeUnretainedValue()
        holder.ve.frame = NSRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(w), height: CGFloat(h))
    }
}

@_cdecl("ve_set_autoresizing_sizeable")
public func ve_set_autoresizing_sizeable(holderPtr: UnsafeMutableRawPointer?) {
    let key = uintFromPtr(holderPtr)
    DispatchQueue.main.async {
        guard let raw = ptrFromUint(key) else { return }
        let holder = Unmanaged<VEHolder>.fromOpaque(raw).takeUnretainedValue()
        holder.ve.autoresizingMask = [.width, .height]
    }
}

@_cdecl("ve_set_alpha")
public func ve_set_alpha(holderPtr: UnsafeMutableRawPointer?, alpha: Double) {
    let key = uintFromPtr(holderPtr)
    let a = max(0.0, min(1.0, alpha))
    DispatchQueue.main.async {
        guard let raw = ptrFromUint(key) else { return }
        let holder = Unmanaged<VEHolder>.fromOpaque(raw).takeUnretainedValue()
        holder.ve.alphaValue = CGFloat(a)
    }
}

@_cdecl("ve_set_wants_layer")
public func ve_set_wants_layer(holderPtr: UnsafeMutableRawPointer?, wants: Bool) {
    let key = uintFromPtr(holderPtr)
    DispatchQueue.main.async {
        guard let raw = ptrFromUint(key) else { return }
        let holder = Unmanaged<VEHolder>.fromOpaque(raw).takeUnretainedValue()
        holder.ve.wantsLayer = wants
    }
}

@_cdecl("ve_set_layer_corner_radius")
public func ve_set_layer_corner_radius(holderPtr: UnsafeMutableRawPointer?, radius: Double) {
    let key = uintFromPtr(holderPtr)
    DispatchQueue.main.async {
        guard let raw = ptrFromUint(key) else { return }
        let holder = Unmanaged<VEHolder>.fromOpaque(raw).takeUnretainedValue()
        if holder.ve.wantsLayer, let layer = holder.ve.layer {
            layer.cornerRadius = CGFloat(radius)
            layer.masksToBounds = radius > 0
        }
    }
}

@_cdecl("ve_set_material_by_int")
public func ve_set_material_by_int(holderPtr: UnsafeMutableRawPointer?, materialInt: Int32) {
    let key = uintFromPtr(holderPtr)
    DispatchQueue.main.async {
        guard let raw = ptrFromUint(key) else { return }
        let holder = Unmanaged<VEHolder>.fromOpaque(raw).takeUnretainedValue()
        holder.ve.material = materialFrom(materialInt)
    }
}

@_cdecl("ve_set_blending_by_int")
public func ve_set_blending_by_int(holderPtr: UnsafeMutableRawPointer?, blendingInt: Int32) {
    let key = uintFromPtr(holderPtr)
    DispatchQueue.main.async {
        guard let raw = ptrFromUint(key) else { return }
        let holder = Unmanaged<VEHolder>.fromOpaque(raw).takeUnretainedValue()
        holder.ve.blendingMode = blendingFrom(blendingInt)
    }
}

@_cdecl("ve_set_state_by_int")
public func ve_set_state_by_int(holderPtr: UnsafeMutableRawPointer?, stateInt: Int32) {
    let key = uintFromPtr(holderPtr)
    DispatchQueue.main.async {
        guard let raw = ptrFromUint(key) else { return }
        let holder = Unmanaged<VEHolder>.fromOpaque(raw).takeUnretainedValue()
        holder.ve.state = stateFrom(stateInt)
    }
}

// Remove & release (MUST be called once per handle returned)
@_cdecl("ve_remove_and_release")
public func ve_remove_and_release(holderPtr: UnsafeMutableRawPointer?) {
    // Convert to UInt and synchronously release on main thread
    let key = uintFromPtr(holderPtr)
    DispatchQueue.main.sync {
        guard let raw = ptrFromUint(key) else { return }
        // takeRetainedValue matches passRetained above and triggers holder.deinit
        _ = Unmanaged<VEHolder>.fromOpaque(raw).takeRetainedValue()
    }
}

// Version string (pointer to static C string)
nonisolated(unsafe) private let _ve_version_cstr: UnsafePointer<CChar>? = {
    let s = "VE - Visual Effect Bridge Developer Alpha 0.0.1"
    return (s as NSString).utf8String
}()
@_cdecl("ve_get_version")
public func ve_get_version() -> UnsafePointer<CChar>? {
    return _ve_version_cstr
}
