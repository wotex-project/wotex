cmake_minimum_required(VERSION 3.20)
project(wotex_opcua_native VERSION 1.0.0 LANGUAGES C)

if(NOT IS_ABSOLUTE "${WOTEX_SDK_PREFIX}" OR NOT IS_ABSOLUTE "${WOTEX_OPENSSL_PREFIX}")
  message(FATAL_ERROR "Explicit absolute SDK and OpenSSL prefixes are required")
endif()
set(OPENSSL_USE_STATIC_LIBS TRUE)
set(OPENSSL_ROOT_DIR "${WOTEX_OPENSSL_PREFIX}")
set(OPENSSL_INCLUDE_DIR "${WOTEX_OPENSSL_PREFIX}/include")
set(OPENSSL_SSL_LIBRARY "${WOTEX_OPENSSL_PREFIX}/lib/libssl.a")
set(OPENSSL_CRYPTO_LIBRARY "${WOTEX_OPENSSL_PREFIX}/lib/libcrypto.a")
# Keep FindPkgConfig's commands available to older FindOpenSSL modules while
# disabling executable discovery and all pkg-config hints.
set(PKG_CONFIG_EXECUTABLE "" CACHE FILEPATH "No ambient pkg-config executable" FORCE)
set(PKG_CONFIG_ARGN "" CACHE STRING "No ambient pkg-config arguments" FORCE)
find_package(OpenSSL 3.5.8 EXACT REQUIRED)
find_package(open62541 1.5.7 EXACT CONFIG REQUIRED NO_DEFAULT_PATH
             PATHS "${WOTEX_SDK_PREFIX}/lib/cmake/open62541")

add_executable(wotex_opcua_native main.c)
target_compile_features(wotex_opcua_native PRIVATE c_std_99)
target_compile_definitions(wotex_opcua_native PRIVATE _POSIX_C_SOURCE=200809L)
target_compile_options(wotex_opcua_native PRIVATE -Wall -Wextra -Werror)
target_include_directories(wotex_opcua_native PRIVATE "${OPENSSL_INCLUDE_DIR}")
target_link_libraries(wotex_opcua_native PRIVATE wotex_opcua_security)

add_library(wotex_opcua_security STATIC security.c session_config.c session_open.c ipc.c output.c owner.c)
target_compile_features(wotex_opcua_security PRIVATE c_std_11)
target_compile_definitions(wotex_opcua_security PRIVATE _POSIX_C_SOURCE=200809L)
target_compile_options(wotex_opcua_security PRIVATE -Wall -Wextra -Werror)
target_include_directories(wotex_opcua_security PUBLIC "${OPENSSL_INCLUDE_DIR}")
target_link_libraries(wotex_opcua_security PUBLIC wotex_opcua_json open62541::open62541)
add_executable(wotex_opcua_security_check security_check.c)
target_compile_features(wotex_opcua_security_check PRIVATE c_std_11)
target_compile_options(wotex_opcua_security_check PRIVATE -Wall -Wextra -Werror)
target_link_libraries(wotex_opcua_security_check PRIVATE wotex_opcua_security)
add_executable(wotex_opcua_session_probe session_probe.c)
target_compile_features(wotex_opcua_session_probe PRIVATE c_std_11)
target_compile_definitions(wotex_opcua_session_probe PRIVATE _POSIX_C_SOURCE=200809L)
target_compile_options(wotex_opcua_session_probe PRIVATE -Wall -Wextra -Werror)
target_link_libraries(wotex_opcua_session_probe PRIVATE wotex_opcua_security)
add_executable(wotex_opcua_browse_check browse_check.c)
target_compile_features(wotex_opcua_browse_check PRIVATE c_std_11)
target_compile_options(wotex_opcua_browse_check PRIVATE -Wall -Wextra -Werror)
target_link_libraries(wotex_opcua_browse_check PRIVATE wotex_opcua_security)
add_executable(wotex_opcua_paged_peer paged_peer.c)
target_compile_features(wotex_opcua_paged_peer PRIVATE c_std_11)
target_compile_options(wotex_opcua_paged_peer PRIVATE -Wall -Wextra -Werror)
target_link_libraries(wotex_opcua_paged_peer PRIVATE open62541::open62541)
add_executable(wotex_opcua_sdk_revision_check sdk_revision_check.c)
target_compile_features(wotex_opcua_sdk_revision_check PRIVATE c_std_11)
target_compile_definitions(wotex_opcua_sdk_revision_check PRIVATE _POSIX_C_SOURCE=200809L)
target_compile_options(wotex_opcua_sdk_revision_check PRIVATE -Wall -Wextra -Werror)
target_link_libraries(wotex_opcua_sdk_revision_check PRIVATE open62541::open62541)

