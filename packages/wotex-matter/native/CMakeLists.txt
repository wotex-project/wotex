cmake_minimum_required(VERSION 3.25)

project(wotex_matter_native LANGUAGES CXX)

option(WOTEX_MATTER_SANITIZERS "Enable address and undefined-behavior sanitizers" OFF)
set(WOTEX_MATTER_SDK_ROOT "" CACHE PATH "Path to the pinned connectedhomeip source tree")
set(WOTEX_MATTER_JSON_INCLUDE "" CACHE PATH "Path containing nlohmann/json.hpp")

add_library(wotex_matter_value STATIC src/value.cpp src/interaction.cpp src/subscription.cpp src/commissioning.cpp)
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

find_package(Threads REQUIRED)
add_library(wotex_matter_bridge_handoff STATIC src/bridge_handoff.cpp src/bridge_handoff_owner.cpp)
target_include_directories(wotex_matter_bridge_handoff PUBLIC include)
target_link_libraries(wotex_matter_bridge_handoff PUBLIC Threads::Threads)
target_compile_features(wotex_matter_bridge_handoff PUBLIC cxx_std_17)
target_compile_options(wotex_matter_bridge_handoff PRIVATE -Wall -Wextra -Wpedantic -Werror)
if(WOTEX_MATTER_SANITIZERS)
  target_compile_options(wotex_matter_bridge_handoff PUBLIC -fno-omit-frame-pointer -fsanitize=address,undefined)
  target_link_options(wotex_matter_bridge_handoff PUBLIC -fsanitize=address,undefined)
endif()
add_executable(wotex_matter_bridge_handoff_test ../test/native/bridge_handoff_test.cpp)
target_link_libraries(wotex_matter_bridge_handoff_test PRIVATE wotex_matter_bridge_handoff)
target_compile_options(wotex_matter_bridge_handoff_test PRIVATE -Wall -Wextra -Wpedantic -Werror)
add_test(NAME wotex_matter_bridge_handoff_test COMMAND wotex_matter_bridge_handoff_test)

add_executable(wotex_matter_bridge_handoff_owner_test ../test/native/bridge_handoff_owner_test.cpp)
target_link_libraries(wotex_matter_bridge_handoff_owner_test PRIVATE wotex_matter_bridge_handoff)
target_compile_options(wotex_matter_bridge_handoff_owner_test PRIVATE -Wall -Wextra -Wpedantic -Werror)
add_test(NAME wotex_matter_bridge_handoff_owner_test COMMAND wotex_matter_bridge_handoff_owner_test)

add_library(wotex_matter_bridge_output STATIC src/bridge_output.cpp)
target_link_libraries(wotex_matter_bridge_output PUBLIC wotex_matter_bridge_handoff)
target_compile_options(wotex_matter_bridge_output PRIVATE -Wall -Wextra -Wpedantic -Werror)
add_executable(wotex_matter_bridge_output_test ../test/native/bridge_output_test.cpp)
target_link_libraries(wotex_matter_bridge_output_test PRIVATE wotex_matter_bridge_output)
target_compile_options(wotex_matter_bridge_output_test PRIVATE -Wall -Wextra -Wpedantic -Werror)
add_test(NAME wotex_matter_bridge_output_test COMMAND wotex_matter_bridge_output_test)

add_library(wotex_matter_bridge_bootstrap_input STATIC src/bridge_private_file.cpp)
target_include_directories(wotex_matter_bridge_bootstrap_input PUBLIC include)
target_compile_features(wotex_matter_bridge_bootstrap_input PUBLIC cxx_std_17)
target_compile_options(wotex_matter_bridge_bootstrap_input PRIVATE -Wall -Wextra -Wpedantic -Werror)
if(WOTEX_MATTER_SANITIZERS)
  target_compile_options(wotex_matter_bridge_bootstrap_input PUBLIC -fno-omit-frame-pointer -fsanitize=address,undefined)
  target_link_options(wotex_matter_bridge_bootstrap_input PUBLIC -fsanitize=address,undefined)
endif()
foreach(test_name bridge_private_file bridge_commissioning_input)
  add_executable(wotex_matter_${test_name}_test ../test/native/${test_name}_test.cpp)
  target_link_libraries(wotex_matter_${test_name}_test PRIVATE wotex_matter_bridge_bootstrap_input)
  target_compile_options(wotex_matter_${test_name}_test PRIVATE -Wall -Wextra -Wpedantic -Werror)
  add_test(NAME wotex_matter_${test_name}_test COMMAND wotex_matter_${test_name}_test)
