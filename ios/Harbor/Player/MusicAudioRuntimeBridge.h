#ifndef HARBOR_MUSIC_AUDIO_RUNTIME_BRIDGE_H
#define HARBOR_MUSIC_AUDIO_RUNTIME_BRIDGE_H
#include <stdbool.h>
#include <stdint.h>

uint32_t harbor_audio_filter_version(void);
bool harbor_audio_filter_available(const char *name);
#endif
