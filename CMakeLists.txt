cmake_minimum_required(VERSION 3.20)

# This line is needed to use the Slang toolchain in CMake.
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/external/slang-cpu-utils/cmake")

# C & CXX are needed for the C & C++ libraries used in this project.
project(SimpleVulkan LANGUAGES Slang C CXX)

find_package(SDL2 REQUIRED)
find_package(Vulkan REQUIRED)

#===============================================================================
# Binding generation; you can run it manually and just save the resulting
# bindings, but I do it here to ensure the bindings are always up-to-date.
#===============================================================================
find_package(Python3 REQUIRED)
set(BINDGEN ${CMAKE_CURRENT_SOURCE_DIR}/external/slang-cpu-utils/bindgen/bindgen.py)

add_custom_command(
    OUTPUT vulkan.slang
    COMMAND ${Python3_EXECUTABLE} ${BINDGEN}
        ${Vulkan_INCLUDE_DIRS}/vulkan/vulkan.h
        ${Vulkan_INCLUDE_DIRS}/vulkan/vk_platform.h
        ${Vulkan_INCLUDE_DIRS}/vulkan/vulkan_core.h
        ${Vulkan_INCLUDE_DIRS}/vk_video/vulkan_video_codec_h264std.h
        ${Vulkan_INCLUDE_DIRS}/vk_video/vulkan_video_codec_h264std_encode.h
        ${Vulkan_INCLUDE_DIRS}/vk_video/vulkan_video_codec_h264std_decode.h
        ${Vulkan_INCLUDE_DIRS}/vk_video/vulkan_video_codec_h265std.h
        ${Vulkan_INCLUDE_DIRS}/vk_video/vulkan_video_codec_h265std_encode.h
        ${Vulkan_INCLUDE_DIRS}/vk_video/vulkan_video_codec_h265std_decode.h
        --define size_t=uintptr_t
        --output vulkan.slang
    COMMENT "Generating Vulkan bindings"
)

add_custom_command(
    OUTPUT vulkanmemoryallocator.slang
    COMMAND ${Python3_EXECUTABLE} ${BINDGEN}
        ${CMAKE_CURRENT_SOURCE_DIR}/external/VulkanMemoryAllocator/include/vk_mem_alloc.h
        --import vulkan
        --imported ${Vulkan_INCLUDE_DIRS}/vulkan/vulkan.h
        --imported ${Vulkan_INCLUDE_DIRS}/vulkan/vulkan_core.h
        --define size_t=uintptr_t
        --output vulkanmemoryallocator.slang
    COMMENT "Generating Vulkan Memory Allocator bindings"
)

add_custom_command(
    OUTPUT sdl2.slang
    COMMAND ${Python3_EXECUTABLE} ${BINDGEN}
        ${SDL2_INCLUDE_DIR}/SDL.h
        ${SDL2_INCLUDE_DIR}/SDL_error.h
        ${SDL2_INCLUDE_DIR}/SDL_log.h
        ${SDL2_INCLUDE_DIR}/SDL_assert.h
        ${SDL2_INCLUDE_DIR}/SDL_version.h
        ${SDL2_INCLUDE_DIR}/SDL_video.h
        ${SDL2_INCLUDE_DIR}/SDL_render.h
        ${SDL2_INCLUDE_DIR}/SDL_pixels.h
        ${SDL2_INCLUDE_DIR}/SDL_rect.h
        ${SDL2_INCLUDE_DIR}/SDL_surface.h
        ${SDL2_INCLUDE_DIR}/SDL_clipboard.h
        ${SDL2_INCLUDE_DIR}/SDL_vulkan.h
        ${SDL2_INCLUDE_DIR}/SDL_metal.h
        ${SDL2_INCLUDE_DIR}/SDL_events.h
        ${SDL2_INCLUDE_DIR}/SDL_keyboard.h
        ${SDL2_INCLUDE_DIR}/SDL_keycode.h
        ${SDL2_INCLUDE_DIR}/SDL_scancode.h
        ${SDL2_INCLUDE_DIR}/SDL_mouse.h
        ${SDL2_INCLUDE_DIR}/SDL_joystick.h
        ${SDL2_INCLUDE_DIR}/SDL_gamecontroller.h
        ${SDL2_INCLUDE_DIR}/SDL_sensor.h
        ${SDL2_INCLUDE_DIR}/SDL_haptic.h
        ${SDL2_INCLUDE_DIR}/SDL_audio.h
        ${SDL2_INCLUDE_DIR}/SDL_thread.h
        ${SDL2_INCLUDE_DIR}/SDL_mutex.h
        ${SDL2_INCLUDE_DIR}/SDL_atomic.h
        ${SDL2_INCLUDE_DIR}/SDL_timer.h
        ${SDL2_INCLUDE_DIR}/SDL_filesystem.h
        ${SDL2_INCLUDE_DIR}/SDL_rwops.h
        ${SDL2_INCLUDE_DIR}/SDL_loadso.h
        ${SDL2_INCLUDE_DIR}/SDL_platform.h
        ${SDL2_INCLUDE_DIR}/SDL_cpuinfo.h
        ${SDL2_INCLUDE_DIR}/SDL_endian.h
        ${SDL2_INCLUDE_DIR}/SDL_bits.h
        ${SDL2_INCLUDE_DIR}/SDL_power.h
        ${SDL2_INCLUDE_DIR}/SDL_messagebox.h
        ${SDL2_INCLUDE_DIR}/SDL_system.h
        ${SDL2_INCLUDE_DIR}/SDL_stdinc.h
        ${SDL2_INCLUDE_DIR}/SDL_blendmode.h
        ${SDL2_INCLUDE_DIR}/SDL_guid.h
        --import vulkan
        --imported ${Vulkan_INCLUDE_DIRS}/vulkan/vulkan.h
        --imported ${Vulkan_INCLUDE_DIRS}/vulkan/vulkan_core.h
        --define size_t=uintptr_t
        --output sdl2.slang
    COMMENT "Generating SDL2 bindings"
)

