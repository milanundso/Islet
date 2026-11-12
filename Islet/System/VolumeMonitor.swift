import Foundation
import CoreAudio
import AudioToolbox

final class VolumeMonitor {
    var onChange: ((Float, Bool) -> Void)?

    private var observedDevice = AudioObjectID(kAudioObjectUnknown)
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?

    private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.attachToDefaultDevice()
        }
        defaultDeviceListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, DispatchQueue.main, listener)
        attachToDefaultDevice()
    }

    private func attachToDefaultDevice() {
        if let deviceListener, observedDevice != AudioObjectID(kAudioObjectUnknown) {
            AudioObjectRemovePropertyListenerBlock(observedDevice, &volumeAddress, DispatchQueue.main, deviceListener)
            AudioObjectRemovePropertyListenerBlock(observedDevice, &muteAddress, DispatchQueue.main, deviceListener)
        }
        var device = AudioObjectID(kAudioObjectUnknown)
        var deviceSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, 0, nil, &deviceSize, &device)
        guard status == noErr else { return }
        observedDevice = device
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.report()
        }
        deviceListener = listener
        AudioObjectAddPropertyListenerBlock(device, &volumeAddress, DispatchQueue.main, listener)
        AudioObjectAddPropertyListenerBlock(device, &muteAddress, DispatchQueue.main, listener)
    }

    private func report() {
        var volume = Float32(0)
        var volumeSize = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(observedDevice, &volumeAddress, 0, nil, &volumeSize, &volume)
        var muted = UInt32(0)
        var mutedSize = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(observedDevice, &muteAddress, 0, nil, &mutedSize, &muted)
        onChange?(volume, muted != 0)
    }
}
