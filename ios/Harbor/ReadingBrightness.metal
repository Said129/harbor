#include <metal_stdlib>
using namespace metal;

[[ stitchable ]] half4 harborReadingBrightness(float2 position, half4 color, float amount) {
    (void)position;
    return half4(color.rgb * half(amount), color.a);
}