add_library(wotex_opcua_json STATIC json_codec.c vendor/yyjson/yyjson.c)
target_compile_features(wotex_opcua_json PRIVATE c_std_11)
target_compile_options(wotex_opcua_json PRIVATE -Wall -Wextra -Werror)
target_compile_definitions(wotex_opcua_json PUBLIC
  YYJSON_DISABLE_NON_STANDARD=1 YYJSON_DISABLE_UTILS=1 YYJSON_DISABLE_INCR_READER=1
  YYJSON_DISABLE_FAST_FP_CONV=0 YYJSON_DISABLE_UTF8_VALIDATION=0)
add_executable(wotex_opcua_json_check json_check.c)
target_compile_features(wotex_opcua_json_check PRIVATE c_std_11)
target_compile_options(wotex_opcua_json_check PRIVATE -Wall -Wextra -Werror)
target_link_libraries(wotex_opcua_json_check PRIVATE wotex_opcua_json)
add_executable(wotex_opcua_ipc_check ipc_check.c ipc.c)
target_compile_features(wotex_opcua_ipc_check PRIVATE c_std_11)
target_compile_options(wotex_opcua_ipc_check PRIVATE -Wall -Wextra -Werror)
target_link_libraries(wotex_opcua_ipc_check PRIVATE wotex_opcua_json)
add_executable(wotex_opcua_output_check output_check.c output.c)
target_compile_features(wotex_opcua_output_check PRIVATE c_std_11)
target_compile_definitions(wotex_opcua_output_check PRIVATE _POSIX_C_SOURCE=200809L)
target_compile_options(wotex_opcua_output_check PRIVATE -Wall -Wextra -Werror)
target_link_libraries(wotex_opcua_output_check PRIVATE wotex_opcua_json)
add_executable(wotex_opcua_owner_check owner_check.c owner.c output.c ipc.c)
target_compile_features(wotex_opcua_owner_check PRIVATE c_std_11)
target_compile_definitions(wotex_opcua_owner_check PRIVATE _POSIX_C_SOURCE=200809L)
target_compile_options(wotex_opcua_owner_check PRIVATE -Wall -Wextra -Werror)
target_link_libraries(wotex_opcua_owner_check PRIVATE wotex_opcua_json)

add_library(wotex_opcua_values STATIC value_codec.c)
target_compile_features(wotex_opcua_values PRIVATE c_std_11)
target_compile_options(wotex_opcua_values PRIVATE -Wall -Wextra -Werror)
target_link_libraries(wotex_opcua_values PUBLIC wotex_opcua_json open62541::open62541)
target_link_libraries(wotex_opcua_security PUBLIC wotex_opcua_values)
add_executable(wotex_opcua_value_check value_check.c)
target_compile_features(wotex_opcua_value_check PRIVATE c_std_11)
target_compile_options(wotex_opcua_value_check PRIVATE -Wall -Wextra -Werror)
target_link_libraries(wotex_opcua_value_check PRIVATE wotex_opcua_values)
add_executable(wotex_opcua_value_fault_check value_fault_check.c)
target_compile_features(wotex_opcua_value_fault_check PRIVATE c_std_11)
target_compile_options(wotex_opcua_value_fault_check PRIVATE -Wall -Wextra -Werror)
target_link_libraries(wotex_opcua_value_fault_check PRIVATE wotex_opcua_values)
add_executable(wotex_opcua_native_contract_check native_contract_check.c)
target_compile_features(wotex_opcua_native_contract_check PRIVATE c_std_11)
target_compile_options(wotex_opcua_native_contract_check PRIVATE -Wall -Wextra -Werror)
target_link_libraries(wotex_opcua_native_contract_check PRIVATE wotex_opcua_values)

