import swoosh;

struct GatherPC
{
    int valueCount;
    int splatCount;
    int stride;
    int offset;
};

#ifndef TARGET_CPU
[vk::binding(0)]
uniform RWStructuredBuffer<SwooshSplat> gradients;

[vk::push_constant]
uniform GatherPC pc;

[shader("compute")]
[numthreads(256,1,1)]
void gather(uint3 tid : SV_DispatchThreadID)
{
    int splatIndex = tid.x % pc.splatCount;
    int groupIndex = tid.x / pc.splatCount;

    int i = groupIndex * pc.splatCount * pc.stride + splatIndex;
    int j = i + pc.offset * pc.splatCount;
    if (i < pc.valueCount && j < pc.valueCount)
    {
        SwooshSplat a = gradients[i];
        SwooshSplat b = gradients[j];

        a.color += b.color;
        a.main.a += b.main.a;
        a.main.b += b.main.b;
        a.main.aniso += b.main.aniso;
        a.main.sharpness += b.main.sharpness;
        a.cutout.a += b.cutout.a;
        a.cutout.b += b.cutout.b;
        a.cutout.aniso += b.cutout.aniso;
        a.cutout.sharpness += b.cutout.sharpness;

        gradients[i] = a;
    }
}
#endif
