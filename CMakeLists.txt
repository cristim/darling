cmake_minimum_required(VERSION 3.20)
project(DarlingSwiftUI NONE)
option(DARLING_BUILD_SWIFTUI "Build the pinned SwiftUI source closure" ON)
set(DARLING_SWIFTUI_INPUTS "" CACHE FILEPATH "Pinned source closure manifest")
set(DARLING_SWIFTUI_RUNTIME_ROOT "" CACHE PATH "Read-only private guest runtime root")
set(DARLING_SWIFTUI_WORKSPACE "${CMAKE_BINARY_DIR}/swiftui" CACHE PATH "Separate private source build/install workspace")
if(DARLING_BUILD_SWIFTUI)
  if(NOT EXISTS "${DARLING_SWIFTUI_INPUTS}" OR NOT IS_DIRECTORY "${DARLING_SWIFTUI_RUNTIME_ROOT}")
    message(FATAL_ERROR "SwiftUI default build requires a pinned inputs manifest and private runtime root")
  endif()
  find_package(Python3 REQUIRED COMPONENTS Interpreter)
  add_custom_target(SwiftUI ALL
    COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/build.py"
      --inputs "${DARLING_SWIFTUI_INPUTS}"
      --runtime-root "${DARLING_SWIFTUI_RUNTIME_ROOT}"
      --workspace "${DARLING_SWIFTUI_WORKSPACE}" --jobs 2
    VERBATIM USES_TERMINAL)
endif()
