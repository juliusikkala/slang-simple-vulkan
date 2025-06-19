import swoosh;

struct UpdatePC
{
    int splatCount;
    uint iters;
    float lr;
};

#ifndef TARGET_CPU
[vk::binding(0)]
uniform RWStructuredBuffer<SwooshSplat> splats;

[vk::binding(1)]
uniform RWStructuredBuffer<SwooshSplat> gradients;

[vk::binding(2)]
uniform RWStructuredBuffer<SwooshSplat> moments;

[vk::push_constant]
uniform UpdatePC pc;

static const float ADAM_ALPHA = 0.001;
static const float ADAM_BETA1 = 0.9;
static const float ADAM_BETA2 = 0.999;
static const float ADAM_EPSILON = 1e-7;

void adam<T: __BuiltinFloatingPointType>(
    inout T weight,
    inout T m1,
    inout T m2,
    T gradient,
    float alpha = ADAM_ALPHA
){
    m1 = gradient * T(1.0 - ADAM_BETA1) + m1 * T(ADAM_BETA1);
    m2 = gradient * gradient * T(1.0 - ADAM_BETA2) + m2 * T(ADAM_BETA2);

    let m1Hat = m1/T(1.0-pow(ADAM_BETA1, 1+pc.iters));
    let m2Hat = m2/T(1.0-pow(ADAM_BETA2, 1+pc.iters));

    weight -= T(alpha) * m1Hat / (sqrt(m2Hat) + T(ADAM_EPSILON));
}

void adam<T: __BuiltinFloatingPointType, let N: int>(
    inout vector<T, N> weight,
    inout vector<T, N> m1,
    inout vector<T, N> m2,
    vector<T, N> gradient,
    float alpha = ADAM_ALPHA
){
    m1 = gradient * T(1.0 - ADAM_BETA1) + m1 * T(ADAM_BETA1);
    m2 = gradient * gradient * T(1.0 - ADAM_BETA2) + m2 * T(ADAM_BETA2);

    let m1Hat = m1/T(1.0-pow(ADAM_BETA1, 1+pc.iters));
    let m2Hat = m2/T(1.0-pow(ADAM_BETA2, 1+pc.iters));

    weight -= T(alpha) * m1Hat / (sqrt(m2Hat) + T(ADAM_EPSILON));
}

[shader("compute")]
[numthreads(32,1,1)]
void update(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= pc.splatCount)
        return;

    SwooshSplat splat = splats[tid.x];
    SwooshSplat gradient = gradients[tid.x];
    SwooshSplat m1 = moments[2*tid.x];
    SwooshSplat m2 = moments[2*tid.x+1];

    float lr = pc.lr;

    adam(splat.color, m1.color, m2.color, gradient.color * lr, 0.003);
    adam(splat.main.a, m1.main.a, m2.main.a, gradient.main.a * lr);
    adam(splat.main.b, m1.main.b, m2.main.b, gradient.main.b * lr);
    adam(splat.main.aniso, m1.main.aniso, m2.main.aniso, gradient.main.aniso * lr, 0.004);
    adam(splat.main.sharpness, m1.main.sharpness, m2.main.sharpness, gradient.main.sharpness * lr, 0.005);
    adam(splat.cutout.a, m1.cutout.a, m2.cutout.a, gradient.cutout.a * lr, 0.004);
    adam(splat.cutout.b, m1.cutout.b, m2.cutout.b, gradient.cutout.b * lr, 0.004);
    adam(splat.cutout.aniso, m1.cutout.aniso, m2.cutout.aniso, gradient.cutout.aniso * lr, 0.004);
    adam(splat.cutout.sharpness, m1.cutout.sharpness, m2.cutout.sharpness, gradient.cutout.sharpness * lr, 0.005);

    splat.color = clamp(splat.color, float4(0), float4(1));

    splats[tid.x] = splat;
    moments[2*tid.x] = m1;
    moments[2*tid.x+1] = m2;
}
#endif
