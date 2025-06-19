import gfx;
import vulkan;
import panic;
import sdl2;
import string;
import vulkanmemoryallocator;
import memory;
import time;
import swoosh;

import visualize;
import gather;
import update;

public struct Renderer
{
    Texture renderTex;
    Texture fitTex;

    VkSampler textureSampler;

    SimpleComputePipeline visualizer;
    SimpleComputePipeline gather;
    SimpleComputePipeline update;

    Tuple<VkBuffer, VmaAllocation> splats;
    Tuple<VkBuffer, VmaAllocation> gradients;
    Tuple<VkBuffer, VmaAllocation> moments;

    uint iters;

    public __init()
    {
        renderTex = Texture();
        fitTex = Texture();
        textureSampler = nullptr;
        visualizer = SimpleComputePipeline();
        gather = SimpleComputePipeline();
        update = SimpleComputePipeline();
        splats._0 = nullptr;
        splats._1 = nullptr;
        gradients._0 = nullptr;
        gradients._1 = nullptr;
        moments._0 = nullptr;
        moments._1 = nullptr;
        iters = 0;
    }

    [mutating]
    public void reset(inout Device dev, uint2 size)
    {
        drop(dev);

        renderTex.create(dev, uint3(size, 1), VK_FORMAT_R16G16B16A16_SFLOAT);
        do
        {
            try fitTex.loadFromFile(dev, "data/Slang_LogoBug.png");
        }
        catch
        {
            panic("Failed to load target image!\n");
        }

        textureSampler = dev.createSampler(
            VK_FILTER_LINEAR,
            VK_FILTER_LINEAR,
            VK_SAMPLER_MIPMAP_MODE_NEAREST,
            VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
        );

        do
        {
            var path = U8String(ptrToString(SDL_GetBasePath()));
            defer path.drop();
            path.append("visualize.slang.spv");
            try visualizer.create(
                dev,
                path.cStr,
                "visualize",
                sizeof(VisualizePC),
                uint[](),
                bindingSlot(0, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER),
                bindingSlot(1, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE),
                bindingSlot(2, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER),
                bindingSlot(3, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER)
            );

            path.drop();
            path = U8String(ptrToString(SDL_GetBasePath()));
            path.append("gather.slang.spv");
            try gather.create(
                dev,
                path.cStr,
                "gather",
                sizeof(GatherPC),
                uint[](),
                bindingSlot(0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER)
            );

            path.drop();
            path = U8String(ptrToString(SDL_GetBasePath()));
            path.append("update.slang.spv");
            try update.create(
                dev,
                path.cStr,
                "update",
                sizeof(UpdatePC),
                uint[](),
                bindingSlot(0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER),
                bindingSlot(1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER),
                bindingSlot(2, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER)
            );
        }
        catch
        {
            panic("Failed to load shader!\n");
        }

        splats = dev.createBuffer(
            VK_BUFFER_USAGE_TRANSFER_DST_BIT|VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
            strideof<SwooshSplat>() * SPLAT_COUNT
        );

        gradients = dev.createBuffer(
            VK_BUFFER_USAGE_TRANSFER_DST_BIT|VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
            strideof<SwooshSplat>() * SPLAT_COUNT * size.x * size.y
        );

        moments = dev.createBuffer(
            VK_BUFFER_USAGE_TRANSFER_DST_BIT|VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
            strideof<SwooshSplat>() * SPLAT_COUNT * 2
        );

        iters = 0;
    }

