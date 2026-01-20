//
//  RecMemoryIOS.h
//  ARMSX2
//
//  iOS recompiler memory management for PCSX2
//

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>

// Initialize recompiler memory system
void RecMemory_iOS_Initialize(void);

// Shutdown recompiler memory system
void RecMemory_iOS_Shutdown(void);

// Allocate executable memory for recompiler
void* RecMemory_iOS_AllocateCode(size_t size);

// Free recompiler code
void RecMemory_iOS_FreeCode(void* ptr);

// Get writable pointer for code
void* RecMemory_iOS_GetWritablePointer(const void* code_ptr);

// Flush instruction cache
void RecMemory_iOS_FlushCache(const void* code_ptr, size_t size);

#ifdef __cplusplus
}
#endif

#ifdef __cplusplus

// C++ interface for PCSX2
namespace RecMemoryIOS
{
    // Initialize the system
    bool Initialize();

    // Shutdown the system
    void Shutdown();

    // Allocate executable code memory
    void* AllocateCode(size_t size);

    // Free code memory
    void FreeCode(void* ptr);

    // Get writable pointer (for writing code)
    void* GetWritablePointer(const void* code_ptr);

    // Flush instruction cache after writing code
    void FlushCache(const void* code_ptr, size_t size);

    // RAII helper for writing to JIT memory
    class CodeWriter
    {
    public:
        CodeWriter(void* code_ptr, size_t size)
            : m_code_ptr(code_ptr)
            , m_writable_ptr(GetWritablePointer(code_ptr))
            , m_size(size)
        {
        }

        ~CodeWriter()
        {
            if (m_code_ptr)
            {
                FlushCache(m_code_ptr, m_size);
            }
        }

        void* GetWritablePointer() const { return m_writable_ptr; }

        template<typename T>
        T* GetWritablePointerAs() const { return static_cast<T*>(m_writable_ptr); }

    private:
        void* m_code_ptr;
        void* m_writable_ptr;
        size_t m_size;
    };
}

#endif
