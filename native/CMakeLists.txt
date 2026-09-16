cmake_minimum_required(VERSION 3.22)
project(pipewire_telephony_native_library VERSION 0.0.1 LANGUAGES C CXX)

option(PWT_BUILD_DART_INTEGRATION_TESTS
  "Run Dart tests that load the native shared library" ON)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(SDBUSCPP_BUILD_CODEGEN OFF CACHE BOOL "" FORCE)
set(SDBUSCPP_BUILD_DOCS OFF CACHE BOOL "" FORCE)
set(SDBUSCPP_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(SDBUSCPP_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(SDBUSCPP_INSTALL OFF CACHE BOOL "" FORCE)
add_subdirectory(third_party/sdbus-cpp EXCLUDE_FROM_ALL)

add_library(pwt_glaze INTERFACE)
target_include_directories(pwt_glaze INTERFACE third_party/glaze/include)
target_compile_features(pwt_glaze INTERFACE cxx_std_23)

set(PIPEWIRE_TELEPHONY_CORE_SOURCES
  src/dart_api_dl.c
  src/client_context.cpp
  src/command_queue.cpp
  src/gateway_registry.cpp
  src/telephony_codec.cpp
)

add_library(pipewire_telephony_native_core STATIC
  ${PIPEWIRE_TELEPHONY_CORE_SOURCES}
)

target_include_directories(pipewire_telephony_native_core
  PUBLIC include generated
)

target_compile_definitions(pipewire_telephony_native_core
  PUBLIC DART_SHARED_LIB
)

target_link_libraries(pipewire_telephony_native_core
  PUBLIC sdbus-c++ pwt_glaze pthread
)

set_target_properties(pipewire_telephony_native_core PROPERTIES
  LINKER_LANGUAGE CXX
)

add_library(pipewire_telephony_native SHARED
  src/telephony_bridge.cpp
)

target_include_directories(pipewire_telephony_native
  PRIVATE include
)

target_compile_definitions(pipewire_telephony_native
  PUBLIC DART_SHARED_LIB
)

target_link_libraries(pipewire_telephony_native
  PRIVATE pipewire_telephony_native_core
)

set_target_properties(pipewire_telephony_native PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN YES
  LINKER_LANGUAGE CXX
  PUBLIC_HEADER include/pipewire_telephony_native.h
  OUTPUT_NAME "pipewire_telephony_native"
)

if(UNIX AND NOT APPLE)
  target_link_options(pipewire_telephony_native PRIVATE
    "-Wl,--exclude-libs,ALL"
    "-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/exports.map"
  )
endif()

if(BUILD_TESTING)
  enable_testing()
  add_subdirectory(test)
endif()