add_executable(wotex_opcua_custody custody.c)
add_executable(wotex_opcua_custody_check custody_check.c)
foreach(target wotex_opcua_custody wotex_opcua_custody_check)
  target_compile_features(${target} PRIVATE c_std_11)
  target_compile_options(${target} PRIVATE -Wall -Wextra -Werror)
endforeach()

option(WOTEX_SANITIZERS "Instrument the native host with ASan and UBSan" OFF)
if(WOTEX_SANITIZERS)
  target_sources(wotex_opcua_native PRIVATE sanitizer_options.c)
  foreach(target wotex_opcua_native wotex_opcua_custody wotex_opcua_custody_check
      wotex_opcua_json wotex_opcua_json_check wotex_opcua_ipc_check wotex_opcua_output_check wotex_opcua_owner_check wotex_opcua_values wotex_opcua_value_check
      wotex_opcua_value_fault_check wotex_opcua_native_contract_check
      wotex_opcua_security wotex_opcua_security_check wotex_opcua_session_probe
      wotex_opcua_browse_check wotex_opcua_paged_peer
      wotex_opcua_sdk_revision_check)
    target_compile_options(${target} PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
    target_link_options(${target} PRIVATE -fsanitize=address,undefined)
  endforeach()
endif()

enable_testing()
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/fixtures/value-v1.json" WOTEX_VALUE_FIXTURES)
string(JSON WOTEX_VALUE_COUNT LENGTH "${WOTEX_VALUE_FIXTURES}" cases)
math(EXPR WOTEX_VALUE_LAST "${WOTEX_VALUE_COUNT} - 1")
foreach(index RANGE 0 ${WOTEX_VALUE_LAST})
  string(JSON case_id GET "${WOTEX_VALUE_FIXTURES}" cases ${index} id)
  add_test(NAME native_value_${case_id} COMMAND wotex_opcua_value_check --case
    "${CMAKE_CURRENT_SOURCE_DIR}/fixtures/value-v1.json" "${case_id}")
  set_tests_properties(native_value_${case_id} PROPERTIES TIMEOUT 10
    PASS_REGULAR_EXPRESSION "\"status\":\"passed\"")
endforeach()
foreach(number 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17)
  add_test(NAME native_value_fault_WOP-NF${number} COMMAND wotex_opcua_value_fault_check WOP-NF${number})
  set_tests_properties(native_value_fault_WOP-NF${number} PROPERTIES TIMEOUT 10
    PASS_REGULAR_EXPRESSION "\"status\":\"passed\"")
endforeach()
set(WOTEX_NATIVE_CONTRACT
  "${CMAKE_CURRENT_SOURCE_DIR}/../../docs/specs/fixtures/native-contract-v1.json")
if(NOT EXISTS "${WOTEX_NATIVE_CONTRACT}")
  message(FATAL_ERROR "The native contract fixture is required")
endif()
foreach(number 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16)
  add_test(NAME native_contract_WOP-X-F${number} COMMAND wotex_opcua_native_contract_check
    "${WOTEX_NATIVE_CONTRACT}" WOP-X-F${number})
  set_tests_properties(native_contract_WOP-X-F${number} PROPERTIES TIMEOUT 10
    PASS_REGULAR_EXPRESSION "\"status\":\"passed\"")
endforeach()
foreach(number 17 18 19 20 49 50 52 53 54 55)
  add_test(NAME native_contract_WOP-X-F${number} COMMAND wotex_opcua_owner_check
    "${WOTEX_NATIVE_CONTRACT}" WOP-X-F${number})
  set_tests_properties(native_contract_WOP-X-F${number} PROPERTIES TIMEOUT 20
    PASS_REGULAR_EXPRESSION "\"status\":\"passed\"")
endforeach()
add_test(NAME native_owner_matrix COMMAND wotex_opcua_owner_check --matrix)
set_tests_properties(native_owner_matrix PROPERTIES
  TIMEOUT 60 PASS_REGULAR_EXPRESSION "\"status\":\"passed\"")
add_test(NAME native_json_self_test COMMAND wotex_opcua_json_check --self-test)
set_tests_properties(native_json_self_test PROPERTIES
  TIMEOUT 10 PASS_REGULAR_EXPRESSION "\"status\":\"passed\"")
add_test(NAME native_ipc_admission COMMAND wotex_opcua_ipc_check)
set_tests_properties(native_ipc_admission PROPERTIES
  TIMEOUT 10 PASS_REGULAR_EXPRESSION "\"status\":\"passed\"")
add_test(NAME native_output_queue COMMAND wotex_opcua_output_check)
set_tests_properties(native_output_queue PROPERTIES
  TIMEOUT 10 PASS_REGULAR_EXPRESSION "\"status\":\"passed\"")
add_test(NAME native_security_preflight COMMAND wotex_opcua_security_check)
set_tests_properties(native_security_preflight PROPERTIES
  TIMEOUT 30 PASS_REGULAR_EXPRESSION "\"status\":\"passed\"")
add_test(NAME native_sdk_session_revision COMMAND wotex_opcua_sdk_revision_check)
add_test(NAME native_browse_token_state COMMAND wotex_opcua_browse_check)
set_tests_properties(native_browse_token_state PROPERTIES
  TIMEOUT 10 PASS_REGULAR_EXPRESSION "\"status\":\"passed\"")
set_tests_properties(native_sdk_session_revision PROPERTIES
  TIMEOUT 20 PASS_REGULAR_EXPRESSION "\"status\":\"passed\"")
add_test(NAME native_dependency_self_test COMMAND wotex_opcua_native --self-test)
set_tests_properties(native_dependency_self_test PROPERTIES
  TIMEOUT 10 PASS_REGULAR_EXPRESSION "\"self_test\":\"ok\"")
add_test(NAME native_invalid_arguments COMMAND wotex_opcua_native --unknown)
set_tests_properties(native_invalid_arguments PROPERTIES TIMEOUT 10 WILL_FAIL TRUE)
foreach(number 01 02 03 04 05 06 07 08 09)
  file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/custody-G${number}")
  add_test(NAME custody_G${number} COMMAND wotex_opcua_custody_check
    $<TARGET_FILE:wotex_opcua_custody> WOP-G${number}
    "${CMAKE_CURRENT_BINARY_DIR}/custody-G${number}")
  set_tests_properties(custody_G${number} PROPERTIES TIMEOUT 25
    PASS_REGULAR_EXPRESSION "\"status\":\"passed\"")
  if(WOTEX_SANITIZERS)
    set_tests_properties(custody_G${number} PROPERTIES ENVIRONMENT
      "ASAN_OPTIONS=detect_leaks=0:abort_on_error=1;UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1")
    file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/custody-leak-G${number}")
    add_test(NAME custody_leak_G${number} COMMAND wotex_opcua_custody_check
      $<TARGET_FILE:wotex_opcua_custody> WOP-G${number}
      "${CMAKE_CURRENT_BINARY_DIR}/custody-leak-G${number}" --leak-audit)
    set_tests_properties(custody_leak_G${number} PROPERTIES TIMEOUT 25
      PASS_REGULAR_EXPRESSION "\"status\":\"passed\"" ENVIRONMENT
      "ASAN_OPTIONS=detect_leaks=1:abort_on_error=1;UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1")
  endif()
endforeach()
install(TARGETS wotex_opcua_native wotex_opcua_custody RUNTIME DESTINATION bin)
install(FILES vendor/yyjson/LICENSE DESTINATION share/licenses/yyjson)
