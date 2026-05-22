// Raw Dart FFI type declarations for the AEGIS C++ core library.
// These map 1-to-1 to the functions in aegis_api.h.
// Do not use these directly — use AegisLibrary instead.

import 'dart:ffi';
import 'package:ffi/ffi.dart';

// ─── Native function type declarations ────────────────────────────────────

// Pipeline lifecycle
typedef AegisCreatePipelineNative = Pointer<Void> Function();
typedef AegisDestroyPipelineNative = Void Function(Pointer<Void> pipeline);

// Data loading
typedef AegisLoadDataNative = Int32 Function(
  Pointer<Void> pipeline,
  Pointer<Double> data,
  Int32 rows,
  Int32 cols,
);

// Configuration
typedef AegisConfigureNative = Int32 Function(
  Pointer<Void> pipeline,
  Pointer<Utf8> jsonConfig,
);

// Control
typedef AegisStartNative  = Int32 Function(Pointer<Void> pipeline);
typedef AegisPauseNative  = Int32 Function(Pointer<Void> pipeline);
typedef AegisResumeNative = Int32 Function(Pointer<Void> pipeline);
typedef AegisStopNative   = Int32 Function(Pointer<Void> pipeline);

// Status / results
typedef AegisGetStatusNative    = Pointer<Utf8> Function(Pointer<Void> pipeline);
typedef AegisGetBestModelNative = Pointer<Utf8> Function(Pointer<Void> pipeline);
typedef AegisGetSnapshotNative  = Pointer<Utf8> Function(Pointer<Void> pipeline);
typedef AegisFreeStringNative   = Void Function(Pointer<Utf8> ptr);

// Agent tuning
typedef AegisApplyTuningNative = Int32 Function(
  Pointer<Void> pipeline,
  Pointer<Utf8> paramName,
  Double newValue,
  Pointer<Utf8> reason,
);
typedef AegisGetTuningLogNative = Pointer<Utf8> Function(Pointer<Void> pipeline);

// Standalone agent server
typedef AegisCreateAgentServerNative  = Pointer<Void> Function(Int32 port);
typedef AegisDestroyAgentServerNative = Void Function(Pointer<Void> server);
typedef AegisAgentServerStartNative   = Int32 Function(Pointer<Void> server);
typedef AegisAgentServerStopNative    = Void Function(Pointer<Void> server);
typedef AegisAgentBroadcastNative     = Int32 Function(
  Pointer<Void> server,
  Pointer<Utf8> json,
);
typedef AegisAgentClientCountNative = Int32 Function(Pointer<Void> server);
typedef AegisVersionNative          = Pointer<Utf8> Function();

// ─── Dart typedef aliases ─────────────────────────────────────────────────

typedef AegisCreatePipeline    = Pointer<Void> Function();
typedef AegisDestroyPipeline   = void Function(Pointer<Void>);
typedef AegisLoadData          = int Function(Pointer<Void>, Pointer<Double>, int, int);
typedef AegisConfigure         = int Function(Pointer<Void>, Pointer<Utf8>);
typedef AegisStart             = int Function(Pointer<Void>);
typedef AegisPause             = int Function(Pointer<Void>);
typedef AegisResume            = int Function(Pointer<Void>);
typedef AegisStop              = int Function(Pointer<Void>);
typedef AegisGetStatus         = Pointer<Utf8> Function(Pointer<Void>);
typedef AegisGetBestModel      = Pointer<Utf8> Function(Pointer<Void>);
typedef AegisGetSnapshot       = Pointer<Utf8> Function(Pointer<Void>);
typedef AegisFreeString        = void Function(Pointer<Utf8>);
typedef AegisApplyTuning       = int Function(
  Pointer<Void>, Pointer<Utf8>, double, Pointer<Utf8>);
typedef AegisGetTuningLog      = Pointer<Utf8> Function(Pointer<Void>);
typedef AegisCreateAgentServer = Pointer<Void> Function(int);
typedef AegisDestroyAgentServer= void Function(Pointer<Void>);
typedef AegisAgentServerStart  = int Function(Pointer<Void>);
typedef AegisAgentServerStop   = void Function(Pointer<Void>);
typedef AegisAgentBroadcast    = int Function(Pointer<Void>, Pointer<Utf8>);
typedef AegisAgentClientCount  = int Function(Pointer<Void>);
typedef AegisVersion           = Pointer<Utf8> Function();
