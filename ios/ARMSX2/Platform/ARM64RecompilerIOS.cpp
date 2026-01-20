//
//  ARM64RecompilerIOS.cpp
//  ARMSX2
//
//  iOS-specific ARM64 recompiler integration for PCSX2
//

#include "RecMemoryIOS.h"
#include "common/Pcsx2Defs.h"
#include <cstdlib>
#include <cstring>

// Override PCSX2's ARM64 assembler memory management for iOS
extern "C" {

// Global variables used by PCSX2's ARM64 recompiler
thread_local uint8_t* armAsmPtr = nullptr;
thread_local size_t armAsmCapacity = 0;

// ARM64 code block allocation
void* armAllocateCodeBlock(size_t size)
{
    void* ptr = RecMemoryIOS::AllocateCode(size);
    if (ptr)
    {
        armAsmPtr = static_cast<uint8_t*>(ptr);
        armAsmCapacity = size;
    }
    return ptr;
}

// ARM64 code block freeing
void armFreeCodeBlock(void* ptr)
{
    if (ptr)
    {
        RecMemoryIOS::FreeCode(ptr);
        if (armAsmPtr == ptr)
        {
            armAsmPtr = nullptr;
            armAsmCapacity = 0;
        }
    }
}

// Get writable pointer for ARM64 code generation
void* armGetWritableCodePointer(const void* code_ptr)
{
    return RecMemoryIOS::GetWritablePointer(code_ptr);
}

// Finalize ARM64 code (flush caches)
void armFinalizeCodeBlock(const void* code_ptr, size_t size)
{
    RecMemoryIOS::FlushCache(code_ptr, size);
}

} // extern "C"

namespace ARM64RecompilerIOS
{
    // Initialize iOS-specific ARM64 recompiler
    bool Initialize()
    {
        return RecMemoryIOS::Initialize();
    }

    // Shutdown iOS-specific ARM64 recompiler
    void Shutdown()
    {
        RecMemoryIOS::Shutdown();
    }

    // Helper class for managing ARM64 code blocks
    class CodeBlock
    {
    public:
        CodeBlock(size_t size)
            : m_size(size)
            , m_code_ptr(nullptr)
            , m_writable_ptr(nullptr)
        {
            m_code_ptr = RecMemoryIOS::AllocateCode(size);
            if (m_code_ptr)
            {
                m_writable_ptr = RecMemoryIOS::GetWritablePointer(m_code_ptr);
            }
        }

        ~CodeBlock()
        {
            if (m_code_ptr)
            {
                RecMemoryIOS::FreeCode(m_code_ptr);
            }
        }

        void* GetExecutablePointer() const { return m_code_ptr; }
        void* GetWritablePointer() const { return m_writable_ptr; }
        size_t GetSize() const { return m_size; }
        bool IsValid() const { return m_code_ptr != nullptr && m_writable_ptr != nullptr; }

        void Finalize(size_t used_size)
        {
            if (m_code_ptr)
            {
                RecMemoryIOS::FlushCache(m_code_ptr, used_size);
            }
        }

        // Prevent copying
        CodeBlock(const CodeBlock&) = delete;
        CodeBlock& operator=(const CodeBlock&) = delete;

    private:
        size_t m_size;
        void* m_code_ptr;
        void* m_writable_ptr;
    };
}
