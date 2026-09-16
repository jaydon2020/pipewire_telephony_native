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

set(PWT_GTEST_ROOT
  "${PROJECT_SOURCE_DIR}/third_party/googletest/googletest"
)
add_library(pwt_gtest_main STATIC
  "${PWT_GTEST_ROOT}/src/gtest-all.cc"
  "${PWT_GTEST_ROOT}/src/gtest_main.cc"
)
target_include_directories(pwt_gtest_main PUBLIC
  "${PWT_GTEST_ROOT}/include"
  PRIVATE "${PWT_GTEST_ROOT}"
)
target_link_libraries(pwt_gtest_main PUBLIC pthread)

add_library(pwt_test_support STATIC
  support/mock_telephony_service.cpp
)
target_include_directories(pwt_test_support PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_link_libraries(pwt_test_support PUBLIC sdbus-c++)

add_executable(test_mock_telephony_service test_mock_telephony_service.cpp)
target_link_libraries(test_mock_telephony_service
  PRIVATE pwt_test_support pwt_gtest_main
)
find_program(DBUS_RUN_SESSION dbus-run-session REQUIRED)
add_test(NAME mock_telephony_service
  COMMAND "${DBUS_RUN_SESSION}" -- $<TARGET_FILE:test_mock_telephony_service>
)
set_tests_properties(mock_telephony_service PROPERTIES TIMEOUT 15)
