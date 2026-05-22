// Loads the aegis_core native library and resolves all FFI symbols.
// Falls back gracefully when the native library is unavailable (e.g., on web).

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

import 'aegis_ffi_bindings.dart';

class AegisLibrary {
  static AegisLibrary? _instance;

  final DynamicLibrary _lib;

  // ── Resolved function pointers ─────────────────────────────────────────
  late final AegisCreatePipeline    createPipeline;
  late final AegisDestroyPipeline   destroyPipeline;
  late final AegisLoadData          loadData;
  late final AegisConfigure         configure;
  late final AegisStart             start;
  late final AegisPause             pause;
  late final AegisResume            resume;
  late final AegisStop              stop;
  late final AegisGetStatus         getStatus;
  late final AegisGetBestModel      getBestModel;
  late final AegisGetSnapshot       getSnapshot;
  late final AegisFreeString        freeString;
  late final AegisApplyTuning       applyTuning;
  late final AegisGetTuningLog      getTuningLog;
  late final AegisCreateAgentServer createAgentServer;
  late final AegisDestroyAgentServer destroyAgentServer;
  late final AegisAgentServerStart  agentServerStart;
  late final AegisAgentServerStop   agentServerStop;
  late final AegisAgentBroadcast    agentBroadcast;
  late final AegisAgentClientCount  agentClientCount;
  late final AegisVersion           version;

  AegisLibrary._(this._lib) {
    createPipeline    = _lib.lookupFunction<AegisCreatePipelineNative,    AegisCreatePipeline>   ('aegis_create_pipeline');
    destroyPipeline   = _lib.lookupFunction<AegisDestroyPipelineNative,   AegisDestroyPipeline>  ('aegis_destroy_pipeline');
    loadData          = _lib.lookupFunction<AegisLoadDataNative,           AegisLoadData>         ('aegis_load_data');
    configure         = _lib.lookupFunction<AegisConfigureNative,          AegisConfigure>        ('aegis_configure');
    start             = _lib.lookupFunction<AegisStartNative,              AegisStart>            ('aegis_start');
    pause             = _lib.lookupFunction<AegisPauseNative,             AegisPause>            ('aegis_pause');
    resume            = _lib.lookupFunction<AegisResumeNative,            AegisResume>           ('aegis_resume');
    stop              = _lib.lookupFunction<AegisStopNative,              AegisStop>             ('aegis_stop');
    getStatus         = _lib.lookupFunction<AegisGetStatusNative,          AegisGetStatus>        ('aegis_get_status');
    getBestModel      = _lib.lookupFunction<AegisGetBestModelNative,       AegisGetBestModel>     ('aegis_get_best_model');
    getSnapshot       = _lib.lookupFunction<AegisGetSnapshotNative,        AegisGetSnapshot>      ('aegis_get_snapshot');
    freeString        = _lib.lookupFunction<AegisFreeStringNative,         AegisFreeString>       ('aegis_free_string');
    applyTuning       = _lib.lookupFunction<AegisApplyTuningNative,        AegisApplyTuning>      ('aegis_apply_tuning');
    getTuningLog      = _lib.lookupFunction<AegisGetTuningLogNative,       AegisGetTuningLog>     ('aegis_get_tuning_log');
    createAgentServer = _lib.lookupFunction<AegisCreateAgentServerNative,  AegisCreateAgentServer>('aegis_create_agent_server');
    destroyAgentServer= _lib.lookupFunction<AegisDestroyAgentServerNative, AegisDestroyAgentServer>('aegis_destroy_agent_server');
    agentServerStart  = _lib.lookupFunction<AegisAgentServerStartNative,   AegisAgentServerStart> ('aegis_agent_server_start');
    agentServerStop   = _lib.lookupFunction<AegisAgentServerStopNative,    AegisAgentServerStop>  ('aegis_agent_server_stop');
    agentBroadcast    = _lib.lookupFunction<AegisAgentBroadcastNative,     AegisAgentBroadcast>   ('aegis_agent_broadcast');
    agentClientCount  = _lib.lookupFunction<AegisAgentClientCountNative,   AegisAgentClientCount> ('aegis_agent_client_count');
    version           = _lib.lookupFunction<AegisVersionNative,            AegisVersion>          ('aegis_version');
  }

  /// Singleton accessor. Returns null if the native library cannot be loaded.
  static AegisLibrary? get instance => _instance;

  /// Try to open the native library. Must be called once at app startup
  /// (e.g., inside main()) before using any C++ features.
  static bool tryLoad() {
    if (_instance != null) return true;
    try {
      final lib = _openLibrary();
      _instance = AegisLibrary._(lib);
      return true;
    } catch (_) {
      return false;
    }
  }

  static DynamicLibrary _openLibrary() {
    if (Platform.isWindows) {
      return DynamicLibrary.open('aegis_core.dll');
    } else if (Platform.isMacOS) {
      return DynamicLibrary.open('libaegis_core.dylib');
    } else {
      return DynamicLibrary.open('libaegis_core.so');
    }
  }

  /// Whether the C++ backend is available on this platform/build.
  static bool get isAvailable => _instance != null;

  /// Helper: call C function returning a UTF-8 string and free the buffer.
  String callStringFn(Pointer<Utf8> Function() fn) {
    final ptr = fn();
    if (ptr.address == 0) return '';
    final result = ptr.toDartString();
    freeString(ptr);
    return result;
  }
}
