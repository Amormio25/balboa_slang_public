[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float2 center,
                  uniform float radius,
                  uniform float3 color,
                  RWTexture2D<float4> image) {
    // LLM usage:
    // Model: ChatGPT, GPT-6
    // I used ChatGPT to help a lot with setting up balboa since running 1_1 wasn't working at first. I tried first understanding the error ("pass-through compiler not found" output and researching things like if it was due to my OS. I found out that it was because my macOS version (15 or 16 at the time) was too old and I needed XCode and its metal tools for compilation.

    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    image[tid] = float4(0.5, 0.5, 0.5, 1.0);
    // TODO: your code here

    // if thread's center is within center to radius color
    // float2 middle = tid.xy + float2(0.5, 0.5);
    // float distance = length(middle - center);

    // flip first
    float2 middle = float2(tid.x + 0.5, height - tid.y - 0.5);
    float distance = length(middle - center);

    if (distance < radius) {
        image[tid] = float4(color, 1.0);
    }
    
}
