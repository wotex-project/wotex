cmake_minimum_required(VERSION 3.25)

project(wotex_matter_native LANGUAGES CXX)

option(WOTEX_MATTER_SANITIZERS "Enable address and undefined-behavior sanitizers" OFF)

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
