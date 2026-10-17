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
#ifdef __cplusplus
}
#endif
#endif
