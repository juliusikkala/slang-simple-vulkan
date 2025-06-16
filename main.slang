import gfx;
import window;
import memory;
import sdl2;
import vulkan;
import time;

export __extern_cpp int main(int argc, Ptr<NativeString> argv)
{
    Context ctx;
    ctx.init();
    Window win;
    win.open(ctx, "Simple Vulkan demo", int2(1280, 720), true);

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

    win.close(ctx);
    ctx.deinit();
    return 0;
}
