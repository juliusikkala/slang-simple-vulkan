import sdl2;
import memory;
import vulkan;
import vulkanmemoryallocator;
import panic;
import drop;
import platform;
import list;
import string;
import io;
import stb_image;

#define VK_MAKE_API_VERSION(variant, major, minor, patch) \
    ((((uint32_t)(variant)) << 29U) | (((uint32_t)(major)) << 22U) | (((uint32_t)(minor)) << 12U) | ((uint32_t)(patch)))
#define VK_API_VERSION_1_3 VK_MAKE_API_VERSION(0, 1, 3, 0)

__extern_cpp void load_vk_extensions(VkInstance instance);

export __extern_cpp VkBool32 debugCallback(
    VkDebugUtilsMessageSeverityFlagBitsEXT severity,
    VkDebugUtilsMessageTypeFlagsEXT,
    VkDebugUtilsMessengerCallbackDataEXT* data,
    void*
) {
    if(severity == 0) return false;

    if((severity&VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT) != 0)
    {
        panic("%s\n", data->pMessage);
    }
    else
    {
        printf("%s\n", data->pMessage);
    }
    return false;
}

[ForceInline]
void* getDebugCallbackPtr()
{
    // We have to call this manually here so that the function appears in the
    // generated source before we use it.
    debugCallback(VkDebugUtilsMessageSeverityFlagBitsEXT(0), 0, nullptr, nullptr);
    __intrinsic_asm "((void*)&debugCallback)";
}

public struct Context
{
    public VkInstance vulkanInstance;
    public List<NativeString> extensions;
    public List<NativeString> validationLayers;
    public List<Device> devices;

    VkDebugUtilsMessengerEXT debugMessenger;

    public __init() {}

    [mutating]
    public void init()
    {
        // Init SDL
        if(SDL_Init(SDL_INIT_VIDEO|SDL_INIT_TIMER|SDL_INIT_EVENTS) != 0)
        {
            panic("SDL initialization failed: %s\n", SDL_GetError());
        }

        SDL_Vulkan_LoadLibrary(ptrToString(Ptr<void>(nullptr)));

        // Init Vulkan
        uint count = 0;
        if(!SDL_Vulkan_GetInstanceExtensions(nullptr, &count, nullptr))
            panic("SDL_Vulkan_GetInstanceExtensions: %s\n", SDL_GetError());

        extensions.resize(count);
        if(!SDL_Vulkan_GetInstanceExtensions(nullptr, &count, extensions.data))
            panic("SDL_Vulkan_GetInstanceExtensions: %s\n", SDL_GetError());

        extensions.push(VK_EXT_DEBUG_UTILS_EXTENSION_NAME);

        VkApplicationInfo appInfo = VkApplicationInfo(
            VK_STRUCTURE_TYPE_APPLICATION_INFO,
            nullptr,
            "Slang postal packer",
            0,
            "Slang postal packer",
            0,
            VK_API_VERSION_1_3
        );

        uint availableLayerCount = 0;
        vkEnumerateInstanceLayerProperties(&availableLayerCount, nullptr);
        List<VkLayerProperties> availableLayers;
        defer availableLayers.drop();
        availableLayers.resize(availableLayerCount);
        vkEnumerateInstanceLayerProperties(&availableLayerCount, availableLayers.data);

#ifndef NDEBUG
        for(size_t i = 0; i < availableLayers.size; ++i)
        {
            var layer = availableLayers[i];
            if(ptrToString(&layer.layerName) == "VK_LAYER_KHRONOS_validation")
            {
                validationLayers.push("VK_LAYER_KHRONOS_validation");
            }
        }


        VkValidationFeatureEnableEXT enabledFeatures[1] = {
            VK_VALIDATION_FEATURE_ENABLE_DEBUG_PRINTF_EXT
        };
        VkValidationFeaturesEXT features = VkValidationFeaturesEXT(
            VK_STRUCTURE_TYPE_VALIDATION_FEATURES_EXT,
            nullptr,
            enabledFeatures.getCount(),
            (VkValidationFeatureEnableEXT*)&enabledFeatures,
            0,
            nullptr
        );
#endif

        VkInstanceCreateInfo instanceInfo = VkInstanceCreateInfo(
            VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            nullptr,
            0,
            &appInfo,
            (uint)validationLayers.size, validationLayers.data,
            (uint)extensions.size, extensions.data
        );
#ifndef NDEBUG
        instanceInfo.pNext = (void*)&features;
#endif

        VkResult res = vkCreateInstance(&instanceInfo, nullptr, &vulkanInstance);
        if(res != VkResult.VK_SUCCESS)
            panic("vkCreateInstance %d\n", res);

        load_vk_extensions(vulkanInstance);

#ifndef NDEBUG
        VkDebugUtilsMessengerCreateInfoEXT messengerInfo = VkDebugUtilsMessengerCreateInfoEXT(
            VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
            nullptr,
            0,
            //VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT|
            VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT|
            VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT|
            VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
            VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT|
            VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT|
            VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
            getDebugCallbackPtr(),
            nullptr
        );
        vkCreateDebugUtilsMessengerEXT(vulkanInstance, &messengerInfo, nullptr, &debugMessenger);
#endif

        uint physicalDeviceCount = 0;
        vkEnumeratePhysicalDevices(vulkanInstance, &physicalDeviceCount, nullptr);
        List<VkPhysicalDevice> physicalDevices;
        defer physicalDevices.drop();
        physicalDevices.resize(physicalDeviceCount);
        vkEnumeratePhysicalDevices(vulkanInstance, &physicalDeviceCount, physicalDevices.data);

        for(uint i = 0; i < physicalDeviceCount; ++i)
        {
            Device d;
            d.init(physicalDevices[i]);
            if(d.supportsRequiredExtensions)
                devices.push(d);
            else d.deinit();
        }
    }

    [mutating]
    public void deinit()
    {
        for(uint i = 0; i < devices.size; ++i)
            devices[i].deinit();
        devices.drop();

#ifndef NDEBUG
        vkDestroyDebugUtilsMessengerEXT(vulkanInstance, debugMessenger, nullptr);
#endif
        // Deinit vulkan
        vkDestroyInstance(vulkanInstance, nullptr);

        validationLayers.drop();
        extensions.drop();

        SDL_Quit();
    }
}

bool hasAllExtensions(NativeString required[], List<VkExtensionProperties> props)
{
    for(int i = 0; i < required.getCount(); ++i)
    {
        NativeString required_name = required[i];
        bool found = false;
        for(size_t j = 0; j < props.size; ++j)
        {
            VkExtensionProperties prop = props[j];
            if(ptrToString(&prop.extensionName) == required_name)
            {
                found = true;
                break;
            }
        }

        if(!found)
            return false;
    }
    return true;
}

public struct DestroyableVulkanResource<T>
{
    T resource;
    uint64_t usedUntil;

    __init(T resource, uint64_t usedUntil)
    {
        this.resource = resource;
        this.usedUntil = usedUntil;
    }
};

