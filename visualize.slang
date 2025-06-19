import swoosh;

static const uint SPLAT_COUNT = 4;

struct VisualizePC
{
    uint2 displaySize;
    float time;
};

#ifndef TARGET_CPU
[vk::binding(0)]
uniform Sampler2D<float4> targetImage;

[vk::binding(1)]
uniform RWTexture2D renderTarget;

[vk::binding(2)]
uniform RWStructuredBuffer<SwooshSplat> splatData;

[vk::binding(3)]
uniform RWStructuredBuffer<SwooshSplat> gradients;

[vk::push_constant]
uniform VisualizePC pc;

[Differentiable]
float4 alphaBlend(float4 bottom, float4 top)
{
    return float4(
        lerp(bottom.rgb, top.rgb, top.a),
        1.0 - (1.0 - top.a) * (1.0 - bottom.a)
    );
}

[Differentiable]
float loss(
    no_diff float2 p,
    no_diff float4 reference,
    SwooshSplat splats[SPLAT_COUNT]
){
    float4 color = float4(1);
    [ForceUnroll] for (int i = 0; i < SPLAT_COUNT; ++i)
    {
        float4 swoosh = swooshColor(p, splats[i]);
        color = alphaBlend(color, swoosh);
    }
    float3 delta = color.rgb - reference.rgb;
    return length(delta);
}

void nanFilter<T: __BuiltinFloatingPointType>(inout T weight)
{
    if (isnan(weight))
        weight = T(0.0);
}

void nanFilter<T: __BuiltinFloatingPointType, let N: int>(inout vector<T, N> weight)
{
    [ForceUnroll] for (int i = 0; i < N; ++i)
        weight[i] = isnan(weight[i]) ? T(0) : weight[i];
}

[shader("compute")]
[numthreads(8,8,1)]
void visualize(uint3 tid : SV_DispatchThreadID)
{
    if(any(tid.xy >= pc.displaySize.xy))
        return;

    float2 p = (float2(tid.xy) + 0.5f) / float2(pc.displaySize);
    p = p * 2.0 - 1.0;
    p.x *= float(pc.displaySize.x) / float(pc.displaySize.y);
    p.y = -p.y;

    p *= 1.1;

    float4 background = float4(1);
    float4 reference = pow(targetImage.SampleGrad(p*0.5+0.5, float(0), float2(0)), 2.2);
    reference = alphaBlend(background, reference);

    SwooshSplat splats[SPLAT_COUNT];
    float4 color = background;
    [ForceUnroll] for (int i = 0; i < SPLAT_COUNT; ++i)
    {
        splats[i] = splatData[i];
        float4 swoosh = swooshColor(p, splats[i]);
        color = alphaBlend(color, swoosh);
    }

    DifferentialPair<SwooshSplat[SPLAT_COUNT]> diffSplats = diffPair(splats);
    bwd_diff(loss)(p, reference, diffSplats, 1.0);

    [ForceUnroll] for (int i = 0; i < SPLAT_COUNT; ++i)
    {
        uint index = SPLAT_COUNT * (tid.x + tid.y * pc.displaySize.x) + i;

        SwooshSplat gradient = diffSplats.d[i];
        nanFilter(gradient.color);
        nanFilter(gradient.main.a);
        nanFilter(gradient.main.b);
        nanFilter(gradient.main.aniso);
        nanFilter(gradient.main.sharpness);
        nanFilter(gradient.cutout.a);
        nanFilter(gradient.cutout.b);
        nanFilter(gradient.cutout.aniso);
        nanFilter(gradient.cutout.sharpness);
        gradients[index] = gradient;
    }

    renderTarget[tid.xy] = color;
}
#endif
