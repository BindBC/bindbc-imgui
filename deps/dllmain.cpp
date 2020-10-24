#include <glbinding/glbinding.h>

#if defined _MSC_VER
  #define INITIALIZE_FOR_IMGUI_DLL_EXPORTED __declspec(dllexport)
#else
  #define INITIALIZE_FOR_IMGUI_DLL_EXPORTED __attribute__((__visibility__("default")))
#endif

extern "C"
{
    INITIALIZE_FOR_IMGUI_DLL_EXPORTED void InitOpenGLForImGui()
    {
        glbinding::initialize(nullptr);
    }
}

#if WIN32
#include "Windows.h"

BOOL WINAPI DllMain(
    HINSTANCE hinstDLL,  // handle to DLL module
    DWORD fdwReason,     // reason for calling function
    LPVOID lpReserved )  // reserved
{
    // Perform actions based on the reason for calling.
    switch( fdwReason ) 
    { 
        case DLL_PROCESS_ATTACH:
         // Initialize once for each new process.
         // Return FALSE to fail DLL load.
            break;

        case DLL_THREAD_ATTACH:
         // Do thread-specific initialization.
            break;

        case DLL_THREAD_DETACH:
         // Do thread-specific cleanup.
            break;

        case DLL_PROCESS_DETACH:
         // Perform any necessary cleanup.
            break;
    }
    return TRUE;  // Successful DLL_PROCESS_ATTACH.
}
#endif