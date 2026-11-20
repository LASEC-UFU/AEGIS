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
 * Configure the pipeline from a JSON object (must be called after
 * aegis_load_data). Unknown keys are ignored and reported through
 * aegis_get_last_error(). The complete list of keys, defaults and valid
 * ranges is documented in docs/CONFIGURATION.md; aegis_get_config() returns
 * the effective configuration, including the effective random seed.
 * Returns 0 on success, -1 on error (message in aegis_get_last_error()).
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
 *   param_name : one of the parameters of aegis_get_action_schema()
 *   new_value  : proposed value (validated against range, max step, cooldown)
 *   reason     : human-readable reason string (may be NULL)
 *   returns    : 0 = accepted, 1 = rejected, -1 = unknown param
 * Legacy wrapper around aegis_apply_action (source = "legacy").
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

/* ── Agent action interface (typed, validated, logged) ─────────────── */

/**
 * Submit one action as JSON: {"param":"mutationFactor","value":0.6,
 * "reason":"...","source":"llm"}. Also accepts
 * {"actions":[{"param":..,"value":..},...]} and the legacy
 * {"proposed_changes":{"param":value},"reason":"..."}.
 * Returns {"results":[ActionRecord,...]} (caller frees). Accepted actions are
 * applied at the next generation boundary; see docs/AGENT_INTERFACE.md.
 */
AEGIS_API char* aegis_apply_action(void* pipeline, const char* action_json);

/** Published schema of agent-tunable parameters (ranges, max step, cooldown). */
AEGIS_API char* aegis_get_action_schema(void* pipeline);

/** Enable (1) or disable (0) agent actions without touching the run. */
AEGIS_API int   aegis_set_agent_enabled(void* pipeline, int enabled);

/* ── Records / reproducibility ─────────────────────────────────────── */

/** Effective configuration (after validation, includes the effective seed). */
AEGIS_API char* aegis_get_config(void* pipeline);

/** Compact per-generation history (convergence curves). */
AEGIS_API char* aegis_get_history(void* pipeline);

/**
 * Final report (available after completion or stop): config, seed, data
 * hash, splits, normalization, model, train/validation/test metrics (one-step
 * and free-run, normalized and original units), actions and outcomes.
 */
AEGIS_API char* aegis_get_final_report(void* pipeline);

/** Last configuration/data error or warning (empty string if none). */
AEGIS_API char* aegis_get_last_error(void* pipeline);

/**
 * Evaluate an external model (AEGIS model JSON) on the pipeline's data and
 * splits. refit != 0 re-estimates coefficients on the training split.
 * Uses the test split: intended for post-hoc baseline evaluation only.
 */
AEGIS_API char* aegis_evaluate_model(void* pipeline, const char* model_json, int refit);

/** Build information JSON (static; do NOT free). */
AEGIS_API const char* aegis_build_info(void);

/** Inject a model (best_model JSON) as a migrant into island 0. */
AEGIS_API int   aegis_inject_individual(void* pipeline, const char* json);

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
