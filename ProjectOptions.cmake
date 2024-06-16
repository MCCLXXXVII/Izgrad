include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(Izgrad_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(Izgrad_setup_options)
  option(Izgrad_ENABLE_HARDENING "Enable hardening" ON)
  option(Izgrad_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    Izgrad_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    Izgrad_ENABLE_HARDENING
    OFF)

  Izgrad_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR Izgrad_PACKAGING_MAINTAINER_MODE)
    option(Izgrad_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(Izgrad_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(Izgrad_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(Izgrad_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(Izgrad_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(Izgrad_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(Izgrad_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(Izgrad_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(Izgrad_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(Izgrad_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(Izgrad_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(Izgrad_ENABLE_PCH "Enable precompiled headers" OFF)
    option(Izgrad_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(Izgrad_ENABLE_IPO "Enable IPO/LTO" ON)
    option(Izgrad_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(Izgrad_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(Izgrad_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(Izgrad_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(Izgrad_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(Izgrad_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(Izgrad_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(Izgrad_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(Izgrad_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(Izgrad_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(Izgrad_ENABLE_PCH "Enable precompiled headers" OFF)
    option(Izgrad_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      Izgrad_ENABLE_IPO
      Izgrad_WARNINGS_AS_ERRORS
      Izgrad_ENABLE_USER_LINKER
      Izgrad_ENABLE_SANITIZER_ADDRESS
      Izgrad_ENABLE_SANITIZER_LEAK
      Izgrad_ENABLE_SANITIZER_UNDEFINED
      Izgrad_ENABLE_SANITIZER_THREAD
      Izgrad_ENABLE_SANITIZER_MEMORY
      Izgrad_ENABLE_UNITY_BUILD
      Izgrad_ENABLE_CLANG_TIDY
      Izgrad_ENABLE_CPPCHECK
      Izgrad_ENABLE_COVERAGE
      Izgrad_ENABLE_PCH
      Izgrad_ENABLE_CACHE)
  endif()

  Izgrad_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (Izgrad_ENABLE_SANITIZER_ADDRESS OR Izgrad_ENABLE_SANITIZER_THREAD OR Izgrad_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(Izgrad_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(Izgrad_global_options)
  if(Izgrad_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    Izgrad_enable_ipo()
  endif()

  Izgrad_supports_sanitizers()

  if(Izgrad_ENABLE_HARDENING AND Izgrad_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR Izgrad_ENABLE_SANITIZER_UNDEFINED
       OR Izgrad_ENABLE_SANITIZER_ADDRESS
       OR Izgrad_ENABLE_SANITIZER_THREAD
       OR Izgrad_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${Izgrad_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${Izgrad_ENABLE_SANITIZER_UNDEFINED}")
    Izgrad_enable_hardening(Izgrad_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(Izgrad_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(Izgrad_warnings INTERFACE)
  add_library(Izgrad_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  Izgrad_set_project_warnings(
    Izgrad_warnings
    ${Izgrad_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(Izgrad_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    Izgrad_configure_linker(Izgrad_options)
  endif()

  include(cmake/Sanitizers.cmake)
  Izgrad_enable_sanitizers(
    Izgrad_options
    ${Izgrad_ENABLE_SANITIZER_ADDRESS}
    ${Izgrad_ENABLE_SANITIZER_LEAK}
    ${Izgrad_ENABLE_SANITIZER_UNDEFINED}
    ${Izgrad_ENABLE_SANITIZER_THREAD}
    ${Izgrad_ENABLE_SANITIZER_MEMORY})

  set_target_properties(Izgrad_options PROPERTIES UNITY_BUILD ${Izgrad_ENABLE_UNITY_BUILD})

  if(Izgrad_ENABLE_PCH)
    target_precompile_headers(
      Izgrad_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(Izgrad_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    Izgrad_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(Izgrad_ENABLE_CLANG_TIDY)
    Izgrad_enable_clang_tidy(Izgrad_options ${Izgrad_WARNINGS_AS_ERRORS})
  endif()

  if(Izgrad_ENABLE_CPPCHECK)
    Izgrad_enable_cppcheck(${Izgrad_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(Izgrad_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    Izgrad_enable_coverage(Izgrad_options)
  endif()

  if(Izgrad_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(Izgrad_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(Izgrad_ENABLE_HARDENING AND NOT Izgrad_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR Izgrad_ENABLE_SANITIZER_UNDEFINED
       OR Izgrad_ENABLE_SANITIZER_ADDRESS
       OR Izgrad_ENABLE_SANITIZER_THREAD
       OR Izgrad_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    Izgrad_enable_hardening(Izgrad_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
