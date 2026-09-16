add_executable(test_telephony_codec test_telephony_codec.cpp)
target_link_libraries(test_telephony_codec PRIVATE pipewire_telephony_native_core)
target_compile_definitions(test_telephony_codec PRIVATE
  PWT_FIXTURE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/../../test/fixtures"
)
add_test(NAME telephony_codec COMMAND test_telephony_codec)

add_executable(test_lifecycle test_lifecycle.cpp)
target_link_libraries(test_lifecycle
  PRIVATE pipewire_telephony_native pipewire_telephony_native_core
)
add_test(NAME lifecycle COMMAND test_lifecycle)