void release(DestroyableVulkanResource<VkBuffer> r, inout Device dev)
{
    vkDestroyBuffer(dev.logicalDevice, r.resource, nullptr);
}

void release(DestroyableVulkanResource<VkCommandBuffer> r, inout Device dev)
{
    VkCommandBuffer buf = r.resource;
    vkFreeCommandBuffers(dev.logicalDevice, dev.commandPool, 1, &buf);
}

void release(DestroyableVulkanResource<VkImage> r, inout Device dev)
{
    vkDestroyImage(dev.logicalDevice, r.resource, nullptr);
}

void release(DestroyableVulkanResource<VmaAllocation> r, inout Device dev)
{
    vmaFreeMemory(dev.allocator, r.resource);
}

void release(DestroyableVulkanResource<VkImageView> r, inout Device dev)
{
    vkDestroyImageView(dev.logicalDevice, r.resource, nullptr);
}

void release(DestroyableVulkanResource<VkDescriptorSetLayout> r, inout Device dev)
{
    vkDestroyDescriptorSetLayout(dev.logicalDevice, r.resource, nullptr);
}

void release(DestroyableVulkanResource<VkPipeline> r, inout Device dev)
{
    vkDestroyPipeline(dev.logicalDevice, r.resource, nullptr);
}

void release(DestroyableVulkanResource<VkPipelineCache> r, inout Device dev)
{
    vkDestroyPipelineCache(dev.logicalDevice, r.resource, nullptr);
}

void release(DestroyableVulkanResource<VkPipelineLayout> r, inout Device dev)
{
    vkDestroyPipelineLayout(dev.logicalDevice, r.resource, nullptr);
}

void release(DestroyableVulkanResource<VkQueryPool> r, inout Device dev)
{
    vkDestroyQueryPool(dev.logicalDevice, r.resource, nullptr);
}

void release(DestroyableVulkanResource<VkShaderModule> r, inout Device dev)
{
    vkDestroyShaderModule(dev.logicalDevice, r.resource, nullptr);
}

void release(DestroyableVulkanResource<VkSampler> r, inout Device dev)
{
    vkDestroySampler(dev.logicalDevice, r.resource, nullptr);
}

#define DELETION_QUEUES \
    DELETION_QUEUE(VkBuffer) \
    DELETION_QUEUE(VkCommandBuffer) \
    DELETION_QUEUE(VkImage) \
    DELETION_QUEUE(VkImageView) \
    DELETION_QUEUE(VmaAllocation) \
    DELETION_QUEUE(VkDescriptorSetLayout) \
    DELETION_QUEUE(VkPipeline) \
    DELETION_QUEUE(VkPipelineCache) \
    DELETION_QUEUE(VkPipelineLayout) \
    DELETION_QUEUE(VkQueryPool) \
    DELETION_QUEUE(VkShaderModule) \
    DELETION_QUEUE(VkSampler)

public struct Device: IDroppable
{
    public VkPhysicalDevice physicalDevice = nullptr;
    public VkDevice logicalDevice = nullptr;
    public VkQueue queue = nullptr;
    public VkCommandPool commandPool = nullptr;
    public VkQueryPool timestampQueryPool = nullptr;
    public VmaAllocator allocator = nullptr;
    List<VkQueueFamilyProperties> queueFamilies;
    public bool supportsRequiredExtensions = false;

    // Deletion queues for each type.
#define DELETION_QUEUE(type) \
    private List<DestroyableVulkanResource<type>> dq##type;
    DELETION_QUEUES
#undef DELETION_QUEUE

    private uint64_t deletionTimeline = 0;
    private VkBuffer stagingBuffer = nullptr;
    private VmaAllocation stagingBufferAllocation = nullptr;
    private Ptr<uint8_t> mappedStagingBuffer = nullptr;
    private size_t stagingBottom = 0;
    private size_t stagingTop = 0;
    private size_t stagingCapacity = 0;
    private bool stagingHigh = false;
    private uint64_t timestampQueryFrameCounter = 0;
    private uint timestampQueryCounter = 0;
    private List<uint64_t> timestampQueryResults;

    private static const uint MAX_TIMER_COUNT = 64;

    public VkPhysicalDeviceProperties2 physicalDeviceProps;
    public VkPhysicalDeviceVulkan11Properties vulkan11Props;
    public VkPhysicalDeviceVulkan12Properties vulkan12Props;
    public VkPhysicalDeviceVulkan13Properties vulkan13Props;

    public VkPhysicalDeviceFeatures2 supportedPhysicalDeviceFeatures;
    public VkPhysicalDeviceVulkan11Features supportedVulkan11Features;
    public VkPhysicalDeviceVulkan12Features supportedVulkan12Features;
    public VkPhysicalDeviceVulkan13Features supportedVulkan13Features;

    public VkPhysicalDeviceFeatures2 enabledPhysicalDeviceFeatures;
    public VkPhysicalDeviceVulkan11Features enabledVulkan11Features;
    public VkPhysicalDeviceVulkan12Features enabledVulkan12Features;
    public VkPhysicalDeviceVulkan13Features enabledVulkan13Features;

    static NativeString deviceExtensions[] = {
        VK_KHR_SWAPCHAIN_EXTENSION_NAME,
        VK_KHR_PUSH_DESCRIPTOR_EXTENSION_NAME
    #ifndef NDEBUG
        , VK_KHR_SHADER_NON_SEMANTIC_INFO_EXTENSION_NAME
    #endif
    };

    public __init()
    {
        zeroInitialize(physicalDeviceProps);
        zeroInitialize(vulkan11Props);
        zeroInitialize(vulkan12Props);
        zeroInitialize(vulkan13Props);
        zeroInitialize(supportedPhysicalDeviceFeatures);
        zeroInitialize(supportedVulkan11Features);
        zeroInitialize(supportedVulkan12Features);
        zeroInitialize(supportedVulkan13Features);
        zeroInitialize(enabledPhysicalDeviceFeatures);
        zeroInitialize(enabledVulkan11Features);
        zeroInitialize(enabledVulkan12Features);
        zeroInitialize(enabledVulkan13Features);
#define DELETION_QUEUE(type) \
        dq##type = List<DestroyableVulkanResource<type>>();
        DELETION_QUEUES
#undef DELETION_QUEUE
    }

