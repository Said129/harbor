/* A real, clocked CoreAudio endpoint for the isolated macOS simulator host.
 * This executable is never linked or copied into Harbor. */
#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static AudioObjectPropertyAddress global_address(AudioObjectPropertySelector selector) {
    AudioObjectPropertyAddress address = {
        selector, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    return address;
}

int main(void) {
    const char *ci = getenv("GITHUB_ACTIONS");
    if (ci == NULL || strcmp(ci, "true") != 0) return 2;
    AudioObjectPropertyAddress list = global_address(kAudioHardwarePropertyDevices);
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &list, 0, NULL, &size) != noErr ||
        size == 0 || size > 4096 * sizeof(AudioDeviceID)) return 3;
    AudioDeviceID *devices = malloc(size);
    if (devices == NULL) return 4;
    OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &list, 0, NULL, &size, devices);
    AudioDeviceID selected = kAudioObjectUnknown;
    if (status == noErr) {
        for (UInt32 i = 0; i < size / sizeof(AudioDeviceID); ++i) {
            CFStringRef name = NULL;
            UInt32 bytes = sizeof(name);
            AudioObjectPropertyAddress property = global_address(kAudioObjectPropertyName);
            if (AudioObjectGetPropertyData(devices[i], &property, 0, NULL, &bytes, &name) == noErr && name != NULL) {
                if (CFEqual(name, CFSTR("BlackHole 2ch"))) selected = devices[i];
                CFRelease(name);
            }
        }
    }
    free(devices);
    if (selected == kAudioObjectUnknown) return 5;
    Float64 rate = 48000;
    AudioObjectPropertyAddress sample_rate = global_address(kAudioDevicePropertyNominalSampleRate);
    if (AudioObjectSetPropertyData(selected, &sample_rate, 0, NULL, sizeof(rate), &rate) != noErr) return 6;
    AudioObjectPropertySelector defaults[] = {
        kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice,
        kAudioHardwarePropertyDefaultInputDevice
    };
    for (size_t i = 0; i < sizeof(defaults) / sizeof(defaults[0]); ++i) {
        AudioObjectPropertyAddress property = global_address(defaults[i]);
        if (AudioObjectSetPropertyData(kAudioObjectSystemObject, &property, 0, NULL, sizeof(selected), &selected) != noErr) return 7;
        AudioDeviceID actual = kAudioObjectUnknown;
        UInt32 bytes = sizeof(actual);
        if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &property, 0, NULL, &bytes, &actual) != noErr || actual != selected) return 8;
    }
    UInt32 bytes = sizeof(rate);
    if (AudioObjectGetPropertyData(selected, &sample_rate, 0, NULL, &bytes, &rate) != noErr ||
        !isfinite(rate) || fabs(rate - 48000) > 1) return 9;
    UInt32 alive = 0;
    bytes = sizeof(alive);
    AudioObjectPropertyAddress active = global_address(kAudioDevicePropertyDeviceIsAlive);
    if (AudioObjectGetPropertyData(selected, &active, 0, NULL, &bytes, &alive) != noErr || alive == 0) return 10;
    printf("{\"device\":\"BlackHole 2ch\",\"sampleRate\":%.0f,\"alive\":true}\n", rate);
    return 0;
}
