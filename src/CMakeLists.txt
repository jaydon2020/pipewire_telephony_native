# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(pipewire_telephony_native_library VERSION 0.0.1 LANGUAGES C)

add_library(pipewire_telephony_native SHARED
  "pipewire_telephony_native.c"
)

set_target_properties(pipewire_telephony_native PROPERTIES
  PUBLIC_HEADER pipewire_telephony_native.h
  OUTPUT_NAME "pipewire_telephony_native"
)

target_compile_definitions(pipewire_telephony_native PUBLIC DART_SHARED_LIB)

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(pipewire_telephony_native PRIVATE "-Wl,-z,max-page-size=16384")
endif()
