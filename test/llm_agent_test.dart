// LLM agent tests with a mocked HTTP client: no network, no API cost.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aegis/agent/generation_snapshot.dart';
import 'package:aegis/services/llm_agent_core.dart';
import 'package:aegis/services/optimization_agent.dart';

GenerationSnapshot snap(int generation) => GenerationSnapshot(
  generation: generation,
  elapsed: Duration.zero,
  bestFitness: 0.1,
  worstFitness: 0.5,
  meanFitness: 0.3,
  medianFitness: 0.3,
  stdDevFitness: 0.05,
  q1Fitness: 0.2,
  q3Fitness: 0.4,
  improvementAbsolute: 0,
  improvementRelative: 0,
  improvementRate5: 0,
  improvementRate20: 0,
  stagnationCounter: 120,
  uniqueStructures: 20,
  structureEntropy: 2,
  phenotypicDiversity: 0.05,
  regressorFrequency: const {},
  populationVariance: 0.0025,
  successRate: 0.01,
  successRateHistory: const [],
  bestModelComplexity: 4,
  bestModelMaxDegree: 2,
  bestModelMaxDelay: 5,
  bestModelERR: const [],
  bestModelRMSE: 0.05,
  bestModelValidationRMSE: 0.06,
  bestModelR2: 0.98,
  islandSnapshots: const [],
  parameters: const {'mutationFactor': 0.5, 'crossoverRate': 0.9},
);

http.Response messagesReply(Map<String, dynamic> decision,
    {String stopReason = 'end_turn', String model = 'claude-opus-5-5'}) {
  return http.Response(
    jsonEncode({
      'id': 'msg_test',
      'type': 'message',
      'role': 'assistant',
      'model': model,
      'content': [
        {'type': 'thinking', 'thinking': ''},
        {'type': 'text', 'text': jsonEncode(decision)},
      ],
      'stop_reason': stopReason,
      'usage': {'input_tokens': 2000, 'output_tokens': 300, 'cache_read_input_tokens': 0},
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

LlmAgentCore agentWith(http.Client client, {String key = 'test-key', int maxCalls = 10}) =>
    LlmAgentCore(apiKeyProvider: () => key, client: client, consultEvery: 1, maxCalls: maxCalls);

void main() {
  test('valid structured reply → one bounded action; request is well-formed', () async {
    late Map<String, dynamic> sent;
    late Map<String, String> headers;
    final client = MockClient((req) async {
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      headers = req.headers;
      return messagesReply({
        'assessment': 'stagnation',
        'diagnosis': 'success rate 1% for 120 generations',
        'evidence_sufficient': true,
        'actions': [{'param': 'mutationFactor', 'value': 0.65, 'reason': 'larger steps'}],
        'rationale': 'stagnation with failing trials',
      });
    });
    final decisions = <AgentDecision>[];
    final actions = <(String, double)>[];
    final agent = agentWith(client)
      ..onDecision = decisions.add
      ..onSuggestion = (p, v, r) => actions.add((p, v));
    await agent.consult(snap(100));
    expect(actions, [('mutationFactor', 0.65)]);
    expect(decisions.single.status, 'action');
    expect(decisions.single.costUsd, closeTo((2000 * 4.0 + 300 * 20.0) / 1e6, 1e-12));
    expect(decisions.single.latencyMs, isNotNull);
    // Request shape
    expect(sent['model'], 'claude-opus-5-5');
    expect(sent.containsKey('thinking'), isFalse);
    expect((sent['output_config'] as Map)['format'], isNotNull);
    expect(headers['anthropic-version'], '2026-10-21');
    expect(headers['x-api-key'], 'test-key');
    final user = jsonDecode((sent['messages'] as List).single['content'] as String) as Map;
    expect(jsonEncode(user).toLowerCase().contains('test'), isFalse, reason: 'no test-set data sent');
  });

  test('insufficient evidence → no action', () async {
    final client = MockClient((_) async => messagesReply({
      'assessment': 'healthy',
      'diagnosis': 'still improving',
      'evidence_sufficient': false,
      'actions': [],
      'rationale': 'no clear signal',
    }));
    final decisions = <AgentDecision>[];
    var called = false;
    final agent = agentWith(client)
      ..onDecision = decisions.add
      ..onSuggestion = (_, _, _) => called = true;
    await agent.consult(snap(100));
    expect(called, isFalse);
    expect(decisions.single.status, 'insufficient_evidence');
  });

  test('out-of-bounds or oversized proposals are rejected locally', () async {
    final client = MockClient((_) async => messagesReply({
      'assessment': 'stagnation',
      'diagnosis': 'x',
      'evidence_sufficient': true,
      'actions': [{'param': 'mutationFactor', 'value': 1.6, 'reason': 'huge'}],
      'rationale': 'x',
    }));
    final decisions = <AgentDecision>[];
    var called = false;
    final agent = agentWith(client)
      ..onDecision = decisions.add
      ..onSuggestion = (_, _, _) => called = true;
    await agent.consult(snap(100));
    expect(called, isFalse);
    expect(decisions.single.status, 'rejected_locally');
  });

  test('refusal, HTTP errors and timeouts never propagate to the engine', () async {
    final statuses = <String>[];
    for (final handler in <Future<http.Response> Function(http.Request)>[
      (_) async => messagesReply({}, stopReason: 'refusal'),
      (_) async => http.Response('{"error":{"type":"overloaded_error"}}', 529),
      (_) async => http.Response('not json', 200),
    ]) {
      final agent = agentWith(MockClient(handler))..onDecision = (d) => statuses.add(d.status);
      await agent.consult(snap(100));
    }
    final slow = LlmAgentCore(
      apiKeyProvider: () => 'k',
      client: MockClient((_) => Completer<http.Response>().future),
      consultEvery: 1,
      timeout: const Duration(milliseconds: 50),
    )..onDecision = (d) => statuses.add(d.status);
    await slow.consult(snap(100));
    expect(statuses, ['refusal', 'error', 'error', 'error']);
  });

  test('no API key or exhausted budget → skipped without any request', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('{}', 500);
    });
    final statuses = <String>[];
    final noKey = agentWith(client, key: '')..onDecision = (d) => statuses.add(d.status);
    await noKey.consult(snap(100));
    final noBudget = agentWith(client, maxCalls: 0)..onDecision = (d) => statuses.add(d.status);
    await noBudget.consult(snap(100));
    final disabled = agentWith(client)
      ..enabled = false
      ..onDecision = (d) => statuses.add(d.status);
    await disabled.consult(snap(100));
    expect(requests, 0);
    expect(statuses, ['skipped', 'skipped', 'skipped']);
  });

  test('engine rejection is fed back into the next consultation', () async {
    final bodies = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
      return messagesReply({
        'assessment': 'stagnation',
        'diagnosis': 'x',
        'evidence_sufficient': true,
        'actions': [{'param': 'crossoverRate', 'value': 0.7, 'reason': 'x'}],
        'rationale': 'x',
      });
    });
    final agent = agentWith(client)..onSuggestion = (_, _, _) {};
    await agent.consult(snap(100));
    agent.onActionResult({'accepted': false, 'code': 'cooldown', 'message': 'cooldown 10'});
    await agent.consult(snap(150));
    final user = jsonDecode((bodies.last['messages'] as List).single['content'] as String) as Map;
    final prev = (user['observation'] as Map)['previousDecisions'] as List;
    expect(((prev.last as Map)['engine'] as Map)['code'], 'cooldown');
  });
}
