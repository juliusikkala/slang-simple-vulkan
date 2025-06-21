import sdl2;
import vulkan;
import memory;
import gfx;
import panic;
import drop;
import list;

public struct Window
{
    public static const int IN_FLIGHT_FRAMES = 2;

    private SDL_Window* win = nullptr;
    public Device* dev = nullptr;

    private VkSurfaceKHR surface = nullptr;
    private VkSurfaceFormatKHR surfaceFormat = VkSurfaceFormatKHR(VK_FORMAT_UNDEFINED, VK_COLOR_SPACE_SRGB_NONLINEAR_KHR);
    private VkPresentModeKHR presentMode = VK_PRESENT_MODE_IMMEDIATE_KHR;
    private VkSwapchainKHR swapchain = nullptr;
    private List<VkImage> swapchainImages;
    private List<VkImageView> swapchainImageViews;
    private VkFence frameFences[IN_FLIGHT_FRAMES] = {};
    private List<VkSemaphore> frameStartSemaphores = {};
    private List<VkSemaphore> frameEndSemaphores = {};
    private uint64_t frameTimeline = 0;
    private bool vsync = false;
    private uint32_t swapchainImageIndex = 0;
    public int2 swapchainSize = int2(0,0);

    public __init() { }

    public property int2 size {
        get {
            int2 size = int2(0,0);
            if(win != nullptr)
                SDL_GetWindowSize(win, &size.x, &size.y);
            return size;
        }
    }

    [mutating]
    public void open(inout Context ctx, String title, int2 size, bool vsync)
    {
        win = SDL_CreateWindow(
            title,
            SDL_WINDOWPOS_UNDEFINED_MASK,
            SDL_WINDOWPOS_UNDEFINED_MASK,
            size.x, size.y,
            uint(SDL_WINDOW_SHOWN|SDL_WINDOW_VULKAN)
        );
        if(!win)
            panic("%s\n", SDL_GetError());

        SDL_GetWindowSize(win, &size.x, &size.y);

        if(!SDL_Vulkan_CreateSurface(win, ctx.vulkanInstance, &surface))
            panic("%s\n", SDL_GetError());

        for(int i = 0; i < ctx.devices.size; ++i)
        {
            Device* d = &ctx.devices.data[i];
            if(d.findCompatibleQueue(surface) >= 0)
            {
                this.dev = d;
                this.dev.open(ctx, surface);
                break;
            }
        }

        if(this.dev == nullptr)
        {
            panic("Failed to find a suitable Vulkan device!");
        }

        this.vsync = vsync;
        frameTimeline = 0; 

        initSwapchain();
    }

    public void grab(bool e)
    {
        SDL_SetWindowGrab(win, e ? SDL_TRUE : SDL_FALSE);
        SDL_SetRelativeMouseMode(e ? SDL_TRUE : SDL_FALSE);
    }

    [mutating]
    public void close(inout Context ctx)
    {
        deinitSwapchain();
        if(this.dev)
            this.dev.close();
        this.dev = nullptr;
        if(surface)
            vkDestroySurfaceKHR(ctx.vulkanInstance, surface, nullptr);
        surface = nullptr;
        if(win)
            SDL_DestroyWindow(win);
        win = nullptr;
    }

    [mutating]
    public VkCommandBuffer beginFrame(out RenderTarget target)
    {
        bool success = false;
        size_t inFlightIndex = size_t(frameTimeline%IN_FLIGHT_FRAMES);
        for(;;)
        {
            VkFence fence = frameFences[inFlightIndex];
            vkWaitForFences(dev.logicalDevice, 1, &fence, VK_TRUE, uint64_t.maxValue-1);
            vkResetFences(dev.logicalDevice, 1, &fence);

            VkResult res = vkAcquireNextImageKHR(
                dev.logicalDevice, swapchain, uint64_t.maxValue-1,
                frameStartSemaphores[int(frameTimeline%frameStartSemaphores.size)],
                nullptr, &swapchainImageIndex
            );
            if(res == VK_ERROR_OUT_OF_DATE_KHR || res == VK_SUBOPTIMAL_KHR)
            {
                deinitSwapchain();
                initSwapchain();
            }
            else break;
        }

        dev.stagingFrame();
        target.image = swapchainImages[swapchainImageIndex];
        target.view = swapchainImageViews[swapchainImageIndex];
        target.format = surfaceFormat.format;
        target.size = swapchainSize;

        VkCommandBuffer cmd = dev.beginCommandBuffer();
        dev.pumpTimestampQueries(cmd);

        imageMemoryBarrier(cmd, target.image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_GENERAL);
        return cmd;
    }

