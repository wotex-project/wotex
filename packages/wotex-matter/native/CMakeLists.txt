cmake_minimum_required(VERSION 3.25)

project(wotex_matter_native LANGUAGES CXX)

option(WOTEX_MATTER_SANITIZERS "Enable address and undefined-behavior sanitizers" OFF)
set(WOTEX_MATTER_SDK_ROOT "" CACHE PATH "Path to the pinned connectedhomeip source tree")
set(WOTEX_MATTER_JSON_INCLUDE "" CACHE PATH "Path containing nlohmann/json.hpp")

add_library(wotex_matter_value STATIC src/value.cpp)
target_include_directories(wotex_matter_value PUBLIC include)
target_compile_features(wotex_matter_value PUBLIC cxx_std_17)
target_compile_options(wotex_matter_value PRIVATE -Wall -Wextra -Wpedantic -Werror)

if(WOTEX_MATTER_SANITIZERS)
  target_compile_options(wotex_matter_value PUBLIC -fno-omit-frame-pointer -fsanitize=address,undefined)
  target_link_options(wotex_matter_value PUBLIC -fsanitize=address,undefined)
endif()

enable_testing()

add_executable(wotex_matter_value_test ../test/native/value_test.cpp)
target_link_libraries(wotex_matter_value_test PRIVATE wotex_matter_value)
target_compile_options(wotex_matter_value_test PRIVATE -Wall -Wextra -Wpedantic -Werror)

add_test(NAME wotex_matter_value_test COMMAND wotex_matter_value_test)

if(WOTEX_MATTER_SDK_ROOT AND WOTEX_MATTER_JSON_INCLUDE)
  set(WOTEX_MATTER_SDK_INCLUDES
    "${WOTEX_MATTER_SDK_ROOT}/src"
    "${WOTEX_MATTER_SDK_ROOT}/third_party/nlassert/repo/include"
    "${WOTEX_MATTER_SDK_ROOT}/third_party/nlio/repo/include"
  )

  add_library(wotex_matter_storage STATIC src/storage.cpp)
  target_include_directories(wotex_matter_storage PUBLIC include)
  target_include_directories(
    wotex_matter_storage SYSTEM
    PUBLIC ${WOTEX_MATTER_SDK_INCLUDES}
    PRIVATE "${WOTEX_MATTER_JSON_INCLUDE}"
  )
  target_compile_features(wotex_matter_storage PUBLIC cxx_std_17)
  target_compile_definitions(wotex_matter_storage PUBLIC CHIP_SYSTEM_CONFIG_USE_SOCKETS=1)
  target_compile_options(wotex_matter_storage PRIVATE -Wall -Wextra -Wpedantic -Werror)

  add_library(wotex_matter_sdk_storage_binding OBJECT src/sdk_storage.cpp)
  target_include_directories(wotex_matter_sdk_storage_binding PRIVATE include)
  target_include_directories(
    wotex_matter_sdk_storage_binding SYSTEM
    PRIVATE ${WOTEX_MATTER_SDK_INCLUDES}
  )
  target_compile_features(wotex_matter_sdk_storage_binding PRIVATE cxx_std_17)
  target_compile_definitions(
    wotex_matter_sdk_storage_binding
    PRIVATE CHIP_SYSTEM_CONFIG_USE_SOCKETS=1
  )
  target_compile_options(
    wotex_matter_sdk_storage_binding
    PRIVATE -Wall -Wextra -Wpedantic -Werror
  )

  add_library(wotex_matter_storage_test_library STATIC src/storage.cpp)
  target_include_directories(wotex_matter_storage_test_library PUBLIC include)
  target_include_directories(
    wotex_matter_storage_test_library SYSTEM
    PUBLIC ${WOTEX_MATTER_SDK_INCLUDES}
    PRIVATE "${WOTEX_MATTER_JSON_INCLUDE}"
  )
  target_compile_features(wotex_matter_storage_test_library PUBLIC cxx_std_17)
  target_compile_definitions(
    wotex_matter_storage_test_library
    PUBLIC CHIP_SYSTEM_CONFIG_USE_SOCKETS=1 WOTEX_MATTER_STORAGE_TESTING=1
  )
  target_compile_options(
    wotex_matter_storage_test_library
    PRIVATE -Wall -Wextra -Wpedantic -Werror
  )

  add_executable(wotex_matter_storage_test ../test/native/storage_test.cpp)
  target_include_directories(
    wotex_matter_storage_test SYSTEM
    PRIVATE "${WOTEX_MATTER_JSON_INCLUDE}"
  )
  target_link_libraries(wotex_matter_storage_test PRIVATE wotex_matter_storage_test_library)
  target_compile_options(
    wotex_matter_storage_test
    PRIVATE -Wall -Wextra -Wpedantic -Werror
  )
  add_test(NAME wotex_matter_storage_test COMMAND wotex_matter_storage_test)

  if(WOTEX_MATTER_SANITIZERS)
    foreach(target wotex_matter_storage wotex_matter_storage_test_library)
      target_compile_options(${target} PUBLIC -fno-omit-frame-pointer -fsanitize=address,undefined)
      target_link_options(${target} PUBLIC -fsanitize=address,undefined)
    endforeach()
  endif()
endif()
