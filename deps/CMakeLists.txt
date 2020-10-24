cmake_minimum_required(VERSION 3.1)

project(bindbc_imgui)

set(CMAKE_DEBUG_POSTFIX "")

add_subdirectory(SDL)

set(OutputDirectory ${CMAKE_CURRENT_LIST_DIR}/../lib)

option(BUILD_SHARED_LIBS     "Build shared instead of static libraries." ON)
option(OPTION_BUILD_TOOLS    "Build tools."                              OFF)
option(OPTION_BUILD_EXAMPLES "Build examples."                           OFF)
add_subdirectory(glbinding)

set(IMGUI_SDL "yes" CACHE STRING "Build with SDL")
set(IMGUI_OPENGL3 "yes" CACHE STRING "Build with OpenGL3")
add_subdirectory(cimgui)

set_target_properties(cimgui PROPERTIES DEBUG_POSTFIX "")
set_target_properties(glbinding PROPERTIES DEBUG_POSTFIX "")
set_target_properties(SDL2 PROPERTIES DEBUG_POSTFIX "")

set_target_properties(cimgui PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY ${aLibraryDirectory}
    LIBRARY_OUTPUT_DIRECTORY ${aLibraryDirectory}
    RUNTIME_OUTPUT_DIRECTORY ${OutputDirectory})

set_target_properties(glbinding PROPERTIES 
    ARCHIVE_OUTPUT_DIRECTORY ${OutputDirectory}
    LIBRARY_OUTPUT_DIRECTORY ${OutputDirectory}
    RUNTIME_OUTPUT_DIRECTORY ${OutputDirectory})
set_target_properties(SDL2 PROPERTIES 
    ARCHIVE_OUTPUT_DIRECTORY ${OutputDirectory}
    LIBRARY_OUTPUT_DIRECTORY ${OutputDirectory}
    RUNTIME_OUTPUT_DIRECTORY ${OutputDirectory})
