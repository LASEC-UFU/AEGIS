// Dart-side WebSocket client that connects to the C++ AgentController
// running on localhost:8765.
//
// Responsibilities:
//  - Connect / auto-reconnect to the C++ WebSocket server
//  - Expose the generation snapshot stream to the UI
//  - Allow the AI agent (or user) to send parameter-tuning suggestions

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Incoming generation report from the C++ engine (matches broadcast JSON).
class EngineReport {
  final int generation;
  final double bestFitness;
  final double rmseValidation;
  final double rmseTest;
  final double bic;
  final double aic;
  final double populationDiversity;
  final int stagnation;
  final double muF;
  final double muCr;
  final int numTerms;
  final bool isStable;
  final bool overfitting;
  final bool underfitting;
  final bool peOk;
  final List<double> residualAutocorr;
  final List<double> coefficients;
  final List<double> exponents;
  final String alerts;

  const EngineReport({
    required this.generation,
    required this.bestFitness,
    required this.rmseValidation,
    required this.rmseTest,
    required this.bic,
    required this.aic,
    required this.populationDiversity,
    required this.stagnation,
    required this.muF,
    required this.muCr,
    required this.numTerms,
    required this.isStable,
    required this.overfitting,
    required this.underfitting,
    required this.peOk,
    required this.residualAutocorr,
    required this.coefficients,
    required this.exponents,
    required this.alerts,
  });

  factory EngineReport.fromJson(Map<String, dynamic> j) {
    double d(String k) => (j[k] as num?)?.toDouble() ?? 0.0;
    int    n(String k) => (j[k] as num?)?.toInt()    ?? 0;
    bool   b(String k) => j[k] == true;
    List<double> arr(String k) {
      final raw = j[k];
      if (raw is List) return raw.map((e) => (e as num).toDouble()).toList();
      return [];
    }

    return EngineReport(
      generation:         n('generation'),
      bestFitness:        d('best_fitness'),
      rmseValidation:     d('rmse_validation'),
      rmseTest:           d('rmse_test'),
      bic:                d('bic'),
      aic:                d('aic'),
      populationDiversity:d('population_diversity'),
      stagnation:         n('stagnation'),
      muF:                d('mu_f'),
      muCr:               d('mu_cr'),
      numTerms:           n('num_terms'),
      isStable:           b('is_stable'),
      overfitting:        b('overfitting'),
      underfitting:       b('underfitting'),
      peOk:               b('pe_ok'),
      residualAutocorr:   arr('residual_autocorr'),
      coefficients:       arr('coefficients'),
      exponents:          arr('exponents'),
      alerts:             j['alerts'] as String? ?? '',
    );
  }
}

/// A parameter-tuning suggestion sent from Dart to the C++ engine.
class AgentSuggestion {
  final String paramName;
  final double proposedValue;
  final String reason;

  const AgentSuggestion({
    required this.paramName,
    required this.proposedValue,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
    'proposed_changes': {paramName: proposedValue},
    'reason': reason,
  };
}

/// Connection state for the WebSocket agent service.
enum AgentConnectionState { disconnected, connecting, connected, error }

/// Manages the WebSocket connection to the C++ AgentController.
class AgentWebSocketService {
  final String host;
  final int port;

  AgentWebSocketService({this.host = 'localhost', this.port = 8765});

  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  bool _shouldConnect = false;

  AgentConnectionState _connectionState = AgentConnectionState.disconnected;
  AgentConnectionState get connectionState => _connectionState;

  final _reportController    = StreamController<EngineReport>.broadcast();
  final _connectionController= StreamController<AgentConnectionState>.broadcast();
  final _responseController  = StreamController<Map<String, dynamic>>.broadcast();

  /// Stream of generation reports from the C++ engine.
  Stream<EngineReport> get reports => _reportController.stream;

  /// Stream of connection state changes.
  Stream<AgentConnectionState> get connectionStates =>
      _connectionController.stream;

  /// Stream of raw response messages (acknowledgements, errors) from engine.
  Stream<Map<String, dynamic>> get responses => _responseController.stream;

  // ── Connection lifecycle ─────────────────────────────────────────────────

  void connect() {
    _shouldConnect = true;
    _tryConnect();
  }

  void disconnect() {
    _shouldConnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _channel?.sink.close();
    _channel = null;
    _setConnectionState(AgentConnectionState.disconnected);
  }

  void _tryConnect() {
    if (!_shouldConnect) return;
    _setConnectionState(AgentConnectionState.connecting);

    try {
      final uri = Uri.parse('ws://$host:$port');
      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone:  _onDone,
        cancelOnError: false,
      );

      _setConnectionState(AgentConnectionState.connected);
    } catch (e) {
      _setConnectionState(AgentConnectionState.error);
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic message) {
    try {
      final json = jsonDecode(message as String) as Map<String, dynamic>;
      if (json.containsKey('generation')) {
        _reportController.add(EngineReport.fromJson(json));
      } else {
        _responseController.add(json);
      }
    } catch (_) {
      // ignore malformed messages
    }
  }

  void _onError(Object error) {
    _setConnectionState(AgentConnectionState.error);
    _scheduleReconnect();
  }

  void _onDone() {
    if (_shouldConnect) {
      _setConnectionState(AgentConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), _tryConnect);
  }

  void _setConnectionState(AgentConnectionState state) {
    _connectionState = state;
    _connectionController.add(state);
  }

  // ── Sending suggestions ──────────────────────────────────────────────────

  /// Send a parameter-tuning suggestion to the C++ engine.
  /// Returns false if the connection is not open.
  bool sendSuggestion(AgentSuggestion suggestion) {
    if (_channel == null ||
        _connectionState != AgentConnectionState.connected) {
      return false;
    }
    try {
      _channel!.sink.add(jsonEncode(suggestion.toJson()));
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Dispose ──────────────────────────────────────────────────────────────

  void dispose() {
    disconnect();
    _reportController.close();
    _connectionController.close();
    _responseController.close();
  }
}