    [mutating]
    public void endFrame(VkCommandBuffer cmd)
    {
        imageMemoryBarrier(
            cmd, swapchainImages[swapchainImageIndex],
            VK_IMAGE_LAYOUT_GENERAL, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
        );
        vkEndCommandBuffer(cmd);

        var waitInfo = VkSemaphoreSubmitInfo(
            VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
            nullptr,
            frameStartSemaphores[int(frameTimeline%frameStartSemaphores.size)],
            0, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, 0
        );
        var cmdInfo = VkCommandBufferSubmitInfo(
            VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
            nullptr,
            cmd,
            0
        );
        var signalInfo = VkSemaphoreSubmitInfo(
            VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
            nullptr,
            frameEndSemaphores[swapchainImageIndex],
            0, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, 0
        );
        var submitInfo = VkSubmitInfo2KHR(
            VK_STRUCTURE_TYPE_SUBMIT_INFO_2_KHR,
            nullptr,
            0,
            1, &waitInfo,
            1, &cmdInfo,
            1, &signalInfo
        );

        size_t inFlightIndex = size_t(frameTimeline%IN_FLIGHT_FRAMES);
        VkFence fence = frameFences[inFlightIndex];
        vkQueueSubmit2(dev.queue, 1, &submitInfo, fence);
        dev.release(cmd);

        VkSemaphore end = frameEndSemaphores[swapchainImageIndex];
        var presentInfo = VkPresentInfoKHR(
            VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            nullptr,
            1, &end,
            1, &swapchain,
            &swapchainImageIndex,
            nullptr
        );

        VkResult res = vkQueuePresentKHR(dev.queue, &presentInfo);
        if(res == VK_SUBOPTIMAL_KHR || res == VK_ERROR_OUT_OF_DATE_KHR)
        {
            deinitSwapchain();
            initSwapchain();
        }

        frameTimeline++;
    }