add_custom_command(
    OUTPUT stb_image.slang
    COMMAND ${Python3_EXECUTABLE} ${BINDGEN}
        ${CMAKE_CURRENT_SOURCE_DIR}/external/stb/stb_image.h
        --define size_t=uintptr_t
        --output stb_image.slang
    COMMENT "Generating stb_image bindings"
)

add_custom_target(bindgen DEPENDS sdl2.slang vulkan.slang vulkanmemoryallocator.slang stb_image.slang)

add_library(external-funcs STATIC
    external/vulkan_ext_trampoline.c
    external/vk_mem_alloc.cc
    external/stb.c
)

#===============================================================================
# Building shaders
#===============================================================================
function(add_shader target)
    if(NOT TARGET shaders)
        add_custom_target(shaders)
    endif()
    foreach(source ${ARGN})
        get_filename_component(shader_bin_name ${source} NAME)
        string(REPLACE "\." "_" shader_bin_name ${shader_bin_name})
        string(CONCAT binary ${source} ".spv")

        list(TRANSFORM SHADER_INCLUDE_DIRS PREPEND "-I" OUTPUT_VARIABLE SHADER_INCLUDE_ARGS)

        add_custom_command(
            OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${binary}
            COMMAND ${CMAKE_Slang_COMPILER} -fvk-use-gl-layout -fvk-use-entrypoint-name -matrix-layout-row-major -target spirv -O2 ${CMAKE_CURRENT_SOURCE_DIR}/${source} -o ${CMAKE_CURRENT_BINARY_DIR}/${binary} ${SHADER_INCLUDE_ARGS}
            COMMAND_EXPAND_LISTS
            MAIN_DEPENDENCY ${CMAKE_CURRENT_SOURCE_DIR}/${source}
            DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/${source}
            IMPLICIT_DEPENDS Slang ${CMAKE_CURRENT_SOURCE_DIR}/${source}
            VERBATIM
        )
        add_custom_target(${binary}_target DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/${binary})
        add_dependencies(${target} ${binary}_target)
        add_dependencies(shaders ${binary}_target)
    endforeach()
endfunction()

#===============================================================================
# Building demo executable
#===============================================================================
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/external/slang-cpu-utils/lib" lib)

add_compile_definitions("TARGET_CPU")
add_executable(demo main.slang window.slang vulkan.slang vulkanmemoryallocator.slang sdl2.slang gfx.slang)
add_shader(demo visualize.slang)
add_dependencies(demo bindgen)

# Hack: needed because bindings get generated in the binary dir of CMake
target_include_directories(demo PUBLIC "${CMAKE_CURRENT_BINARY_DIR}")
set(CMAKE_Slang_LINK_FLAGS "-I ${CMAKE_CURRENT_BINARY_DIR}")

set_target_properties(demo PROPERTIES LINKER_LANGUAGE Slang)
target_link_libraries(demo PRIVATE scl)
target_link_libraries(demo PUBLIC SDL2::SDL2 Vulkan::Vulkan external-funcs)
