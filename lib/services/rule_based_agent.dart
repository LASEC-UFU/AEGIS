// Rule-based AI agent that connects to the C++ AEGIS engine via WebSocket
// and sends parameter adjustments based on diagnostic heuristics.
//
// To use: instantiate RuleBasedAgent, call start(), stop() when done.
// The agent self-tunes the DE parameters using the rules below.

import 'dart:async';

import 'agent_websocket_service.dart';

/// A simple rule-based agent that monitors the engine and suggests
/// parameter adjustments to keep the optimization healthy.
class RuleBasedAgent {
  final AgentWebSocketService _ws;
  StreamSubscription<EngineReport>? _sub;

  // Cooldown: minimum generations between suggestions on the same param
  final Map<String, int> _lastSuggestionGen = {};
  static const int _cooldown = 30; // generations

  RuleBasedAgent({int port = 8765})
      : _ws = AgentWebSocketService(port: port);

  void start() {
    _ws.connect();
    _sub = _ws.reports.listen(_evaluate);
  }

  void stop() {
    _sub?.cancel();
    _ws.disconnect();
  }

  void dispose() {
    stop();
    _ws.dispose();
  }

  // ── Core heuristics ─────────────────────────────────────────────────────

  void _evaluate(EngineReport r) {
    _checkLowDiversity(r);
    _checkStagnation(r);
    _checkOverfitting(r);
    _checkUnderfitting(r);
    _checkHighExploration(r);
  }

  /// Diversidade < 0.1: aumentar F (exploração)
  void _checkLowDiversity(EngineReport r) {
    if (r.populationDiversity < 0.1 && r.muF < 0.8) {
      _suggest(r, 'mutationFactor', (r.muF + 0.15).clamp(0.0, 2.0),
          'diversidade baixa (${r.populationDiversity.toStringAsFixed(3)}): '
          'aumentando F para diversificar');
    }
  }

  /// Estagnação > 100 gerações sem melhora: aumentar migração
  void _checkStagnation(EngineReport r) {
    if (r.stagnation > 100) {
      _suggest(r, 'migrationRate', 0.2,
          'estagnação por ${r.stagnation} gerações: forçando migração');
    }
  }

  /// Overfitting detectado: aumentar penalidade de complexidade
  void _checkOverfitting(EngineReport r) {
    if (r.overfitting) {
      _suggest(r, 'complexityPenalty', 3.0,
          'overfitting detectado (val_rmse/train_rmse elevado): '
          'aumentando penalidade de complexidade');
    }
  }

  /// Underfitting detectado: reduzir penalidade para permitir modelos maiores
  void _checkUnderfitting(EngineReport r) {
    if (r.underfitting) {
      _suggest(r, 'complexityPenalty', 0.2,
          'underfitting detectado: reduzindo penalidade para explorar '
          'modelos mais complexos');
    }
  }

  /// CR muito alto + diversidade ok: reduzir CR para convergência
  void _checkHighExploration(EngineReport r) {
    if (r.muCr > 0.95 && r.populationDiversity > 0.4 && r.stagnation < 20) {
      _suggest(r, 'crossoverRate', 0.7,
          'exploração excessiva: reduzindo CR para acelerar convergência');
    }
  }

  // ── Suggestion helper with cooldown ─────────────────────────────────────

  void _suggest(EngineReport r, String param, double value, String reason) {
    final lastGen = _lastSuggestionGen[param] ?? -999;
    if (r.generation - lastGen < _cooldown) return;

    final sent = _ws.sendSuggestion(AgentSuggestion(
      paramName: param,
      proposedValue: value,
      reason: reason,
    ));

    if (sent) {
      _lastSuggestionGen[param] = r.generation;
      // ignore: avoid_print
      print('[Agent] Gen ${r.generation}: $param → $value ($reason)');
    }
  }
}
