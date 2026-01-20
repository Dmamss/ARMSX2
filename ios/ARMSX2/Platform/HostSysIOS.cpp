//
//  HostSysIOS.cpp
//  ARMSX2
//
//  iOS-specific HostSys implementation for JIT code management
//

#include "common/HostSys.h"
#include "RecMemoryIOS.h"
#include <sys/mman.h>
#include <libkern/OSCacheControl.h>

// Current writable pointer for JIT code (thread-local)
static thread_local void* s_current_code_writable = nullptr;
static thread_local const void* s_current_code_executable = nullptr;
static thread_local size_t s_current_code_size = 0;

namespace HostSys
{
    // Begin writing JIT code - get writable pointer for current code region
    void BeginCodeWrite()
    {
        // The ARM64 recompiler will use armAsmPtr which is already set
        // We just need to track it so we can get the writable mirror
        extern thread_local uint8_t* armAsmPtr;
        extern thread_local size_t armAsmCapacity;

        if (armAsmPtr && armAsmCapacity > 0)
        {
            s_current_code_executable = armAsmPtr;
            s_current_code_size = armAsmCapacity;
            s_current_code_writable = RecMemory_iOS_GetWritablePointer(armAsmPtr);

            // Update armAsmPtr to point to writable memory
            armAsmPtr = static_cast<uint8_t*>(s_current_code_writable);
        }
    }

    // End writing JIT code - restore executable pointer and flush cache
    void EndCodeWrite()
    {
        extern thread_local uint8_t* armAsmPtr;

        if (s_current_code_executable && s_current_code_writable)
        {
            // Restore executable pointer
            armAsmPtr = static_cast<uint8_t*>(const_cast<void*>(s_current_code_executable));

            // Flush will be done by armEndBlock() which calls FlushInstructionCache
            s_current_code_writable = nullptr;
            s_current_code_executable = nullptr;
            s_current_code_size = 0;
        }
    }

    // Flush instruction cache for JIT code
    void FlushInstructionCache(void* address, u32 size)
    {
        if (address && size > 0)
        {
            RecMemory_iOS_FlushCache(address, size);
        }
    }

    // Memory allocation functions (required by HostSys)
    void* Mmap(void* base, size_t size)
    {
        // Use our JIT allocator
        void* ptr = RecMemory_iOS_AllocateCode(size);
        if (ptr && base && ptr != base)
        {
            // Requested specific base address but got different one
            // This is OK for most cases, PCSX2 can handle it
        }
        return ptr;
    }

    void Munmap(void* base, size_t size)
    {
        if (base)
        {
            RecMemory_iOS_FreeCode(base);
        }
    }

    void MemProtect(void* baseaddr, size_t size, const PageProtectionMode& mode)
    {
        // Protection is handled by vm_remap mirroring
        // R/X and R/W mirrors already have correct permissions
        // Nothing to do here
    }

    std::string GetFileMappingName(const char* prefix)
    {
        // Not used on iOS
        return "";
    }

    void* CreateSharedMemory(const char* name, size_t size)
    {
        // Use regular JIT allocation
        return RecMemory_iOS_AllocateCode(size);
    }

    void DestroySharedMemory(const char* name)
    {
        // Nothing to do, memory will be freed via Munmap
    }

    void* MapSharedMemory(void* handle, size_t offset, void* baseaddr, size_t size, const PageProtectionMode& mode)
    {
        // Return the base address as-is
        return baseaddr;
    }

    void UnmapSharedMemory(void* baseaddr, size_t size)
    {
        // Will be freed via Munmap
    }
}
