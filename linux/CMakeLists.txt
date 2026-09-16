# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

# Project-level configuration.
set(PROJECT_NAME "pipewire_telephony_native")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PWT_PREBUILT_LIBRARY "" CACHE FILEPATH
  "Absolute path to a target-built libpipewire_telephony_native.so")
set(PWT_EXPECTED_ELF_MACHINE "" CACHE STRING
  "readelf Machine value required for a prebuilt library")

if(PWT_PREBUILT_LIBRARY)
  if(NOT IS_ABSOLUTE "${PWT_PREBUILT_LIBRARY}")
    message(FATAL_ERROR "PWT_PREBUILT_LIBRARY must be an absolute path")
  endif()
  if(NOT PWT_EXPECTED_ELF_MACHINE)
    message(FATAL_ERROR
      "PWT_EXPECTED_ELF_MACHINE is required with PWT_PREBUILT_LIBRARY")
  endif()
  string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" pwt_system_processor)
  if(pwt_system_processor MATCHES "^(aarch64|arm64)$")
    set(pwt_cmake_elf_machine "AArch64")
  elseif(pwt_system_processor MATCHES "^(x86_64|amd64)$")
    set(pwt_cmake_elf_machine "Advanced Micro Devices X86-64")
  elseif(pwt_system_processor MATCHES "^arm")
    set(pwt_cmake_elf_machine "ARM")
  elseif(pwt_system_processor MATCHES "^riscv64$")
    set(pwt_cmake_elf_machine "RISC-V")
  endif()
  if(DEFINED pwt_cmake_elf_machine AND
      NOT "${PWT_EXPECTED_ELF_MACHINE}" STREQUAL "${pwt_cmake_elf_machine}")
    message(FATAL_ERROR
      "PWT_EXPECTED_ELF_MACHINE does not match CMAKE_SYSTEM_PROCESSOR")
  endif()
  execute_process(
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/../scripts/validate_native_library.sh"
      "${PWT_PREBUILT_LIBRARY}" "${PWT_EXPECTED_ELF_MACHINE}"
    RESULT_VARIABLE validation_result
    OUTPUT_VARIABLE validation_output
    ERROR_VARIABLE validation_error
  )
  if(NOT validation_result EQUAL 0)
    message(FATAL_ERROR
      "Invalid PipeWire telephony prebuilt:\n${validation_output}${validation_error}")
  endif()
  add_library(pipewire_telephony_native_prebuilt SHARED IMPORTED GLOBAL)
  set_target_properties(pipewire_telephony_native_prebuilt PROPERTIES
    IMPORTED_LOCATION "${PWT_PREBUILT_LIBRARY}"
  )
  set(PWT_BUNDLED_LIBRARY $<TARGET_FILE:pipewire_telephony_native_prebuilt>)
else()
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../native"
    "${CMAKE_CURRENT_BINARY_DIR}/shared")
  set(PWT_BUNDLED_LIBRARY $<TARGET_FILE:pipewire_telephony_native>)
endif()

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
if(CMAKE_CURRENT_SOURCE_DIR STREQUAL CMAKE_SOURCE_DIR)
  set(pipewire_telephony_native_bundled_libraries ${PWT_BUNDLED_LIBRARY})
else()
  set(pipewire_telephony_native_bundled_libraries
    ${PWT_BUNDLED_LIBRARY}
    PARENT_SCOPE
  )
endif()