    [mutating]
    private void initSwapchain()
    {
        uint formatCount = 0;
        vkGetPhysicalDeviceSurfaceFormatsKHR(dev.physicalDevice, surface, &formatCount, nullptr);
        List<VkSurfaceFormatKHR> formats;
        defer formats.drop();
        formats.resize(formatCount);
        vkGetPhysicalDeviceSurfaceFormatsKHR(dev.physicalDevice, surface, &formatCount, formats.data);

        surfaceFormat = formats[0];
        for(uint i = 0; i < formatCount; ++i)
        {
            VkSurfaceFormatKHR format = formats[i];
            if(
                (format.format == VK_FORMAT_B8G8R8A8_SRGB ||
                format.format == VK_FORMAT_R8G8B8A8_SRGB) &&
                format.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR
            ){
                surfaceFormat = format;
                break;
            }
        }

        // Find presentation mode based on settings.
        uint32_t modeCount = 0;
        vkGetPhysicalDeviceSurfacePresentModesKHR(dev.physicalDevice, surface, &modeCount, nullptr);
        List<VkPresentModeKHR> modes;
        defer modes.drop();
        modes.resize(modeCount);
        vkGetPhysicalDeviceSurfacePresentModesKHR(dev.physicalDevice, surface, &modeCount, modes.data);

        presentMode = VK_PRESENT_MODE_FIFO_KHR;
        for(uint i = 0; i < modeCount; ++i)
        {
            VkPresentModeKHR mode = modes[i];
            if(
                (vsync && mode == VK_PRESENT_MODE_MAILBOX_KHR) ||
                (!vsync && mode == VK_PRESENT_MODE_IMMEDIATE_KHR)
            ){
                presentMode = mode;
                break;
            }
        }

        // Get surface params
        VkSurfaceCapabilitiesKHR surfaceCapabilities;
        zeroInitialize(surfaceCapabilities);
        vkGetPhysicalDeviceSurfaceCapabilitiesKHR(dev.physicalDevice, surface, &surfaceCapabilities);

        // Calculate available swapchain size
        swapchainSize.x = clamp(
            size.x,
            surfaceCapabilities.minImageExtent.width,
            surfaceCapabilities.maxImageExtent.width
        );
        swapchainSize.y = clamp(
            size.y,
            surfaceCapabilities.minImageExtent.height,
            surfaceCapabilities.maxImageExtent.height
        );

        uint swapchainImageCount = max(
            IN_FLIGHT_FRAMES,
            surfaceCapabilities.minImageCount
        );
        if(surfaceCapabilities.maxImageCount != 0)
            swapchainImageCount = min(swapchainImageCount, surfaceCapabilities.maxImageCount);

        // Create the swapchain.
        uint queueIndex = dev.findCompatibleQueue(surface);
        VkSwapchainCreateInfoKHR createInfo = VkSwapchainCreateInfoKHR(
            VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            nullptr,
            0,
            surface,
            swapchainImageCount,
            surfaceFormat.format,
            surfaceFormat.colorSpace,
            VkExtent2D(swapchainSize.x, swapchainSize.y),
            1,
            uint(VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT|VK_IMAGE_USAGE_TRANSFER_DST_BIT),
            VK_SHARING_MODE_EXCLUSIVE,
            1,
            &queueIndex,
            VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR,
            VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            presentMode,
            VK_TRUE,
            nullptr
        );

        if((surfaceCapabilities.supportedCompositeAlpha & VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR) == 0)
            createInfo.compositeAlpha = (VkCompositeAlphaFlagBitsKHR)(surfaceCapabilities.supportedCompositeAlpha&-surfaceCapabilities.supportedCompositeAlpha);

        vkCreateSwapchainKHR(dev.logicalDevice, &createInfo, nullptr, &swapchain);

        // Get swapchain images
        vkGetSwapchainImagesKHR(dev.logicalDevice, swapchain, &swapchainImageCount, nullptr);
        swapchainImages.resize(swapchainImageCount);
        vkGetSwapchainImagesKHR(dev.logicalDevice, swapchain, &swapchainImageCount, swapchainImages.data);
        swapchainImageViews.resize(swapchainImageCount);
        frameStartSemaphores.resize(swapchainImageCount);
        frameEndSemaphores.resize(swapchainImageCount);

        for(int i = 0; i < swapchainImageCount; ++i)
        {
            VkImageView view = nullptr;
            var viewInfo = VkImageViewCreateInfo(
                VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                nullptr,
                0,
                swapchainImages[i],
                VK_IMAGE_VIEW_TYPE_2D,
                surfaceFormat.format,
                VkComponentMapping(
                    VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY,
                    VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY
                ),
                VkImageSubresourceRange(
                    uint(VK_IMAGE_ASPECT_COLOR_BIT),
                    0, 1, 0, 1
                )
            );
            vkCreateImageView(dev.logicalDevice, &viewInfo, nullptr, &view);
            swapchainImageViews[i] = view;

            VkSemaphore sem;
            var semInfo = VkSemaphoreCreateInfo(
                VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
                nullptr,
                0
            );
            vkCreateSemaphore(dev.logicalDevice, &semInfo, nullptr, &sem);
            frameStartSemaphores[i] = sem;
            vkCreateSemaphore(dev.logicalDevice, &semInfo, nullptr, &sem);
            frameEndSemaphores[i] = sem;
        }

        for(int i = 0; i < IN_FLIGHT_FRAMES; ++i)
        {
            VkFence fence;
            var fenceInfo = VkFenceCreateInfo(
                VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
                nullptr,
                uint(VK_FENCE_CREATE_SIGNALED_BIT)
            );
            vkCreateFence(dev.logicalDevice, &fenceInfo, nullptr, &fence);
            frameFences[i] = fence;
        }
    }

    [mutating]
    private void deinitSwapchain()
    {
        vkDeviceWaitIdle(dev.logicalDevice);
        vkWaitForFences(dev.logicalDevice, IN_FLIGHT_FRAMES, &frameFences[0], VK_TRUE, uint64_t.maxValue-1);
        for(int i = 0; i < swapchainImageViews.size; ++i)
        {
            vkDestroyImageView(dev.logicalDevice, swapchainImageViews[i], nullptr);
            vkDestroySemaphore(dev.logicalDevice, frameStartSemaphores[i], nullptr);
            vkDestroySemaphore(dev.logicalDevice, frameEndSemaphores[i], nullptr);
        }
        for(int i = 0; i < IN_FLIGHT_FRAMES; ++i)
        {
            vkDestroyFence(dev.logicalDevice, frameFences[i], nullptr);
        }
        swapchainImages.drop();
        swapchainImageViews.drop();
        frameStartSemaphores.drop();
        frameEndSemaphores.drop();

        vkDestroySwapchainKHR(dev.logicalDevice, swapchain, nullptr);
        swapchain = nullptr;
    }
};
