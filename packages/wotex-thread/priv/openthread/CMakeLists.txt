cmake_minimum_required(VERSION 3.16)
project(wotex_thread_native LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
option(WOTEX_NATIVE_SANITIZERS "Enable address and undefined-behavior sanitizers" OFF)
set(WOTEX_NATIVE_TEST_SOURCE "" CACHE PATH "Explicit source directory containing native tests")

set(json_header "${CMAKE_BINARY_DIR}/include/nlohmann/json.hpp")
file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/include/nlohmann")
file(DOWNLOAD
  "https://raw.githubusercontent.com/nlohmann/json/v3.11.3/single_include/nlohmann/json.hpp"
  "${json_header}"
  EXPECTED_HASH SHA256=9bea4c8066ef4a1c206b2be5a36302f8926f7fdc6087af5d20b417d0cf103ea6
  TLS_VERIFY ON TIMEOUT 120)

add_library(wotex-thread-protocol INTERFACE)
target_include_directories(wotex-thread-protocol INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}")
target_include_directories(wotex-thread-protocol SYSTEM INTERFACE "${CMAKE_BINARY_DIR}/include")
target_compile_options(wotex-thread-protocol INTERFACE -Wall -Wextra -Wpedantic -Werror)
if(WOTEX_NATIVE_SANITIZERS)
  target_compile_options(wotex-thread-protocol INTERFACE -fsanitize=address,undefined -fno-omit-frame-pointer)
  target_link_options(wotex-thread-protocol INTERFACE -fsanitize=address,undefined)
endif()

if(WOTEX_NATIVE_TEST_SOURCE)
  enable_testing()
  add_executable(wotex-thread-protocol-test "${WOTEX_NATIVE_TEST_SOURCE}/protocol_test.cpp")
  target_link_libraries(wotex-thread-protocol-test PRIVATE wotex-thread-protocol)
  add_test(NAME WTH-C07-WTH-V04 COMMAND wotex-thread-protocol-test)
  add_executable(wotex-thread-storage-test "${WOTEX_NATIVE_TEST_SOURCE}/storage_test.cpp")
  target_link_libraries(wotex-thread-storage-test PRIVATE wotex-thread-protocol)
  add_test(NAME WTH-S03-WTH-V04 COMMAND wotex-thread-storage-test)
  set_tests_properties(WTH-C07-WTH-V04 WTH-S03-WTH-V04 PROPERTIES TIMEOUT 30)
endif()
