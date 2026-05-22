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
