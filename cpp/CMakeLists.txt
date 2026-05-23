cmake_minimum_required(VERSION 3.17)
project(aegis_core VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

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
  src/de_optimizer.cpp
  src/identification_pipeline.cpp
  src/agent_controller.cpp
  src/aegis_api.cpp
)

# ── Shared library ───────────────────────────────────────────────
add_library(aegis_core SHARED ${AEGIS_SOURCES})

target_include_directories(aegis_core
  PUBLIC  ${CMAKE_CURRENT_SOURCE_DIR}/include
  PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include/aegis
)

# Export symbols on Windows
if(WIN32)
  target_compile_definitions(aegis_core PRIVATE AEGIS_EXPORTS)
  target_link_libraries(aegis_core PRIVATE ws2_32)
  set_target_properties(aegis_core PROPERTIES
    WINDOWS_EXPORT_ALL_SYMBOLS OFF
  )
endif()

# ── Compiler options ─────────────────────────────────────────────
if(MSVC)
  target_compile_options(aegis_core PRIVATE /O2 /W3 /MP)
  target_compile_definitions(aegis_core PRIVATE _CRT_SECURE_NO_WARNINGS)
else()
  target_compile_options(aegis_core PRIVATE -O3 -Wall -Wextra -march=native)
endif()

# ── Optional: OpenMP ─────────────────────────────────────────────
find_package(OpenMP OPTIONAL_COMPONENTS CXX)
if(OpenMP_CXX_FOUND)
  target_link_libraries(aegis_core PRIVATE OpenMP::OpenMP_CXX)
  target_compile_definitions(aegis_core PRIVATE AEGIS_OPENMP)
endif()

# ── Install ──────────────────────────────────────────────────────
install(TARGETS aegis_core DESTINATION bin)
install(FILES include/aegis/aegis_api.h DESTINATION include)

# ── WASM target (Emscripten only) ────────────────────────────────
if(DEFINED EMSCRIPTEN)
  add_executable(aegis_wasm ${AEGIS_SOURCES})

  target_include_directories(aegis_wasm
    PUBLIC  ${CMAKE_CURRENT_SOURCE_DIR}/include
    PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include/aegis
  )

  # Functions exported to JavaScript
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
    "_aegis_free_string"
    "_aegis_apply_tuning"
    "_aegis_get_tuning_log"
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
    -sENVIRONMENT=web
    --no-entry
  )

  set_target_properties(aegis_wasm PROPERTIES
    OUTPUT_NAME "aegis_wasm"
    SUFFIX ".js"
  )
endif()
