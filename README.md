Simple Vulkan sample in Slang
==============================

This repo uses submodules, so clone with `--recursive`.

This sample program is fully written in Slang. This means that in addition
to the shaders, the CPU code is also in Slang. The demo loads a compute shader
and displays a simple animation.

This is not a good example for learning Vulkan or programming shaders with
Slang; it's specifically a demo of using Slang on CPU.

For background on how this works, please read [slang-cpu-utils/README.md](https://github.com/juliusikkala/slang-cpu-utils/blob/main/README.md).

## Building

Note that this demo, like [slang-cpu-utils](https://github.com/juliusikkala/slang-cpu-utils/),
depends on the latest available Slang compiler. You'll need to get the
[latest release from GitHub](https://github.com/shader-slang/slang), the version
in the Vulkan SDK is generally too old.

### Linux

You'll need to install cmake, python, libclang, sdl2 and vulkan from your
distro's repositories. If you have installed Slang system-wide:

```sh
cmake -S . -B build
cmake --build build
```

If not, you'll need to provide the path to the Slang compiler with
`cmake -S . -B build -DCMAKE_Slang_COMPILER=/path/to/slangc`.

The executable should then be `build/demo`.

### Windows

1. Install [CMake](https://cmake.org), [Ninja](https://ninja-build.org), [Visual Studio 2022](https://visualstudio.microsoft.com/vs/) (Community edition is fine, we just need the MSVC compiler from this), [Python](https://www.python.org/), [LLVM](https://releases.llvm.org/) and [VCPKG](https://vcpkg.io/en/).
2. [Create the `CMakeUserPresets.json` as described here](https://learn.microsoft.com/en-us/vcpkg/get_started/get-started?pivots=shell-powershell#4---build-and-run-the-project)
3. Open "x64 Native Tools Command Prompt for VS 2022" from the Windows start menu
4. Navigate to the root of this repository.
5. Run `cmake -S . -B build --preset=default` 
    - If this doesn't find the Slang compiler, you should give CMake the path to it, so `cmake -S . -B build --preset=default -DCMAKE_Slang_COMPILER=C:/path/to/your/slang/bin/slangc`.
6. Run `cmake --build build`
    - If you see a bunch of errors from Slang, it's likely that an old version of Slang was found (e.g. the version that comes with Vulkan SDK). Go back to step 4 and define the path to your newer build.

The executable should then be `build\demo.exe`.

In case you're curious; LLVM is only needed for generating bindings to C
libraries like Vulkan & SDL.

## Swoosh splatting

While Gaussian splatting has become a mainstay in the field of novel-view
synthesis and has demonstrated great usefulness as a representation format for
2D and 3D signals, the method struggles with certain kinds of data.

Particularly, sharp details such as claws, sickles and crescents are a poor fit
for gaussian splatting. Such details are particularly important in the logotypes
associated with the Khronos group[^1], nearly all of which include one or more
"Swoosh" shapes.

To alleviate this crucial shortcoming, we[^2] propose a novel representation
called "Swoosh Splatting". It is both differentiable and can preserve the sharp
details associated with swooshes. We demonstrate the suitability of our method
to Khronos logos by measuring its effectiveness with the
[Slang](https://shader-slang.org/) logo.[^3]

[^1]: This work is neither affiliated with nor endorsed by the Khronos group.
[^2]: Actually it's just me.
[^3]: This only requires hours of tuning learning rates to rig our results.
