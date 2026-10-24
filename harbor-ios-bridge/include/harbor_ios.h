#ifndef HARBOR_IOS_H
#define HARBOR_IOS_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* ABI 1: UTF-8 request, max 8 MiB. No embedded application state. */
uint32_t harbor_ios_abi_version(void);
/* Readable input lives for this call. Returned JSON must be freed exactly once. */
char *harbor_ios_call(const uint8_t *input, size_t length);
void harbor_ios_response_free(char *response);
/* Local WOFF/WOFF2 input <=32 MiB; expanded font <=128 MiB. No JSON/network.
 * Input remains readable during the call. output_length is writable and cannot
 * alias input. A returned slice is owned and must be freed once with that length. */
uint8_t *harbor_ios_font_decode(const uint8_t *input, size_t length, size_t *output_length);
void harbor_ios_font_free(uint8_t *data, size_t length);
/* Network ABI 1 is separate; existing pure calls remain synchronous and unchanged.
 * A nonzero handle promises one callback on a background thread, including cancellation.
 * Zero means no callback; the caller retains context. Input is copied before return.
 * Callback JSON is borrowed only during the callback: copy it, never free it. */
typedef void (*harbor_ios_network_callback)(void *context, const uint8_t *response, size_t length);
uint32_t harbor_ios_network_abi_version(void);
uint64_t harbor_ios_network_start(const uint8_t *input, size_t length, void *context, harbor_ios_network_callback callback);
/* Typed public Music catalog operations; same callback and cancellation contract. */
uint64_t harbor_ios_music_start(const uint8_t *input, size_t length, void *context, harbor_ios_network_callback callback);
void harbor_ios_network_cancel(uint64_t handle);
#ifdef __cplusplus
}
#endif
#endif