    [mutating]
    public void init(VkPhysicalDevice physicalDevice)
    {
        this.physicalDevice = physicalDevice;

        uint32_t availableCount = 0;
        NativeString layerName = ptrToString(Ptr<void>(nullptr));
        vkEnumerateDeviceExtensionProperties(physicalDevice, layerName, &availableCount, nullptr);
        List<VkExtensionProperties> extensions;
        defer extensions.drop();
        extensions.resize(availableCount);
        vkEnumerateDeviceExtensionProperties(physicalDevice, layerName, &availableCount, extensions.data);

        supportsRequiredExtensions = hasAllExtensions(deviceExtensions, extensions);

        uint32_t queueFamilyCount = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, nullptr);
        queueFamilies.resize(queueFamilyCount);
        vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, queueFamilies.data);

        physicalDeviceProps.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2;
        physicalDeviceProps.pNext= Ptr<void>(&vulkan11Props);
        vulkan11Props.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_PROPERTIES;
        vulkan11Props.pNext = Ptr<void>(&vulkan12Props);
        vulkan12Props.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_PROPERTIES;
        vulkan12Props.pNext = Ptr<void>(&vulkan13Props);
        vulkan13Props.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_PROPERTIES;
        vulkan13Props.pNext = nullptr;

        vkGetPhysicalDeviceProperties2(physicalDevice, &physicalDeviceProps);

        supportedPhysicalDeviceFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
        supportedPhysicalDeviceFeatures.pNext = Ptr<void>(&supportedVulkan11Features);
        supportedVulkan11Features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES;
        supportedVulkan11Features.pNext = Ptr<void>(&supportedVulkan12Features);
        supportedVulkan12Features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
        supportedVulkan12Features.pNext = Ptr<void>(&supportedVulkan13Features);
        supportedVulkan13Features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES;
        supportedVulkan13Features.pNext = nullptr;

        vkGetPhysicalDeviceFeatures2(physicalDevice, &supportedPhysicalDeviceFeatures);

        zeroInitialize(enabledPhysicalDeviceFeatures);
        zeroInitialize(enabledVulkan11Features);
        zeroInitialize(enabledVulkan12Features);
        zeroInitialize(enabledVulkan13Features);
        enabledPhysicalDeviceFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
        enabledVulkan11Features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES;
        enabledVulkan12Features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
        enabledVulkan13Features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES;

        enabledPhysicalDeviceFeatures.features.shaderInt16 = VK_TRUE;
        enabledPhysicalDeviceFeatures.features.shaderInt64 = VK_TRUE;
        enabledPhysicalDeviceFeatures.features.samplerAnisotropy = VK_TRUE;
        enabledVulkan12Features.bufferDeviceAddress = VK_TRUE;
        enabledVulkan12Features.shaderInt8 = VK_TRUE;
        enabledVulkan12Features.timelineSemaphore = VK_TRUE;
        enabledVulkan13Features.synchronization2 = VK_TRUE;
        enabledVulkan13Features.shaderIntegerDotProduct = VK_TRUE;
    }

    public int findCompatibleQueue(VkSurfaceKHR surface = nullptr)
    {
        let flags = 
            VK_QUEUE_GRAPHICS_BIT |
            VK_QUEUE_COMPUTE_BIT |
            VK_QUEUE_TRANSFER_BIT;
        for(uint i = 0; i < queueFamilies.size; ++i)
        {
            let props = queueFamilies[i];
            if((props.queueFlags & flags) == flags)
            {
                VkBool32 supports = VK_TRUE;
                if(surface)
                {
                    vkGetPhysicalDeviceSurfaceSupportKHR(
                        physicalDevice, i, surface, &supports
                    );
                }

                if(supports == VK_TRUE)
                    return int(i);
            }
        }
        return -1;
    }

    [mutating]
    public void drop()
    {
        deinit();
    }

    [mutating]
    public void deinit()
    {
        close();
        queueFamilies.drop();
    }

    public bool isOpen()
    {
        return logicalDevice != nullptr;
    }

    // The surface is only used for selecting the queue family that support it.
    [mutating]
    public void open(inout Context ctx, VkSurfaceKHR surface = nullptr)
    {
        int familyIndex = findCompatibleQueue(surface);
        if(familyIndex < 0)
            panic("There is no compatible queue family on this device!");

        printf("Using device: %s\n", ptrToString(&physicalDeviceProps.properties.deviceName));

        float priority = 1.0f;
        VkDeviceQueueCreateInfo queueInfo = VkDeviceQueueCreateInfo(
            VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            nullptr,
            0,
            familyIndex,
            1,
            &priority
        );

        enabledPhysicalDeviceFeatures.pNext = Ptr<void>(&enabledVulkan11Features);
        enabledVulkan11Features.pNext = Ptr<void>(&enabledVulkan12Features);
        enabledVulkan12Features.pNext = Ptr<void>(&enabledVulkan13Features);
        enabledVulkan13Features.pNext = nullptr;

        VkDeviceCreateInfo deviceCreateInfo = VkDeviceCreateInfo(
            VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            (void*)&enabledPhysicalDeviceFeatures,
            0,
            1, &queueInfo,
            (uint32_t)ctx.validationLayers.size, ctx.validationLayers.data,
            (uint32_t)deviceExtensions.getCount(), &deviceExtensions[0],
            nullptr
        );

        VkResult res = vkCreateDevice(physicalDevice, &deviceCreateInfo, nullptr, &logicalDevice);
        if(res != VkResult.VK_SUCCESS)
            panic("Failed to open device!");

        vkGetDeviceQueue(logicalDevice, familyIndex, 0, &queue);

        VmaAllocatorCreateInfo allocatorInfo;
        zeroInitialize(allocatorInfo);
        allocatorInfo.physicalDevice = physicalDevice;
        allocatorInfo.device = logicalDevice;
        allocatorInfo.instance = ctx.vulkanInstance;
        allocatorInfo.flags = VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT;
        vmaCreateAllocator(&allocatorInfo, &allocator);

        var poolInfo = VkCommandPoolCreateInfo(
            VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            nullptr, 0,
            (uint32_t)familyIndex
        );
        vkCreateCommandPool(logicalDevice, &poolInfo, nullptr, &commandPool);

        var queryPoolInfo = VkQueryPoolCreateInfo(
            VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO,
            nullptr, 0, VK_QUERY_TYPE_TIMESTAMP, MAX_TIMER_COUNT*2, 0
        );
        vkCreateQueryPool(logicalDevice, &queryPoolInfo, nullptr, &timestampQueryPool);

        deletionTimeline = 0;
        stagingBottom = 0;
        stagingTop = 0;
        stagingCapacity = 0;
        stagingHigh = false;
        timestampQueryFrameCounter = 0;
        timestampQueryCounter = 0;
    }

    private bool deletionQueuesEmpty()
    {
#define DELETION_QUEUE(type) \
        if(dq##type.size > 0) return false;
        DELETION_QUEUES
#undef DELETION_QUEUE
        return true;
    }

    [mutating]
    public void close()
    {
        if(!isOpen())
            return;
        release(stagingBuffer);
        release(stagingBufferAllocation);
        vkDeviceWaitIdle(logicalDevice);
        while (!deletionQueuesEmpty())
            stagingFrame();
        vkDestroyQueryPool(logicalDevice, timestampQueryPool, nullptr);
        timestampQueryResults.drop();
        vkDestroyCommandPool(logicalDevice, commandPool, nullptr);

#define DELETION_QUEUE(type) \
        dq##type.drop();
        DELETION_QUEUES
#undef DELETION_QUEUE

        vmaDestroyAllocator(allocator);
        allocator = nullptr;
        vkDestroyDevice(logicalDevice, nullptr);
        queue = nullptr;
        logicalDevice = nullptr;
    }

    [mutating]
    public VkCommandBuffer beginCommandBuffer()
    {
        VkCommandBuffer cmd;
        var cmdCreateInfo = VkCommandBufferAllocateInfo(
            VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            nullptr,
            commandPool,
            VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            1
        );
        vkAllocateCommandBuffers(logicalDevice, &cmdCreateInfo, &cmd);

        var cmdBeginInfo = VkCommandBufferBeginInfo(
            VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            nullptr,
            VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            nullptr
        );
        vkBeginCommandBuffer(cmd, &cmdBeginInfo);
        return cmd;
    }

    [mutating]
    public void submitCommandBufferSync(VkCommandBuffer cmd)
    {
        vkEndCommandBuffer(cmd);
        var cmdInfo = VkCommandBufferSubmitInfo(
            VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
            nullptr,
            cmd,
            0
        );
        var submitInfo = VkSubmitInfo2(
            VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
            nullptr,
            0,
            0, nullptr,
            1, &cmdInfo,
            0, nullptr
        );
        vkQueueSubmit2(queue, 1, &submitInfo, nullptr);
        vkQueueWaitIdle(queue);
        vkFreeCommandBuffers(logicalDevice, commandPool, 1, &cmd);
        stagingFrame();
        stagingFrame();
    }

    public Tuple<VkBuffer, VmaAllocation> createBuffer(VkBufferUsageFlags usage, size_t size, size_t alignment = 0)
    {
        var bufferInfo = VkBufferCreateInfo(
            VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            nullptr,
            0,
            size,
            usage,
            VK_SHARING_MODE_EXCLUSIVE,
            0,
            nullptr
        );
        var allocInfo = VmaAllocationCreateInfo(
            VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT,
            VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE,
            VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            0,
            0,
            nullptr,
            nullptr,
            1.0f
        );
        VmaAllocationInfo info;
        VkBuffer buf;
        VmaAllocation alloc;
        zeroInitialize(info);
        vmaCreateBufferWithAlignment(allocator, &bufferInfo, &allocInfo, uint64_t(alignment), &buf, &alloc, &info);
        return makeTuple(buf, alloc);
    }

    public Tuple<VkImage, VmaAllocation> createImage(
        VkImageCreateFlags flags,
        VkImageType type,
        VkImageUsageFlags usage,
        VkFormat format,
        uint3 size,
        VkSampleCountFlagBits samples = VK_SAMPLE_COUNT_1_BIT,
        uint mipLevels = 1,
        uint arrayLayers = 1
    ){
        var imageInfo = VkImageCreateInfo(
            VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            nullptr,
            flags,
            type,
            format,
            VkExtent3D(size.x, size.y, size.z),
            mipLevels,
            arrayLayers,
            samples,
            VK_IMAGE_TILING_OPTIMAL,
            usage,
            VK_SHARING_MODE_EXCLUSIVE,
            0,
            nullptr,
            VK_IMAGE_LAYOUT_UNDEFINED
        );

        var allocInfo = VmaAllocationCreateInfo(
            VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT,
            VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE,
            VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            0,
            0,
            nullptr,
            nullptr,
            1.0f
        );
        VkImage img;
        VmaAllocation alloc;

        vmaCreateImage(allocator, &imageInfo, &allocInfo, &img, &alloc, nullptr);
        return makeTuple(img, alloc);
    }

    public VkSampler createSampler(
        VkFilter mini,
        VkFilter magni,
        VkSamplerMipmapMode mipmap_mode,
        VkSamplerAddressMode extension,
        bool normalized = true,
        float anisotropy = 16,
        float max_mipmap = 100.0f,
        float mipmap_bias = 0.0f,
        bool shadow = false
    ){
        var info = VkSamplerCreateInfo(
            VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO, nullptr, 0,
            magni, mini, mipmap_mode, extension, extension, extension, mipmap_bias,
            normalized && anisotropy > 0 ? VK_TRUE : VK_FALSE,
            normalized ? anisotropy : 0.0f,
            shadow, shadow ? VK_COMPARE_OP_LESS : VK_COMPARE_OP_ALWAYS,
            0.0f,
            normalized ? max_mipmap : 0.0f,
            VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK,
            normalized ? VK_FALSE : VK_TRUE
        );
        VkSampler sam;
        vkCreateSampler(logicalDevice, &info, nullptr, &sam);
        return sam;
    }

    public VkDeviceAddress getAddress(VkBuffer buf)
    {
        var info = VkBufferDeviceAddressInfo(
            VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO,
            nullptr,
            buf
        );
        return vkGetBufferDeviceAddress(logicalDevice, &info);
    }

    [mutating]
    private int64_t prepareStaging(size_t memory)
    {
        if(stagingBottom + memory > stagingTop)
        {
            // Will run out of memory - reset.
            release(stagingBuffer);
            release(stagingBufferAllocation);

            size_t newSize = max(stagingCapacity * 2, stagingCapacity + memory);
            var bufferInfo = VkBufferCreateInfo(
                VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                nullptr,
                0,
                newSize,
                VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                VK_SHARING_MODE_EXCLUSIVE,
                0,
                nullptr
            );
            var allocInfo = VmaAllocationCreateInfo(
                VMA_ALLOCATION_CREATE_MAPPED_BIT | VMA_ALLOCATION_CREATE_HOST_ACCESS_RANDOM_BIT,
                VMA_MEMORY_USAGE_AUTO_PREFER_HOST,
                VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT,
                0,
                0,
                nullptr,
                nullptr,
                1.0f
            );
            VmaAllocationInfo info;
            zeroInitialize(info);
            vmaCreateBuffer(
                allocator,
                &bufferInfo,
                &allocInfo,
                &stagingBuffer,
                &stagingBufferAllocation,
                &info
            );

            stagingCapacity = size_t(info.size);
            stagingBottom = 0;
            stagingTop = stagingCapacity;
            mappedStagingBuffer = Ptr<uint8_t>(info.pMappedData);
        }

        int64_t srcOffset = 0;
        if(stagingHigh)
        {
            stagingTop -= memory;
            srcOffset = int64_t(stagingTop);
        }
        else
        {
            srcOffset = int64_t(stagingBottom);
            stagingBottom += memory;
        }
        return srcOffset;
    }

    [mutating]
    public void upload<T>(VkCommandBuffer cmd, VkBuffer target, T* data, size_t count = 1, size_t byteOffset = 0)
    {
        size_t memory = strideof<T>() * count;
        int64_t srcOffset = prepareStaging(memory);
        copyBytes(Ptr<void>(mappedStagingBuffer + srcOffset), Ptr<void>(data), memory);

        var copyRegion = VkBufferCopy(srcOffset, byteOffset, memory);
        vkCmdCopyBuffer(cmd, stagingBuffer, target, 1, &copyRegion);
    }

    [mutating]
    public void upload<T>(
        VkCommandBuffer cmd,
        VkImage target,
        uint3 extents,
        T* data,
        uint dataSize = 0,
        uint mipLevel = 0,
        uint arrayLayer = 0,
        uint layerCount = 1
    ){
        size_t memory = dataSize == 0 ?
            extents.x * extents.y * extents.z * strideof<T>() * layerCount : 
            dataSize;
        int64_t srcOffset = prepareStaging(memory);
        copyBytes(Ptr<void>(mappedStagingBuffer + srcOffset), Ptr<void>(data), memory);

        var copyRegion = VkBufferImageCopy(
            srcOffset,
            0, 0,
            VkImageSubresourceLayers(VK_IMAGE_ASPECT_COLOR_BIT, mipLevel, arrayLayer, layerCount),
            VkOffset3D(0,0,0),
            VkExtent3D(extents.x, extents.y, extents.z)
        );
        vkCmdCopyBufferToImage(cmd, stagingBuffer, target, VK_IMAGE_LAYOUT_GENERAL, 1, &copyRegion);
    }

    [mutating]
    public void stagingFrame()
    {
        stagingHigh = !stagingHigh;
        if(stagingHigh) stagingTop = stagingCapacity;
        else stagingBottom = 0;
        deletionTimeline++;
#define DELETION_QUEUE(type) \
        for(int i = 0; i < dq##type.size;) \
        { \
            let entry = dq##type [i]; \
            if(deletionTimeline >= entry.usedUntil) \
            { \
                release(dq##type [i], this); \
                dq##type .swapAndPop(i); \
            } \
            else ++i; \
        }
    DELETION_QUEUES
#undef DELETION_QUEUE
    }

    [mutating]
    public uint timestampQuery(VkCommandBuffer cmd, VkPipelineStageFlags2 stage)
    {
        uint index = timestampQueryCounter;
        bool timestampQueryHigh = (timestampQueryFrameCounter & 1) == 0;
        uint baseIndex = timestampQueryHigh ? MAX_TIMER_COUNT : 0;
        vkCmdWriteTimestamp2(cmd, stage, timestampQueryPool, baseIndex + index);
        timestampQueryCounter++;
        return index;
    }

    [mutating]
    public uint timestampBegin(VkCommandBuffer cmd)
    {
        return timestampQuery(cmd, VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT);
    }

    [mutating]
    public uint timestampEnd(VkCommandBuffer cmd)
    {
        return timestampQuery(cmd, VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT);
    }

    // Return value is in ms
    [mutating]
    public float getTimestampDelta(uint fromIndex, uint toIndex)
    {
        bool timestampQueryHigh = (timestampQueryFrameCounter & 1) == 0;
        uint baseIndex = timestampQueryHigh ? MAX_TIMER_COUNT : 0;
        uint readFromIndex = baseIndex + fromIndex;
        uint readToIndex = baseIndex + toIndex;
        if(readFromIndex < timestampQueryResults.size && readToIndex < timestampQueryResults.size)
        {
            // Convert results to nanoseconds
            uint64_t from = timestampQueryResults[readFromIndex];
            uint64_t to = timestampQueryResults[readToIndex];
            uint64_t lo = min(from, to);
            uint64_t hi = max(from, to);
            return float(hi-lo) * physicalDeviceProps.properties.limits.timestampPeriod / 1000000.0;
        }
        return 0;
    }

    [mutating]
    public void pumpTimestampQueries(VkCommandBuffer cmd)
    {
        timestampQueryFrameCounter++;
        bool timestampQueryHigh = (timestampQueryFrameCounter & 1) == 0;
        uint baseIndex = timestampQueryHigh ? MAX_TIMER_COUNT : 0;
        if(timestampQueryFrameCounter > 2)
        { // Fetch prev results
            timestampQueryResults.resize(MAX_TIMER_COUNT * 2);
            vkGetQueryPoolResults(
                logicalDevice,
                timestampQueryPool,
                baseIndex,
                MAX_TIMER_COUNT,
                uint32_t(timestampQueryResults.size*8),
                Ptr<void>(timestampQueryResults.data + baseIndex),
                8,
                VK_QUERY_RESULT_64_BIT
            );
        }
        vkCmdResetQueryPool(cmd, timestampQueryPool, baseIndex, MAX_TIMER_COUNT);
        timestampQueryCounter = 0;
    }

#define DELETION_QUEUE(type) \
    [mutating] \
    public void release(inout type t) \
    { \
        if(t == nullptr) return; \
        dq##type .push(DestroyableVulkanResource<type>(t, deletionTimeline+2)); \
        t = nullptr; \
    }
    DELETION_QUEUES
#undef DELETION_QUEUE
}

public struct RenderTarget
{
    // The image is always assumed to be in VK_IMAGE_LAYOUT_GENERAL. If it needs
    // to be in some other layout, it should be returned back to GENERAL before
    // handing it on.
    public VkImage image;
    public VkImageView view;
    public VkFormat format;
    public uint2 size;
};

// This is just VkImageMemoryBarrier2 without the boilerplate and some generally
// safe default parameters.
public void imageMemoryBarrier(
    VkCommandBuffer cmd,
    VkImage image,
    VkImageLayout oldLayout = VK_IMAGE_LAYOUT_GENERAL,
    VkImageLayout newLayout = VK_IMAGE_LAYOUT_GENERAL,
    uint32_t baseMipLevel = 0,
    uint32_t levelCount = VK_REMAINING_MIP_LEVELS,
    uint32_t baseArrayLayer = 0,
    uint32_t layerCount = VK_REMAINING_ARRAY_LAYERS,
    VkPipelineStageFlags2 srcStageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
    VkAccessFlags2 srcAccessMask = VK_ACCESS_2_MEMORY_WRITE_BIT | VK_ACCESS_2_MEMORY_READ_BIT | VK_ACCESS_2_SHADER_SAMPLED_READ_BIT | VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
    VkPipelineStageFlags2 dstStageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
    VkAccessFlags2 dstAccessMask = VK_ACCESS_2_MEMORY_WRITE_BIT | VK_ACCESS_2_MEMORY_READ_BIT | VK_ACCESS_2_SHADER_SAMPLED_READ_BIT,
    VkImageAspectFlags aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
){
    var imageBarrier = VkImageMemoryBarrier2(
        VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        nullptr,
        srcStageMask,
        srcAccessMask,
        dstStageMask,
        dstAccessMask,
        oldLayout,
        newLayout,
        VK_QUEUE_FAMILY_IGNORED,
        VK_QUEUE_FAMILY_IGNORED,
        image,
        VkImageSubresourceRange(
            aspectMask,
            baseMipLevel,
            levelCount,
            baseArrayLayer,
            layerCount
        )
    );
    var dependencyInfo = VkDependencyInfo(
        VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        nullptr,
        0,
        0, nullptr,
        0, nullptr,
        1, &imageBarrier
    );
    vkCmdPipelineBarrier2(cmd, &dependencyInfo);
}

public void bufferBarrier(
    VkCommandBuffer cmd,
    VkPipelineStageFlags2 srcStageMask,
    VkAccessFlags2 srcAccessMask,
    VkPipelineStageFlags2 dstStageMask,
    VkAccessFlags2 dstAccessMask
){
    var memoryBarrier = VkMemoryBarrier2(
        VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
        nullptr,
        srcStageMask,
        srcAccessMask,
        dstStageMask,
        dstAccessMask
    );
    var dependencyInfo = VkDependencyInfo(
        VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        nullptr,
        0,
        1, &memoryBarrier,
        0, nullptr,
        0, nullptr
    );
    vkCmdPipelineBarrier2(cmd, &dependencyInfo);
}

public void bufferUploadStartBarrier(VkCommandBuffer cmd)
{
    bufferBarrier(
        cmd,
        VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
        VK_ACCESS_2_MEMORY_READ_BIT,
        VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
        VK_ACCESS_2_MEMORY_WRITE_BIT | VK_ACCESS_2_MEMORY_READ_BIT
    );
}

public void bufferUploadEndBarrier(VkCommandBuffer cmd)
{
    bufferBarrier(
        cmd,
        VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
        VK_ACCESS_2_MEMORY_WRITE_BIT | VK_ACCESS_2_MEMORY_READ_BIT,
        VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
        VK_ACCESS_2_MEMORY_READ_BIT
    );
}

public void blitImage(
    VkCommandBuffer cmd,
    VkImage src,
    uint3 srcSize,
    VkFormat srcFormat,
    VkImage dst,
    uint3 dstSize,
    VkFormat dstFormat,
    VkFilter filter = VK_FILTER_LINEAR
){
    imageMemoryBarrier(cmd, src);

    if(all(srcSize == dstSize) && srcFormat == dstFormat)
    {
        var copy = VkImageCopy(
            VkImageSubresourceLayers(VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
            VkOffset3D(0,0,0),
            VkImageSubresourceLayers(VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
            VkOffset3D(0,0,0),
            VkExtent3D(dstSize.x, dstSize.y, dstSize.z)
        );
        vkCmdCopyImage(
            cmd,
            src, VK_IMAGE_LAYOUT_GENERAL,
            dst, VK_IMAGE_LAYOUT_GENERAL,
            1, &copy
        );
    }
    else
    {
        var blit = VkImageBlit(
            VkImageSubresourceLayers(VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
            {VkOffset3D(0,0,0), VkOffset3D((int32_t)srcSize.x, (int32_t)srcSize.y, (int32_t)srcSize.z)},
            VkImageSubresourceLayers(VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
            {VkOffset3D(0,0,0), VkOffset3D((int32_t)dstSize.x, (int32_t)dstSize.y, (int32_t)dstSize.z)}
        );
        vkCmdBlitImage(
            cmd,
            src, VK_IMAGE_LAYOUT_GENERAL,
            dst, VK_IMAGE_LAYOUT_GENERAL,
            1, &blit, filter
        );
    }
}

public void blitImage(
    VkCommandBuffer cmd,
    RenderTarget src,
    RenderTarget dst,
    VkFilter filter = VK_FILTER_LINEAR
){
    blitImage(cmd, src.image, uint3(src.size,1), src.format, dst.image, uint3(dst.size,1), dst.format, filter);
}

public void generateMipmaps(VkCommandBuffer cmd, VkImage image, uint3 size, uint mipLevels, uint arrayLayers = 1)
{
    imageMemoryBarrier(
        cmd, image,
        VK_IMAGE_LAYOUT_GENERAL,
        VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL
    );

    for(uint i = 1; i < mipLevels; ++i)
    {
        imageMemoryBarrier(
            cmd, image,
            VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            i-1, 1
        );
        let nextSize = max(size/2u, uint3(1u));
        for(uint j = 0; j < arrayLayers; ++j)
        {
            var blit = VkImageBlit(
                VkImageSubresourceLayers(VK_IMAGE_ASPECT_COLOR_BIT, i-1, j, 1),
                {VkOffset3D(0,0,0), VkOffset3D((int32_t)size.x, (int32_t)size.y, (int32_t)size.z)},
                VkImageSubresourceLayers(VK_IMAGE_ASPECT_COLOR_BIT, i, j, 1),
                {VkOffset3D(0,0,0), VkOffset3D((int32_t)nextSize.x, (int32_t)nextSize.y, (int32_t)nextSize.z)}
            );
            vkCmdBlitImage(
                cmd, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                1, &blit, VK_FILTER_LINEAR
            );
        }
        size = nextSize;
        imageMemoryBarrier(
            cmd, image,
            VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            VK_IMAGE_LAYOUT_GENERAL,
            i-1, 1
        );
    }

    imageMemoryBarrier(
        cmd, image,
        VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        VK_IMAGE_LAYOUT_GENERAL,
        mipLevels-1, 1
    );
}

VkImageAspectFlags guessAspect(VkFormat format)
{
    switch(format)
    {
    case VK_FORMAT_D16_UNORM:
    case VK_FORMAT_D32_SFLOAT:
        return VK_IMAGE_ASPECT_DEPTH_BIT;
    case VK_FORMAT_D16_UNORM_S8_UINT:
    case VK_FORMAT_D24_UNORM_S8_UINT:
    case VK_FORMAT_D32_SFLOAT_S8_UINT:
        return VK_IMAGE_ASPECT_DEPTH_BIT|VK_IMAGE_ASPECT_STENCIL_BIT;
    default:
        return VK_IMAGE_ASPECT_COLOR_BIT;
    }
}

public struct Texture
{
    static let defaultUsage = VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;

    public VkImage image = nullptr;
    public VmaAllocation alloc = nullptr;
    public uint3 size = uint3(0);
    public uint mipLevels = 0;
    public uint arrayLayers = 0;
    public VkImageUsageFlags usage = 0;
    public VkSampleCountFlagBits samples = VK_SAMPLE_COUNT_1_BIT;
    public VkFormat format = VK_FORMAT_UNDEFINED;

    // TODO: Maybe this could be a hash map...
    struct ImageViewData
    {
        VkImageViewType type;
        uint mipmapIndex;
        uint mipmapCount;
        uint layerIndex;
        uint layerCount;
        VkImageView view;
    };
    private List<ImageViewData> imageViews;

    public __init() {}

    [mutating]
    public void create(
        inout Device dev,
        uint3 size,
        VkFormat format,
        VkImageUsageFlags usage = defaultUsage,
        VkImageType type = VK_IMAGE_TYPE_2D,
        VkSampleCountFlagBits samples = VK_SAMPLE_COUNT_1_BIT,
        uint mipLevels = 1,
        uint arrayLayers = 1,
        VkCommandBuffer loadCommands = nullptr
    ){
        drop(dev);

        this.size = size;
        this.format = format;
        this.usage = usage;
        this.samples = samples;
        this.mipLevels = mipLevels;
        this.arrayLayers = arrayLayers;

        let pair = dev.createImage(0, type, usage, format, size, samples, mipLevels, arrayLayers);
        image = pair._0;
        alloc = pair._1;

        VkCommandBuffer cmd;
        if(loadCommands) cmd = loadCommands;
        else cmd = dev.beginCommandBuffer();

        imageMemoryBarrier(
            cmd, image,
            VK_IMAGE_LAYOUT_UNDEFINED,
            VK_IMAGE_LAYOUT_GENERAL
        );

        if(!loadCommands)
            dev.submitCommandBufferSync(cmd);
    }

    static private Tuple<int3, VkFormat, Ptr<uint8_t>> _loadImageFile(NativeString path) throws IOError
    {
        bool hdr = stbi_is_hdr(path) != 0;
        stbi_set_flip_vertically_on_load(true);

        Ptr<uint8_t> imgData = nullptr;
        int dataSize = 0;
        int channels = 0;

        int2 size = int2(0);
        VkFormat format;
        stbi_info(path, &size.x, &size.y, &channels);

        // Three-channel formats are not widely supported.
        if(channels == 3) channels = 4;

        if(hdr)
        {
            imgData = Ptr<uint8_t>(stbi_loadf(path, &size.x, &size.y, nullptr, channels));
            dataSize = size.x * size.y * channels * 4;
            if(channels == 1) format = VK_FORMAT_R32_SFLOAT;
            if(channels == 2) format = VK_FORMAT_R32G32B32_SFLOAT;
            else format = VK_FORMAT_R32G32B32A32_SFLOAT;
        }
        else
        {
            imgData = stbi_load(path, &size.x, &size.y, nullptr, channels);
            dataSize = size.x * size.y * channels;
            if(channels == 1) format = VK_FORMAT_R8_UNORM;
            if(channels == 2) format = VK_FORMAT_R8G8_UNORM;
            else format = VK_FORMAT_R8G8B8A8_UNORM;
        }

        if(!imgData)
            throw IOError.Read;

        return makeTuple(int3(size.x, size.y, dataSize), format, imgData);
    }

    [mutating]
    public void loadFromFile(inout Device dev, NativeString path, bool mipmapped = true, VkCommandBuffer loadCommands = nullptr)
        throws IOError
    {
        this.drop(dev);

        let imageFile = try _loadImageFile(path);
        int3 dims = imageFile._0;
        size = int3(dims.xy, 1);
        format = imageFile._1;
        Ptr<uint8_t> imgData = imageFile._2;

        usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_STORAGE_BIT;
        if(mipmapped)
            usage = usage|VK_IMAGE_USAGE_TRANSFER_DST_BIT|VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
        samples = VK_SAMPLE_COUNT_1_BIT;
        arrayLayers = 1;
        mipLevels = mipmapped ? uint(floor(log2(max(size.x, size.y)))+1u) : 1;

        let pair = dev.createImage(0, VK_IMAGE_TYPE_2D, usage, format, size, samples, mipLevels);
        image = pair._0;
        alloc = pair._1;

        VkCommandBuffer cmd;
        if(loadCommands) cmd = loadCommands;
        else cmd = dev.beginCommandBuffer();

        imageMemoryBarrier(
            cmd, image,
            VK_IMAGE_LAYOUT_UNDEFINED,
            VK_IMAGE_LAYOUT_GENERAL
        );
        dev.upload(cmd, image, size, imgData, dims.z);

        if(mipmapped)
            generateMipmaps(cmd, image, size, mipLevels);

        if(!loadCommands)
            dev.submitCommandBufferSync(cmd);

        stbi_image_free(Ptr<void>(imgData));
    }

    [mutating]
    public void drop(inout Device dev)
    {
        if(image != nullptr)
        {
            dev.release(image);
            dev.release(alloc);
            for(uint i = 0; i < imageViews.size; ++i)
            {
                dev.release(imageViews[i].view);
            }
            imageViews.drop();
            image = nullptr;
            alloc = nullptr;
        }
        size = uint3(0);
        usage = 0;
        samples = VK_SAMPLE_COUNT_1_BIT;
        format = VK_FORMAT_UNDEFINED;
        mipLevels = 0;
        arrayLayers = 0;
    }

    [mutating]
    public VkImageView getView(
        inout Device dev,
        VkImageViewType type = VK_IMAGE_VIEW_TYPE_2D,
        uint mipmapIndex = 0,
        uint mipmapCount = VK_REMAINING_MIP_LEVELS,
        uint layerIndex = 0,
        uint layerCount = VK_REMAINING_ARRAY_LAYERS
    ){
        if(!image)
            return nullptr;

        // Check existing image views.
        for(uint i = 0; i < imageViews.size; ++i)
        {
            ImageViewData data = imageViews[i];
            if(
                data.type == type &&
                data.mipmapIndex == mipmapIndex &&
                data.mipmapCount == mipmapCount &&
                data.layerIndex == layerIndex &&
                data.layerCount == layerCount
            ){
                return data.view;
            }
        }

        // Otherwise, create the necessary view.
        var data = ImageViewData(
            type,
            mipmapIndex,
            mipmapCount,
            layerIndex,
            layerCount,
            nullptr
        );
        var viewInfo = VkImageViewCreateInfo(
            VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            nullptr,
            0,
            image,
            type,
            format,
            VkComponentMapping(
                VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY,
                VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY
            ),
            VkImageSubresourceRange(
                guessAspect(format),
                mipmapIndex, mipmapCount, layerIndex, layerCount
            )
        );
        vkCreateImageView(dev.logicalDevice, &viewInfo, nullptr, &data.view);
        imageViews.push(data);
        return data.view;
    }

    [mutating]
    public RenderTarget getTarget(
        inout Device dev,
        uint mipmapIndex = 0,
        uint mipmapCount = 1,
        uint layerIndex = 0,
        uint layerCount = 1
    ){
        RenderTarget target;
        target.image = image;
        target.view = getView(dev, VK_IMAGE_VIEW_TYPE_2D, mipmapIndex, mipmapCount, layerIndex, layerCount);
        target.format = format;
        target.size = size.xy;
        return target;
    }
};

public VkShaderModule loadShader(inout Device dev, NativeString path)
{
    do
    {
        List<uint8_t> spirv = try readBinaryFile(path);
        defer spirv.drop();
        var createInfo = VkShaderModuleCreateInfo(
            VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            nullptr,
            0,
            int(spirv.size),
            Ptr<uint32_t>(spirv.data)
        );
        VkShaderModule mod;
        VkResult res = vkCreateShaderModule(dev.logicalDevice, &createInfo, nullptr, &mod);
        if(res != VK_SUCCESS)
            return nullptr;
        return mod;
    }
    catch
    {
        panic("Failed to load shader %s\n", path);
        return nullptr;
    }
}

public VkDescriptorSetLayout createDescriptorSetLayout(
    inout Device dev,
    in List<VkDescriptorSetLayoutBinding> bindings,
    in List<VkDescriptorBindingFlags> flags = List<VkDescriptorBindingFlags>(),
    bool pushDescriptor = true
){
    VkDescriptorSetLayoutBindingFlagsCreateInfo flagInfo = {
        VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
        nullptr,
        (uint32_t)flags.size,
        flags.data
    };
    var layoutInfo = VkDescriptorSetLayoutCreateInfo(
        VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        nullptr,
        0,
        (uint32_t)bindings.size,
        bindings.data
    );
    if(flags.size != 0)
        layoutInfo.pNext = Ptr<void>(&flagInfo);
    if(pushDescriptor)
        layoutInfo.flags = VK_DESCRIPTOR_SET_LAYOUT_CREATE_PUSH_DESCRIPTOR_BIT_KHR;

    VkDescriptorSetLayout layout;
    vkCreateDescriptorSetLayout(dev.logicalDevice, &layoutInfo, nullptr, &layout);
    return layout;
}

public VkDescriptorSetLayoutBinding bindingSlot(
    uint32_t binding,
    VkDescriptorType descriptorType,
    uint32_t descriptorCount = 1
){
    return VkDescriptorSetLayoutBinding(
        binding, descriptorType, descriptorCount, VK_SHADER_STAGE_ALL,
        nullptr
    );
}

// 
// Limitations: 
// - Compute only
// - Push descriptors only
public struct SimpleComputePipeline
{
    VkPipeline pipeline = nullptr;
    VkPipelineLayout pipelineLayout = nullptr;
    VkDescriptorSetLayout pushDescriptorLayout = nullptr;
    List<VkDescriptorType> descriptorTypes;

    public __init() {}

    [mutating]
    public void create<each T>(
        inout Device dev,
        NativeString shaderPath,
        NativeString entryPoint,
        size_t pushConstantSize,
        in IArray<uint> specializationConstants,
        expand each T bindings
    )
        throws IOError
        where T == VkDescriptorSetLayoutBinding
    {
        VkShaderModule mod = loadShader(dev, shaderPath);
        if(!mod)
            throw IOError.Read;
        List<VkDescriptorSetLayoutBinding> bindingsList;
        defer bindingsList.drop();
        expand bindingsList.push(each bindings);
        create(dev, mod, entryPoint, pushConstantSize, specializationConstants, bindingsList);

        vkDestroyShaderModule(dev.logicalDevice, mod, nullptr);
    }

    [mutating]
    public void create(
        inout Device dev,
        VkShaderModule mod,
        NativeString entryPoint,
        size_t pushConstantSize,
        in IArray<uint> specializationConstants,
        in List<VkDescriptorSetLayoutBinding> bindings
    ){
        drop(dev);

        List<VkDescriptorBindingFlags> flags;
        defer flags.drop();
        pushDescriptorLayout = createDescriptorSetLayout(dev, bindings, flags, true);

        descriptorTypes.resize(bindings.size);
        for(uint i = 0; i < bindings.size; ++i)
        {
            if(descriptorTypes.size <= bindings[i].binding)
                descriptorTypes.resize(bindings[i].binding+1);
            descriptorTypes[i] = bindings[i].descriptorType;
        }

        List<uint> specializationConstantData;
        defer specializationConstantData.drop();
        List<VkSpecializationMapEntry> specializationEntries;
        defer specializationEntries.drop();
        for(uint i = 0; i < specializationConstants.getCount(); ++i)
        {
            specializationConstantData.push(specializationConstants[i]);
            specializationEntries.push(VkSpecializationMapEntry(
                i, i * 4, 4
            ));
        }
        var specInfo = VkSpecializationInfo(
            uint32_t(specializationEntries.size),
            specializationEntries.data,
            uint32_t(specializationConstantData.size * 4),
            Ptr<void>(specializationConstantData.data),
        );

        var range = VkPushConstantRange(
            VK_SHADER_STAGE_ALL, 0, (uint32_t)pushConstantSize
        );
        var pipelineLayoutInfo = VkPipelineLayoutCreateInfo(
            VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            nullptr, 0,
            bindings.size > 0 ? 1 : 0, &pushDescriptorLayout,
            pushConstantSize > 0 ? 1 : 0,
            &range
        );
        vkCreatePipelineLayout(
            dev.logicalDevice, &pipelineLayoutInfo, nullptr, &pipelineLayout
        );

        var pipelineInfo = VkComputePipelineCreateInfo(
            VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
            nullptr,
            0,
            VkPipelineShaderStageCreateInfo(
                VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                nullptr,
                0,
                VK_SHADER_STAGE_COMPUTE_BIT,
                mod,
                entryPoint,
                &specInfo
            ),
            pipelineLayout,
            nullptr,
            0
        );

        vkCreateComputePipelines(dev.logicalDevice, nullptr, 1, &pipelineInfo, nullptr, &pipeline);
    }

    public void pushConstants<T>(VkCommandBuffer cmd, T t)
    {
        vkCmdPushConstants(
            cmd, pipelineLayout, VK_SHADER_STAGE_ALL, 0,
            (uint)sizeof(T), Ptr<void>(&t)
        );
    }

    public void slot<each T>(VkCommandBuffer cmd, uint binding, expand each T desc)
        where T == VkDescriptorImageInfo
    {
        var write = VkWriteDescriptorSet(
            VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            nullptr,
            nullptr,
            binding,
            0,
            countof(desc),
            descriptorTypes[binding],
            nullptr, nullptr, nullptr
        );
        VkDescriptorImageInfo infos[countof(desc)];
        uint count = 0;
        expand (infos[count++] = each desc);

        write.pImageInfo = &infos[0];
        vkCmdPushDescriptorSetKHR(
            cmd,
            VK_PIPELINE_BIND_POINT_COMPUTE,
            pipelineLayout,
            0, 1, &write
        );
    }

    public void slot<each T>(VkCommandBuffer cmd, uint binding, expand each T desc)
        where T == VkDescriptorBufferInfo
    {
        var write = VkWriteDescriptorSet(
            VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            nullptr,
            nullptr,
            binding,
            0,
            countof(desc),
            descriptorTypes[binding],
            nullptr, nullptr, nullptr
        );
        VkDescriptorBufferInfo infos[countof(desc)];
        uint count = 0;
        expand (infos[count++] = each desc);

        write.pBufferInfo = &infos[0];
        vkCmdPushDescriptorSetKHR(
            cmd,
            VK_PIPELINE_BIND_POINT_COMPUTE,
            pipelineLayout,
            0, 1, &write
        );
    }

    public void bind(VkCommandBuffer cmd)
    {
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    }

    public void dispatch(VkCommandBuffer cmd, uint3 groups)
    {
        vkCmdDispatch(cmd, groups.x, groups.y, groups.z);
    }

    [mutating]
    public void drop(inout Device dev)
    {
        if(pipelineLayout)
            vkDestroyPipelineLayout(dev.logicalDevice, pipelineLayout, nullptr);
        pipelineLayout = nullptr;
        dev.release(pipeline);
        dev.release(pushDescriptorLayout);
        descriptorTypes.drop();
    }
}
