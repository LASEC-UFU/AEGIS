cmake_minimum_required(VERSION 3.17)
project(aegis_core VERSION 1.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(AEGIS_NATIVE_ARCH "Optimise for the build machine (-march=native); breaks bitwise reproducibility across CPUs" OFF)
option(AEGIS_STATIC_RUNTIME "MinGW: link libstdc++/libgcc/winpthread statically into the DLL and tools" ON)

set(AEGIS_VERSION_STRING "1.1.0-audit")

# ── Sources ──────────────────────────────────────────────────────
set(AEGIS_SOURCES
  src/normalizer.cpp
  src/regressor_library.cpp
  src/rational_model.cpp
  src/metrics.cpp
  src/residual_analyzer.cpp
  src/stability_analyzer.cpp
  src/collinearity_analyzer.cpp
  src/excitation_analyzer.cpp
  src/population_diversity_monitor.cpp
  src/overfitting_detector.cpp
  src/underfitting_detector.cpp
  src/automatic_pruner.cpp
  src/individual_evaluator.cpp
  src/local_refiner.cpp
  src/model_io.cpp
  src/de_optimizer.cpp
  src/identification_pipeline.cpp
  src/agent_controller.cpp
  src/aegis_api.cpp
)

# ── Common compile options ───────────────────────────────────────
function(aegis_set_options tgt)
  if(MSVC)
    target_compile_options(${tgt} PRIVATE /O2 /W3 /fp:precise)
    target_compile_definitions(${tgt} PRIVATE _CRT_SECURE_NO_WARNINGS NOMINMAX)
  else()
    target_compile_options(${tgt} PRIVATE -O2 -Wall -Wextra -ffp-contract=off)
    if(AEGIS_NATIVE_ARCH)
      target_compile_options(${tgt} PRIVATE -march=native)
    endif()
  endif()
  string(TOUPPER "${CMAKE_BUILD_TYPE}" _bt)
  target_compile_definitions(${tgt} PRIVATE
    AEGIS_VERSION_STRING="${AEGIS_VERSION_STRING}"
    AEGIS_BUILD_FLAGS="${CMAKE_BUILD_TYPE} ${CMAKE_CXX_FLAGS} ${CMAKE_CXX_FLAGS_${_bt}} native=${AEGIS_NATIVE_ARCH}")
endfunction()

function(aegis_static_runtime tgt)
  if(MINGW AND AEGIS_STATIC_RUNTIME)
    target_link_options(${tgt} PRIVATE -static -static-libgcc -static-libstdc++)
  endif()
endfunction()

# ── Object library shared by the DLL and the C++ tests ───────────
add_library(aegis_obj OBJECT ${AEGIS_SOURCES})
target_include_directories(aegis_obj PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
set_target_properties(aegis_obj PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_compile_definitions(aegis_obj PRIVATE AEGIS_EXPORTS)
aegis_set_options(aegis_obj)

# ── Shared library ───────────────────────────────────────────────
add_library(aegis_core SHARED $<TARGET_OBJECTS:aegis_obj>)
target_include_directories(aegis_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
if(WIN32)
  target_link_libraries(aegis_core PRIVATE ws2_32)
  set_target_properties(aegis_core PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS OFF PREFIX "")
endif()
find_package(Threads)
if(Threads_FOUND)
  target_link_libraries(aegis_core PRIVATE Threads::Threads)
endif()
aegis_static_runtime(aegis_core)

# ── Standalone build: tools and tests ────────────────────────────
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
  install(TARGETS aegis_core DESTINATION bin)
  install(FILES include/aegis/aegis_api.h DESTINATION include)

  # Static library for tests that use the C++ classes directly.
  add_library(aegis_static STATIC $<TARGET_OBJECTS:aegis_obj>)
  target_include_directories(aegis_static PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
  if(WIN32)
    target_link_libraries(aegis_static PUBLIC ws2_32)
  endif()
  if(Threads_FOUND)
    target_link_libraries(aegis_static PUBLIC Threads::Threads)
  endif()

  foreach(tool test_harness diag_harness)
    add_executable(${tool} ${tool}.cpp)
    target_link_libraries(${tool} PRIVATE aegis_core)
    aegis_static_runtime(${tool})
  endforeach()

  # Batch CLI runner (reproducible multi-seed experiments)
  add_executable(aegis_batch src/aegis_batch.cpp)
  target_link_libraries(aegis_batch PRIVATE aegis_core)
  aegis_set_options(aegis_batch)
  aegis_static_runtime(aegis_batch)
  install(TARGETS aegis_batch DESTINATION bin)

  # FROLS / ERR-OLS polynomial NARX baseline (same data handling and metrics)
  add_executable(aegis_frols tools/frols_baseline.cpp)
  target_link_libraries(aegis_frols PRIVATE aegis_core)
  aegis_set_options(aegis_frols)
  aegis_static_runtime(aegis_frols)

  # Re-evaluation of saved models (AEGIS, FROLS, legacy HEAD) with the same metrics
  add_executable(aegis_evaluate_models tools/evaluate_models.cpp)
  target_link_libraries(aegis_evaluate_models PRIVATE aegis_core)
  aegis_set_options(aegis_evaluate_models)
  aegis_static_runtime(aegis_evaluate_models)

  enable_testing()
  add_executable(core_tests core_tests.cpp)
  target_link_libraries(core_tests PRIVATE aegis_static)
  target_compile_definitions(core_tests PRIVATE AEGIS_EXPORTS)
  aegis_set_options(core_tests)
  aegis_static_runtime(core_tests)
  add_test(NAME aegis_core_tests COMMAND core_tests)

  add_executable(api_tests api_tests.cpp)
  target_link_libraries(api_tests PRIVATE aegis_core)
  if(WIN32)
    target_link_libraries(api_tests PRIVATE ws2_32)
  endif()
  aegis_set_options(api_tests)
  aegis_static_runtime(api_tests)
  add_test(NAME aegis_api_tests COMMAND api_tests)

  # Phase 0 (experiments/phase0/PHASE0_PREREG.md): fixed-structure capacity and
  # simulation-error fitting. Built in a separate build directory; does not
  # change any existing target.
  foreach(p0 aegis_phase0 phase0_tests)
    if(p0 STREQUAL "aegis_phase0")
      add_executable(${p0} tools/phase0_fixed.cpp)
    else()
      add_executable(${p0} tools/phase0_tests.cpp)
    endif()
    target_link_libraries(${p0} PRIVATE aegis_static)
    target_compile_definitions(${p0} PRIVATE AEGIS_EXPORTS)
    aegis_set_options(${p0})
    aegis_static_runtime(${p0})
  endforeach()
  add_test(NAME phase0_tests COMMAND phase0_tests)
endif()

# ── WASM target (Emscripten only) ────────────────────────────────
if(DEFINED EMSCRIPTEN)
  add_executable(aegis_wasm ${AEGIS_SOURCES})
  target_include_directories(aegis_wasm
    PUBLIC  ${CMAKE_CURRENT_SOURCE_DIR}/include
    PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include/aegis
  )
  target_compile_definitions(aegis_wasm PRIVATE AEGIS_VERSION_STRING="${AEGIS_VERSION_STRING}")

  set(AEGIS_EXPORTED_FUNCTIONS
    "_aegis_create_pipeline"
    "_aegis_destroy_pipeline"
    "_aegis_load_data"
    "_aegis_configure"
    "_aegis_start"
    "_aegis_pause"
    "_aegis_resume"
    "_aegis_stop"
    "_aegis_step"
    "_aegis_get_status"
    "_aegis_get_snapshot"
    "_aegis_get_best_model"
    "_aegis_inject_individual"
    "_aegis_free_string"
    "_aegis_apply_tuning"
    "_aegis_apply_action"
    "_aegis_get_action_schema"
    "_aegis_set_agent_enabled"
    "_aegis_get_tuning_log"
    "_aegis_get_config"
    "_aegis_get_history"
    "_aegis_get_final_report"
    "_aegis_get_last_error"
    "_aegis_evaluate_model"
    "_aegis_build_info"
    "_aegis_version"
    "_malloc"
    "_free"
  )
  string(JOIN "," AEGIS_EXPORTS_STR ${AEGIS_EXPORTED_FUNCTIONS})

  target_compile_options(aegis_wasm PRIVATE -O2)
  target_link_options(aegis_wasm PRIVATE
    -sMODULARIZE=1
    -sEXPORT_NAME=createAegisModule
    -sALLOW_MEMORY_GROWTH=1
    -sINITIAL_MEMORY=67108864       # 64 MB
    -sEXPORTED_FUNCTIONS=[${AEGIS_EXPORTS_STR}]
    -sEXPORTED_RUNTIME_METHODS=[\"UTF8ToString\",\"stringToUTF8\",\"lengthBytesUTF8\",\"HEAPF64\",\"HEAP8\"]
    -sENVIRONMENT=web,worker
    --no-entry
  )
  set_target_properties(aegis_wasm PROPERTIES OUTPUT_NAME "aegis_wasm" SUFFIX ".js")
endif()