    [mutating]
    public void render(inout Device dev, VkCommandBuffer cmd, RenderTarget swapchain, float delta)
    {
        RenderTarget renderTarget = renderTex.getTarget(dev);
        if (iters == 0)
        {
            bufferUploadStartBarrier(cmd);
            SwooshSplat initialSplats[4] = SwooshSplat[4](
                SwooshSplat(
                    float4(0,0,0,1),
                    SoftDisk(float2(0.0,0.6), float2(0.0,1.0), 1.0, 0.0),
                    SoftDisk(float2(-0.25,0), float2(0.25,0), 1.0, 0.0)
                ),
                SwooshSplat(
                    float4(0,0,0,1),
                    SoftDisk(float2(0.0,-0.6), float2(0.0,-1.0), 1.0, 0.0),
                    SoftDisk(float2(-0.25,0), float2(0.25,0), 1.0, 0.0)
                ),
                SwooshSplat(
                    float4(0,0,0,1),
                    SoftDisk(float2(0.25,0.3), float2(-0.25,0.3), 1.0, 5.0),
                    SoftDisk(float2(-0.25,0), float2(0.25,0), 1.0, 0.0)
                ),
                SwooshSplat(
                    float4(0,0,0,1),
                    SoftDisk(float2(0.25,-0.3), float2(-0.25,-0.3), 1.0, 5.0),
                    SoftDisk(float2(-0.25,0), float2(0.25,0), 1.0, 0.0)
                ),
            );
            dev.upload(cmd, splats._0, &initialSplats[0], 4);
            bufferUploadEndBarrier(cmd);
        }

        {
            VisualizePC pc;
            pc.displaySize = renderTex.size.xy;
            pc.time = float(getTicks().seconds);

            visualizer.bind(cmd);
            visualizer.pushConstants(cmd, pc);
            visualizer.slot(cmd, 0, VkDescriptorImageInfo(textureSampler, fitTex.getView(dev), VK_IMAGE_LAYOUT_GENERAL));
            visualizer.slot(cmd, 1, VkDescriptorImageInfo(nullptr, renderTarget.view, VK_IMAGE_LAYOUT_GENERAL));
            visualizer.slot(cmd, 2, VkDescriptorBufferInfo(splats._0, 0, VK_WHOLE_SIZE));
            visualizer.slot(cmd, 3, VkDescriptorBufferInfo(gradients._0, 0, VK_WHOLE_SIZE));

            visualizer.dispatch(cmd, uint3((pc.displaySize+7)/8,1));

            imageMemoryBarrier(cmd, renderTarget.image);
        }

        blitImage(cmd, renderTarget, swapchain);

        {
            GatherPC pc;
            pc.valueCount = SPLAT_COUNT * renderTex.size.x * renderTex.size.y;
            pc.splatCount = SPLAT_COUNT;
            pc.stride = 2;
            pc.offset = 1;

            gather.bind(cmd);

            while (pc.offset < pc.valueCount)
            {
                gather.pushConstants(cmd, pc);
                gather.slot(cmd, 0, VkDescriptorBufferInfo(gradients._0, 0, VK_WHOLE_SIZE));

                int groupsLeft = (renderTex.size.x * renderTex.size.y + pc.stride - 1) / pc.stride;
                gather.dispatch(cmd, uint3((groupsLeft * SPLAT_COUNT + 255)/256,1,1));

                bufferBarrier(cmd,
                    VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                    VK_ACCESS_2_MEMORY_WRITE_BIT | VK_ACCESS_2_MEMORY_READ_BIT,
                    VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                    VK_ACCESS_2_MEMORY_WRITE_BIT | VK_ACCESS_2_MEMORY_READ_BIT
                );

                pc.stride *= 2;
                pc.offset *= 2;
            }
        }

        {
            UpdatePC pc;
            pc.splatCount = SPLAT_COUNT;
            pc.lr = 1.0 / (renderTex.size.x * renderTex.size.y);
            pc.iters = iters;

            update.bind(cmd);

            update.pushConstants(cmd, pc);
            update.slot(cmd, 0, VkDescriptorBufferInfo(splats._0, 0, VK_WHOLE_SIZE));
            update.slot(cmd, 1, VkDescriptorBufferInfo(gradients._0, 0, VK_WHOLE_SIZE));
            update.slot(cmd, 2, VkDescriptorBufferInfo(moments._0, 0, VK_WHOLE_SIZE));

            update.dispatch(cmd, uint3((SPLAT_COUNT + 7)/8,1,1));

            bufferBarrier(cmd,
                VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                VK_ACCESS_2_MEMORY_WRITE_BIT | VK_ACCESS_2_MEMORY_READ_BIT,
                VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                VK_ACCESS_2_MEMORY_WRITE_BIT | VK_ACCESS_2_MEMORY_READ_BIT
            );
        }
        iters++;
    }

    [mutating]
    public void drop(inout Device dev)
    {
        update.drop(dev);
        gather.drop(dev);
        visualizer.drop(dev);
        dev.release(textureSampler);

        dev.release(splats._0);
        dev.release(splats._1);

        dev.release(gradients._0);
        dev.release(gradients._1);

        dev.release(moments._0);
        dev.release(moments._1);

        renderTex.drop(dev);
        fitTex.drop(dev);
    }
}
