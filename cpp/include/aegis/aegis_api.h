#pragma once
/*
 * AEGIS C API — exported symbols for Dart FFI.
 *
 * All functions use a flat C ABI so Dart can call them via dart:ffi without
 * a C++ name-mangling wrapper. Strings are null-terminated UTF-8. Buffers
 * that the caller must free are released with aegis_free_string().
 *
 * Memory model:
 *   - aegis_create_*  returns an opaque handle that must be freed with the
 *     corresponding aegis_destroy_*.
 *   - aegis_free_string frees any char* returned by the library.
 */

#ifdef _WIN32
  #ifdef AEGIS_EXPORTS
    #define AEGIS_API __declspec(dllexport)
  #else
    #define AEGIS_API __declspec(dllimport)
  #endif
#else
  #define AEGIS_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* ── Lifecycle ──────────────────────────────────────────────────── */

/** Create a new identification pipeline.  Returns opaque handle or NULL. */
AEGIS_API void* aegis_create_pipeline(void);

/** Destroy a pipeline created with aegis_create_pipeline. */
AEGIS_API void  aegis_destroy_pipeline(void* pipeline);

/* ── Data loading ───────────────────────────────────────────────── */

/**
 * Load a row-major data matrix into the pipeline.
 *   data    : double[rows * cols], row-major
 *   rows    : sample count
 *   cols    : variable count (inputs + output)
 *   returns : 0 = OK, non-zero = error
 */
AEGIS_API int aegis_load_data(
    void*        pipeline,
    const double* data,
    int           rows,
    int           cols
);

/* ── Configuration ──────────────────────────────────────────────── */

/**
 * Configure the pipeline from a JSON string.
 * Accepted keys (all optional, use defaults otherwise):
 *   normalizerType      : "minmax" | "robust" | "zscore"  (default "minmax")
 *   trainRatio          : double  [0.5,0.9]   (default 0.7)
 *   validationRatio     : double  [0.05,0.3]  (default 0.15)
 *   outputCol           : int                 (default last column)
 *   numIslands          : int    [1,16]        (default 3)
 *   populationSize      : int    [20,500]      (default 50)
 *   maxGenerations      : int    [100,100000]  (default 5000)
 *   stagnationLimit     : int    [50,5000]     (default 500)
 *   mutationFactor      : double [0.0,2.0]     (default 0.5)
 *   crossoverRate       : double [0.0,1.0]     (default 0.9)
 *   elitismCount        : int    [0,20]        (default 2)
 *   migrationInterval   : int    [5,200]       (default 20)
 *   migrationRate       : double [0.0,0.5]     (default 0.1)
 *   maxRegressors       : int    [2,30]        (default 8)
 *   maxTermsPerReg      : int    [1,5]         (default 3)
 *   pmin                : double [0.1,1.0]     (default 0.5)
 *   pmax                : double [1.0,10.0]    (default 5.0)
 *   maxDelay            : int    [1,200]       (default 20)
 *   complexityPenalty   : double [0.0,10.0]    (default 1.0)
 *   denominatorPenalty  : double [0.0,10.0]    (default 0.1)
 *   exponentPenalty     : double [0.0,1.0]     (default 0.01)
 *   stabilityPenalty    : double [0.0,10.0]    (default 1.0)
 *   numThreads          : int    [1,64]        (default hardware)
 *   webSocketPort       : int    [1024,65535]  (default 8765)
 */
AEGIS_API int aegis_configure(void* pipeline, const char* json_config);

/* ── Identification control ─────────────────────────────────────── */

/** Start asynchronous identification (native) or sync initialization (WASM). Returns immediately. */
AEGIS_API int aegis_start(void* pipeline);

/**
 * Run up to num_generations DE generations synchronously (WASM path).
 * Call repeatedly from a JS timer in place of the async thread.
 * Returns generations run; 0 when done or engine not running.
 */
AEGIS_API int aegis_step(void* pipeline, int num_generations);

/** Pause a running identification. */
AEGIS_API int aegis_pause(void* pipeline);

/** Resume a paused identification. */
AEGIS_API int aegis_resume(void* pipeline);

/** Stop identification (graceful). */
AEGIS_API int aegis_stop(void* pipeline);

/* ── Status queries ─────────────────────────────────────────────── */

/**
 * Returns a heap-allocated JSON string with the current engine status.
 * Caller must free with aegis_free_string().
 * Fields: state, generation, bestFitness, rmseTrain, rmseVal, rmseTest,
 *         bic, aic, populationDiversity, stagnation, elapsed_ms
 */
AEGIS_API char* aegis_get_status(void* pipeline);

/**
 * Returns a heap-allocated JSON string with the best model found so far.
 * Caller must free with aegis_free_string().
 * Fields: equation, coefficients[], exponents[], regressors[],
 *         rmseTrain, rmseVal, rmseTest, r2Train, r2Val,
 *         aic, bic, fpe, mdl, sse,
 *         residualAutocorr[], stability, overfitting, underfitting
 */
AEGIS_API char* aegis_get_best_model(void* pipeline);

/**
 * Returns a heap-allocated JSON with the latest generation snapshot.
 * Same structure as WebSocket broadcast payload.
 * Caller must free with aegis_free_string().
 */
AEGIS_API char* aegis_get_snapshot(void* pipeline);

/** Free any string returned by the library. */
AEGIS_API void aegis_free_string(char* ptr);

/* ── Agent tuning (synchronous) ─────────────────────────────────── */

/**
 * Apply a parameter adjustment from the Dart AI agent.
 *   param_name : one of the configuration keys listed in aegis_configure
 *   new_value  : proposed value (validated against limits)
 *   reason     : human-readable reason string (may be NULL)
 *   returns    : 0 = accepted, 1 = rejected (out of bounds or invalid), -1 = unknown param
 */
AEGIS_API int aegis_apply_tuning(
    void*       pipeline,
    const char* param_name,
    double      new_value,
    const char* reason
);

/**
 * Returns the accepted/rejected tuning log as a JSON array.
 * Caller must free with aegis_free_string().
 */
AEGIS_API char* aegis_get_tuning_log(void* pipeline);

/* ── WebSocket agent server ─────────────────────────────────────── */

/** Create a standalone agent WebSocket server (not tied to a pipeline). */
AEGIS_API void* aegis_create_agent_server(int port);

/** Destroy and stop an agent server. */
AEGIS_API void  aegis_destroy_agent_server(void* server);

/** Start listening. Returns 0 on success. */
AEGIS_API int   aegis_agent_server_start(void* server);

/** Stop listening. */
AEGIS_API void  aegis_agent_server_stop(void* server);

/** Broadcast a JSON payload to all connected clients. Returns client count. */
AEGIS_API int   aegis_agent_broadcast(void* server, const char* json);

/** Number of currently connected clients. */
AEGIS_API int   aegis_agent_client_count(void* server);

/* ── Version ────────────────────────────────────────────────────── */

/** Returns a static version string. Do NOT free. */
AEGIS_API const char* aegis_version(void);

#ifdef __cplusplus
} /* extern "C" */
#endif
