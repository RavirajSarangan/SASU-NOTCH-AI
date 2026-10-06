import CoreAudio
import CoreMediaIO
import Foundation

/// CoreAudio and CoreMediaIO deliver device notifications on a run loop,
/// which by default is the thread that first calls them. If that is the
/// main thread, they take it over and Nova's main queue stops being served:
/// timers, `await`s on the main actor and UI loading all freeze. Tell both
/// frameworks to use their own threads, and query devices on `queue`.
enum HardwareRunLoops {
    static let queue = DispatchQueue(label: "nova.devices", qos: .utility)

    /// Call once at launch, before any device query.
    static func configure() {
        var runLoop: CFRunLoop? = nil
        var audio = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyRunLoop,
                                               mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        _ = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &audio, 0, nil,
                                       UInt32(MemoryLayout<CFRunLoop?>.size), &runLoop)
        // kCMIOHardwarePropertyRunLoop isn't exported to Swift; it shares CoreAudio's code, 'rnlp'.
        var video = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kAudioHardwarePropertyRunLoop),
                                              mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                              mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        _ = CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &video, 0, nil,
                                      UInt32(MemoryLayout<CFRunLoop?>.size), &runLoop)
    }
}
