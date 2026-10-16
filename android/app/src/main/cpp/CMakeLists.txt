# ============================================================
# As Above, So Below. As Within, So Without.
# The Future Dictates the Past and the Past is Always Present.
# ============================================================

cmake_minimum_required(VERSION 3.22.1)
project(sovereign_whistle CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if (${ANDROID_ABI} STREQUAL "arm64-v8a")
    add_definitions(-DWHISTLE_ARM64_SUPPORTED=1)

    add_library(needle_static STATIC IMPORTED)
    set_target_properties(needle_static PROPERTIES
        IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/arm64-v8a/libneedle.a"
    )

    add_library(sovereign_whistle SHARED sovereign_whistle.cpp)
    target_include_directories(sovereign_whistle PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
    target_link_libraries(sovereign_whistle PRIVATE needle_static log)
else()
    add_definitions(-DWHISTLE_ARM64_SUPPORTED=0)
    add_library(sovereign_whistle SHARED sovereign_whistle.cpp)
    target_include_directories(sovereign_whistle PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
    target_link_libraries(sovereign_whistle PRIVATE log)
endif()