endforeach()
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  # Test-only GNU interposition mutates real files during reads. Production
  # sources expose no fault hook and retain ordinary POSIX calls.
  add_executable(wotex_matter_bridge_private_file_fault_test ../test/native/bridge_private_file_fault_test.cpp)
  target_link_libraries(wotex_matter_bridge_private_file_fault_test PRIVATE wotex_matter_bridge_bootstrap_input)
  target_link_options(wotex_matter_bridge_private_file_fault_test PRIVATE "-Wl,--wrap=read" "-Wl,--wrap=fstat")
  target_compile_options(wotex_matter_bridge_private_file_fault_test PRIVATE -Wall -Wextra -Wpedantic -Werror)
  add_test(NAME wotex_matter_bridge_private_file_fault_test COMMAND wotex_matter_bridge_private_file_fault_test)
endif()

if(WOTEX_MATTER_SDK_ROOT AND WOTEX_MATTER_JSON_INCLUDE)
  add_library(wotex_matter_bridge_observation STATIC src/bridge_observation.cpp)
  target_include_directories(wotex_matter_bridge_observation PUBLIC include)
  target_include_directories(wotex_matter_bridge_observation SYSTEM PRIVATE "${WOTEX_MATTER_JSON_INCLUDE}")
  target_compile_features(wotex_matter_bridge_observation PUBLIC cxx_std_17)
  target_compile_options(wotex_matter_bridge_observation PRIVATE -Wall -Wextra -Wpedantic -Werror)
  if(WOTEX_MATTER_SANITIZERS)
    target_compile_options(wotex_matter_bridge_observation PUBLIC -fno-omit-frame-pointer -fsanitize=address,undefined)
    target_link_options(wotex_matter_bridge_observation PUBLIC -fsanitize=address,undefined)
  endif()
  add_executable(wotex_matter_bridge_observation_test testing/bridge_observation_test.cpp)
  target_include_directories(wotex_matter_bridge_observation_test SYSTEM PRIVATE "${WOTEX_MATTER_JSON_INCLUDE}")
  target_link_libraries(wotex_matter_bridge_observation_test PRIVATE wotex_matter_bridge_observation)
  target_compile_options(wotex_matter_bridge_observation_test PRIVATE -Wall -Wextra -Wpedantic -Werror)
  add_test(NAME wotex_matter_bridge_observation_test COMMAND wotex_matter_bridge_observation_test)

  # Bridge input is a separate role and frame contract from the controller.
  add_library(wotex_matter_bridge_input STATIC src/bridge_input.cpp)
  target_include_directories(wotex_matter_bridge_input SYSTEM PRIVATE "${WOTEX_MATTER_JSON_INCLUDE}")
  target_link_libraries(wotex_matter_bridge_input PUBLIC wotex_matter_bridge_handoff)
  target_compile_options(wotex_matter_bridge_input PRIVATE -Wall -Wextra -Wpedantic -Werror)
  add_executable(wotex_matter_bridge_input_test ../test/native/bridge_input_test.cpp)
  target_include_directories(wotex_matter_bridge_input_test SYSTEM PRIVATE "${WOTEX_MATTER_JSON_INCLUDE}")
  target_link_libraries(wotex_matter_bridge_input_test PRIVATE wotex_matter_bridge_input)
  target_compile_options(wotex_matter_bridge_input_test PRIVATE -Wall -Wextra -Wpedantic -Werror)
  add_test(NAME wotex_matter_bridge_input_test COMMAND wotex_matter_bridge_input_test)

  set(WOTEX_MATTER_SDK_INCLUDES
    "${WOTEX_MATTER_SDK_ROOT}/src"
    "${WOTEX_MATTER_SDK_ROOT}/third_party/nlassert/repo/include"
    "${WOTEX_MATTER_SDK_ROOT}/third_party/nlio/repo/include"
  )

  add_library(wotex_matter_storage STATIC src/storage.cpp src/bridge_storage.cpp)
  target_include_directories(wotex_matter_storage PUBLIC include)
  target_include_directories(
    wotex_matter_storage SYSTEM
    PUBLIC ${WOTEX_MATTER_SDK_INCLUDES}
    PRIVATE "${WOTEX_MATTER_JSON_INCLUDE}"
  )
  target_compile_features(wotex_matter_storage PUBLIC cxx_std_17)
  target_compile_definitions(wotex_matter_storage PUBLIC CHIP_SYSTEM_CONFIG_USE_SOCKETS=1)
  target_compile_options(wotex_matter_storage PRIVATE -Wall -Wextra -Wpedantic -Werror)

  add_library(wotex_matter_protocol STATIC src/protocol.cpp)
  target_include_directories(wotex_matter_protocol PUBLIC include)
  target_include_directories(
    wotex_matter_protocol SYSTEM
    PRIVATE "${WOTEX_MATTER_JSON_INCLUDE}"
  )
  target_compile_features(wotex_matter_protocol PUBLIC cxx_std_17)
  target_link_libraries(wotex_matter_protocol PUBLIC wotex_matter_value)
  target_compile_options(
    wotex_matter_protocol PRIVATE -Wall -Wextra -Wpedantic -Werror
  )

  add_executable(wotex_matter_contract_driver ../test/native/contract_driver.cpp)
  target_link_libraries(wotex_matter_contract_driver PRIVATE wotex_matter_protocol)
  target_include_directories(wotex_matter_contract_driver SYSTEM PRIVATE "${WOTEX_MATTER_JSON_INCLUDE}")
  target_compile_options(
    wotex_matter_contract_driver PRIVATE -Wall -Wextra -Wpedantic -Werror
  )

  add_executable(wotex_matter_controller_test ../test/native/controller_test.cpp)
  target_link_libraries(wotex_matter_controller_test PRIVATE wotex_matter_protocol)
  target_compile_options(
    wotex_matter_controller_test PRIVATE -Wall -Wextra -Wpedantic -Werror
  )
  add_test(NAME wotex_matter_controller_test COMMAND wotex_matter_controller_test)

  add_executable(wotex_matter_interaction_test ../test/native/interaction_test.cpp)
  target_link_libraries(wotex_matter_interaction_test PRIVATE wotex_matter_protocol)
  target_compile_options(
    wotex_matter_interaction_test PRIVATE -Wall -Wextra -Wpedantic -Werror
  )
  add_test(NAME wotex_matter_interaction_test COMMAND wotex_matter_interaction_test)

  # Counter cutpoints exist only in this unit-test library. Neither the native
  # host nor the shared contract driver admits counter seeding.
  add_library(wotex_matter_protocol_test_library STATIC
    src/value.cpp src/interaction.cpp src/subscription.cpp src/commissioning.cpp
    src/protocol.cpp)
  target_include_directories(wotex_matter_protocol_test_library PUBLIC include)
  target_include_directories(wotex_matter_protocol_test_library SYSTEM
    PRIVATE "${WOTEX_MATTER_JSON_INCLUDE}")
  target_compile_features(wotex_matter_protocol_test_library PUBLIC cxx_std_17)
  target_compile_definitions(wotex_matter_protocol_test_library
    PUBLIC WOTEX_MATTER_PROTOCOL_TESTING=1)
  target_compile_options(wotex_matter_protocol_test_library
    PRIVATE -Wall -Wextra -Wpedantic -Werror)

  add_executable(wotex_matter_subscription_test ../test/native/subscription_test.cpp)
  target_link_libraries(wotex_matter_subscription_test PRIVATE wotex_matter_protocol_test_library)
  target_compile_options(
    wotex_matter_subscription_test PRIVATE -Wall -Wextra -Wpedantic -Werror
  )
  add_test(NAME wotex_matter_subscription_test COMMAND wotex_matter_subscription_test)

  add_executable(wotex_matter_commissioning_test ../test/native/commissioning_test.cpp)
  target_link_libraries(wotex_matter_commissioning_test PRIVATE wotex_matter_protocol)
  target_compile_options(
    wotex_matter_commissioning_test PRIVATE -Wall -Wextra -Wpedantic -Werror
  )
  add_test(NAME wotex_matter_commissioning_test COMMAND wotex_matter_commissioning_test)

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

  add_library(wotex_matter_storage_test_library STATIC src/storage.cpp src/bridge_storage.cpp)
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

  add_executable(wotex_matter_bridge_storage_test ../test/native/bridge_storage_test.cpp)
  target_include_directories(wotex_matter_bridge_storage_test SYSTEM PRIVATE "${WOTEX_MATTER_JSON_INCLUDE}")
  target_link_libraries(wotex_matter_bridge_storage_test PRIVATE wotex_matter_storage_test_library)
  target_compile_options(wotex_matter_bridge_storage_test PRIVATE -Wall -Wextra -Wpedantic -Werror)
  add_test(NAME wotex_matter_bridge_storage_test COMMAND wotex_matter_bridge_storage_test)

  if(WOTEX_MATTER_SANITIZERS)
    foreach(target wotex_matter_storage wotex_matter_storage_test_library wotex_matter_protocol wotex_matter_protocol_test_library)
      target_compile_options(${target} PUBLIC -fno-omit-frame-pointer -fsanitize=address,undefined)
      target_link_options(${target} PUBLIC -fsanitize=address,undefined)
    endforeach()
  endif()
endif()
