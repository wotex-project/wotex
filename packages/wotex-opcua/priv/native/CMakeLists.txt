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
set(CMAKE_DISABLE_FIND_PACKAGE_PkgConfig TRUE)
find_package(OpenSSL 3.5.8 EXACT REQUIRED)
find_package(open62541 1.5.7 EXACT CONFIG REQUIRED NO_DEFAULT_PATH
             PATHS "${WOTEX_SDK_PREFIX}/lib/cmake/open62541")

add_executable(wotex_opcua_native main.c)
target_compile_features(wotex_opcua_native PRIVATE c_std_99)
target_compile_definitions(wotex_opcua_native PRIVATE _POSIX_C_SOURCE=200809L)
target_compile_options(wotex_opcua_native PRIVATE -Wall -Wextra -Werror)
target_include_directories(wotex_opcua_native PRIVATE "${OPENSSL_INCLUDE_DIR}")
target_link_libraries(wotex_opcua_native PRIVATE open62541::open62541)

add_executable(wotex_opcua_custody custody.c)
add_executable(wotex_opcua_custody_check custody_check.c)
foreach(target wotex_opcua_custody wotex_opcua_custody_check)
  target_compile_features(${target} PRIVATE c_std_11)
  target_compile_options(${target} PRIVATE -Wall -Wextra -Werror)
endforeach()

option(WOTEX_SANITIZERS "Instrument the native host with ASan and UBSan" OFF)
if(WOTEX_SANITIZERS)
  foreach(target wotex_opcua_native wotex_opcua_custody wotex_opcua_custody_check)
    target_compile_options(${target} PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
    target_link_options(${target} PRIVATE -fsanitize=address,undefined)
  endforeach()
endif()

enable_testing()
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
