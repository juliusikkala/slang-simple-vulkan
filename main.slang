import gfx;
import window;
import memory;
import panic;
import sdl2;
import vulkan;
import string;
import time;
import render;

int system(NativeString command)
{
    __intrinsic_asm "system($0)";
}

export __extern_cpp int main(int argc, Ptr<NativeString> argv)
{
    var ctx = Context();
    ctx.init();
    Window win;
    win.open(ctx, "Slang-on-Vulkan-on-Slang demo", int2(1280, 720), true);

    var renderer = Renderer();

    renderer.reset(*win.dev, win.size);

    var begin = getTicks();

    mainloop:
    for (;;)
    {
        var end = getTicks();
        var delta = end-begin;
        if(delta.milliseconds < 16.0)
            sleep(double(1.0/60.0) - delta.seconds);
        begin = end;

        SDL_Event e;
        zeroInitialize(e);

        while (SDL_PollEvent(&e) != 0)
        {
            if(e.type == SDL_EventType.SDL_QUIT)
                break mainloop;
            if(e.type == SDL_EventType.SDL_KEYDOWN)
            {
                switch(SDL_KeyCode(e.key.keysym.sym))
                {
                case SDLK_F5:
                    printf("Resetting renderer!\n");
                    system("cmake --build build --target shaders");
                    renderer.reset(*win.dev, win.size);
                    break;
                default:
                    break;
                }
            }
        }

        RenderTarget swapchain;
        VkCommandBuffer cmd = win.beginFrame(swapchain);

        renderer.render(*win.dev, cmd, swapchain, float(delta.seconds));

        win.endFrame(cmd);
    }

    renderer.drop(*win.dev);
    win.close(ctx);
    ctx.deinit();
    return 0;
}
