cmake_minimum_required(VERSION 3.22)
project(pipewire_telephony_native_library VERSION 0.1.0 LANGUAGES C CXX)

option(PWT_BUILD_DART_INTEGRATION_TESTS
  "Run Dart tests that load the native shared library" ON)
option(PWT_REQUIRE_CROSS_COMPILE
  "Fail unless configured by a cross-compiling toolchain with a sysroot" OFF)
option(PWT_HOOK_BUILD "Build is driven by the Dart Native Assets hook" OFF)

if(PWT_REQUIRE_CROSS_COMPILE)
  if(NOT CMAKE_CROSSCOMPILING)
    message(FATAL_ERROR "PWT_REQUIRE_CROSS_COMPILE rejects a host compiler")
  endif()
  if(NOT CMAKE_SYSROOT)
    message(FATAL_ERROR "The target toolchain must define CMAKE_SYSROOT")
  endif()
  if(BUILD_TESTING OR PWT_BUILD_DART_INTEGRATION_TESTS)
    message(FATAL_ERROR "Target binaries must not run during a cross-build")
  endif()
endif()

string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" pwt_processor)
if(pwt_processor MATCHES "^(aarch64|arm64)$")
  set(pwt_elf_machine "AArch64")
elseif(pwt_processor MATCHES "^(x86_64|amd64)$")
  set(pwt_elf_machine "Advanced Micro Devices X86-64")
elseif(pwt_processor MATCHES "^(i[3-6]86|x86)$")
  set(pwt_elf_machine "Intel 80386")
elseif(pwt_processor MATCHES "^arm")
  set(pwt_elf_machine "ARM")
elseif(pwt_processor MATCHES "^riscv64")
  set(pwt_elf_machine "RISC-V")
else()
  message(FATAL_ERROR
    "Unsupported Linux target processor: ${CMAKE_SYSTEM_PROCESSOR}")
endif()

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
  src/call_registry.cpp
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
  PRIVATE pipewire_telephony_native_core ${CMAKE_DL_LIBS}
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

set(pwt_validator
  "${CMAKE_CURRENT_SOURCE_DIR}/../scripts/validate_native_library.sh")
set_property(TARGET pipewire_telephony_native APPEND PROPERTY
  LINK_DEPENDS "${pwt_validator}" "${CMAKE_CURRENT_SOURCE_DIR}/exports.map")
add_custom_command(TARGET pipewire_telephony_native POST_BUILD
  COMMAND "${pwt_validator}"
    "$<TARGET_FILE:pipewire_telephony_native>" "${pwt_elf_machine}"
  VERBATIM
)

if(BUILD_TESTING)
  enable_testing()
  add_subdirectory(test)
endif()
