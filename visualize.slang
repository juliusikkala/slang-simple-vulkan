struct visualize_pc
{
    uint2 displaySize;
};

#ifndef TARGET_CPU
[vk::binding(0)]
uniform Sampler2D<float4> targetImage;

[vk::binding(1)]
uniform RWTexture2D renderTarget;

[vk::push_constant]
uniform visualize_pc pc;

[shader("compute")]
[numthreads(8,8,1)]
void visualize(uint3 tid : SV_DispatchThreadID)
{
    if(any(tid.xy >= pc.displaySize.xy))
        return;
}
#endif
