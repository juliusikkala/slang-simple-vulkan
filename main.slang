import gfx;
import window;
import memory;
import panic;
import sdl2;
import vulkan;
import string;
import time;

import visualize;

export __extern_cpp int main(int argc, Ptr<NativeString> argv)
{
    var ctx = Context();
    ctx.init();
    Window win;
    win.open(ctx, "Simple Vulkan demo", int2(1280, 720), true);

    var renderTex = Texture();
    renderTex.create(*win.dev, uint3(win.size, 1), VK_FORMAT_R8G8B8A8_UNORM);

    var fitTex = Texture();
    do
    {
        try fitTex.loadFromFile(*win.dev, "data/Slang_LogoBug.png");
    }
    catch
    {
        panic("Failed to load target image!\n");
    }
    VkSampler textureSampler = win.dev.createSampler(
        VK_FILTER_LINEAR,
        VK_FILTER_LINEAR,
        VK_SAMPLER_MIPMAP_MODE_NEAREST,
        VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
    );

    var render = SimpleComputePipeline();
    var path = U8String(ptrToString(SDL_GetBasePath()));
    path.append("visualize.slang.spv");
    do
    {
        try render.create(
            *win.dev,
            path.cStr,
            "visualize",
            sizeof(visualize_pc),
            uint[](),
            bindingSlot(0, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER),
            bindingSlot(1, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE)
        );
    }
    catch
    {
        panic("Failed to load shader!\n");
    }
    path.drop();

    mainloop:
    for (;;)
    {
        SDL_Event e;
        zeroInitialize(e);

        while (SDL_PollEvent(&e) != 0)
        {
            if(e.type == SDL_EventType.SDL_QUIT)
                break mainloop;
        }

        RenderTarget swapchain;
        VkCommandBuffer cmd = win.beginFrame(swapchain);

        TimeTicks t = getTicks();

        VkClearColorValue color;
        color.float32 = float[4](0.0f, 1.0f, 0.0f, 0.0f);
        var range = VkImageSubresourceRange(
            VK_IMAGE_ASPECT_COLOR_BIT,
            0, 1, 0, 1
        );
        vkCmdClearColorImage(cmd, swapchain.image, VK_IMAGE_LAYOUT_GENERAL, &color, 1, &range);
        
        win.endFrame(cmd);
    }

    render.drop(*win.dev);
    win.dev.release(textureSampler);
    renderTex.drop(*win.dev);
    fitTex.drop(*win.dev);
    win.close(ctx);
    ctx.deinit();
    return 0;
}
