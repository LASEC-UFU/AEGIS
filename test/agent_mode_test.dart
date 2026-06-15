import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aegis/services/optimization_agent.dart';
import 'package:aegis/ui/screens/agent_dashboard_screen.dart';
import 'package:aegis/ui/state/app_state.dart';

void main() {
  test('engine supervisor defaults to local and can be disabled', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(engineProvider.notifier);
    expect(container.read(agentModeProvider), AgentMode.local);
    expect(notifier.agentName, 'Agente local adaptativo');
    expect(notifier.agentAvailable, isTrue);

    notifier.setAgentMode(AgentMode.off);

    expect(container.read(agentModeProvider), AgentMode.off);
    expect(notifier.agentName, 'Agente desligado');
  });

  testWidgets('dashboard exposes the supervisor mode selector before a run', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AgentDashboardScreen()),
      ),
    );

    expect(find.text('Supervisor adaptativo'), findsOneWidget);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('Remoto'), findsOneWidget);

    await tester.tap(find.text('Desligado'));
    await tester.pump();

    expect(container.read(agentModeProvider), AgentMode.off);
  });
}
