Simple Vulkan example in Slang
==============================

# TODO REPLACE slang-cpu-utils REMOTE WITH https version!!!!

This example program is fully written in Slang. This means that in addition
to the shaders, the CPU code is also in Slang. The demo loads a compute shader
and displays a simple animation.

This is not a good example for learning Vulkan or programming shaders with
Slang; it's specifically a demo of using Slang on CPU.

For background on how this works, please read [slang-cpu-utils/README.md](https://github.com/juliusikkala/slang-cpu-utils/blob/main/README.md).

## Swoosh splatting

While Gaussian splatting has become a mainstay in the field of novel-view
synthesis and has demonstrated great usefulness as a representation format for
2D and 3D signals, the method struggles with certain kinds of data.

Particularly, sharp details such as claws, sickles and crescents are a poor fit
for gaussian splatting. Such details are particularly important in the logotypes
associated with the Khronos group[^1], nearly all of which include one or more
"Swoosh" shapes.

To alleviate this crucial shortcoming, we[^2] propose a novel representation
called Swoosh Splatting that is both differentiable and can preserve the sharp
details associated with swooshes. We demonstrate the suitability of our method
to Khronos logos by measuring its effectiveness with the
[Slang](https://shader-slang.org/) logo.[^3]

[^1]: This work is neither affiliated nor endorsed by the Khronos group.
[^2]: Actually it's just me.
[^3]: This only requires hours of tuning learning rates to rig our results.
