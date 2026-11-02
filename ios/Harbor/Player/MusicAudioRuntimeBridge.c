#include "MusicAudioRuntimeBridge.h"

/* The two stable public libavfilter functions use no FFmpeg structures here. */
typedef struct AVFilter AVFilter;
extern unsigned avfilter_version(void);
extern const AVFilter *avfilter_get_by_name(const char *name);

uint32_t harbor_audio_filter_version(void) {
    return avfilter_version();
}
bool harbor_audio_filter_available(const char *name) {
    return name && *name && avfilter_get_by_name(name) != 0;
}
