//public struct SoftDisk : IDifferentiable
//{
//    public float2x2 transform;
//    public float2 position;
//};
//
public struct SoftDisk: IDifferentiable
{
    public float2 a;
    public float2 b;
    public float aniso;
    public float sharpness;
};

// This is kind of a "Lune", but both circles have an arbitrary 2D affine transform.
public struct SwooshSplat : IDifferentiable
{
    public float4 color;
    public SoftDisk main;
    public SoftDisk cutout;
};

[Differentiable]
public float softDiskCoverage(no_diff float2 p, SoftDisk sd)
{
    float2 center = (sd.a+sd.b) * 0.5;

    float2 centered = p - center;

    float2 delta = (sd.a-sd.b)*0.5;
    float w = dot(delta, delta);

    float2 xAxis = delta / w;
    float2 yAxis = float2(-xAxis.y, xAxis.x) * sd.aniso;

    float2 q = float2(
        dot(centered, xAxis),
        dot(centered, yAxis)
    );

    float d = dot(q, q);
    d = pow(d, 2.0 + sd.sharpness);
    return pow(0.5, d);
}

//[Differentiable]
//public float softDiskCoverage(no_diff float2 p, SoftDisk sd, float sharpness)
//{
//    float2 q = mul(p - sd.position, sd.transform);
//    float d = dot(q, q);
//    d = pow(d, 2.0 + abs(sharpness));
//    return pow(0.5, d);
//}

[Differentiable]
public float4 swooshColor(no_diff float2 p, SwooshSplat splat)
{
    float mainCoverage = softDiskCoverage(p, splat.main);
    float cutoutCoverage = softDiskCoverage(p, splat.cutout);
    float coverage = mainCoverage * (1.0-cutoutCoverage);
    return float4(splat.color.rgb, splat.color.a * coverage);
}

