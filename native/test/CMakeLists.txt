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

add_executable(test_client_connection test_client_connection.cpp)
target_link_libraries(test_client_connection
  PRIVATE pipewire_telephony_native_core pwt_test_support pwt_gtest_main
)
add_test(NAME client_connection
  COMMAND "${DBUS_RUN_SESSION}" -- $<TARGET_FILE:test_client_connection>
)
set_tests_properties(client_connection PROPERTIES TIMEOUT 15)

add_executable(test_gateway_registry test_gateway_registry.cpp)
target_link_libraries(test_gateway_registry
  PRIVATE pipewire_telephony_native_core pwt_test_support pwt_gtest_main
)
add_test(NAME gateway_registry
  COMMAND "${DBUS_RUN_SESSION}" -- $<TARGET_FILE:test_gateway_registry>
)
set_tests_properties(gateway_registry PROPERTIES TIMEOUT 15)

if(PWT_BUILD_DART_INTEGRATION_TESTS)
  add_executable(mock_telephony_server mock_telephony_server.cpp)
  target_link_libraries(mock_telephony_server PRIVATE pwt_test_support)

  find_program(DART_EXECUTABLE dart REQUIRED)
  add_test(NAME dart_client_lifecycle
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run_dart_client_test.sh"
      $<TARGET_FILE:pipewire_telephony_native>
      $<TARGET_FILE:mock_telephony_server>
      "${CMAKE_CURRENT_SOURCE_DIR}/../../test/client_lifecycle_test.dart"
  )
  set_tests_properties(dart_client_lifecycle PROPERTIES
    TIMEOUT 30
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../.."
  )

  add_test(NAME dart_client_access_denied
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run_dart_access_test.sh"
      "${CMAKE_CURRENT_SOURCE_DIR}/private-bus-deny-telephony.conf"
      $<TARGET_FILE:pipewire_telephony_native>
      "${CMAKE_CURRENT_SOURCE_DIR}/../../test/client_access_denied_test.dart"
  )
  set_tests_properties(dart_client_access_denied PROPERTIES
    TIMEOUT 30
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../.."
  )

  add_test(NAME dart_client_auto_bus
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run_dart_auto_bus_test.sh"
      $<TARGET_FILE:pipewire_telephony_native>
      $<TARGET_FILE:mock_telephony_server>
      "${CMAKE_CURRENT_SOURCE_DIR}/../../test/client_auto_bus_test.dart"
  )
  set_tests_properties(dart_client_auto_bus PROPERTIES
    TIMEOUT 30
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../.."
  )

  find_program(FLUTTER_EXECUTABLE flutter REQUIRED)
  add_test(NAME flutter_example
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run_flutter_example_test.sh"
      $<TARGET_FILE:pipewire_telephony_native>
      $<TARGET_FILE:mock_telephony_server>
  )
  set_tests_properties(flutter_example PROPERTIES
    TIMEOUT 45
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../../example/flutter_telephony"
  )
endif()
