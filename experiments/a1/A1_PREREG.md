# A1: pré-registro

Data: 2026-11-26. Decisão do usuário (2026-11-26): "use o melhor pacote do E3
e pré-registre o A1 e abrir os testes do WH e do SB só depois de congelar o
desenho do A1".

**Este arquivo, o script de análise `tool/experiments/a1_analysis.dart` e o
código do núcleo no commit em que forem enviados ao git congelam o desenho do
A1.** Nenhuma execução do A1 acontece antes desse commit. Mudanças
posteriores viram nova versão, com motivo. Resultados desfavoráveis são
reportados.

## 1. Pergunta

O pacote A1 (melhor célula do E3 + aceleração P1/P2′a + veto de
admissibilidade + refino final por simulação) identifica modelos com menor
erro de **simulação livre no teste** que o AEGIS 1.1.0 (`aegis_full`), nos
mesmos dados, sementes e orçamentos?

## 2. Braços

| Braço | Configuração | Código |
|---|---|---|
| **A1** | `aegis_full.json` + `maxRegressors` = 39, `complexityPenalty` = `exponentPenalty` = `denominatorPenalty` = `alpha` = 0, `gammaAnnealStart` = `gammaAnnealEnd` = 0, `errorMode` = `simulation`, `freeRunHorizon` = 0, `fitMethod` = `normal`, `admissibilityVeto` = true (`vetoTopK` = 5), `finalRefine` = `simulation` | `cpp/build_a1/aegis_batch.exe` deste commit |
| **Referência: 1.1.0** | `aegis_full`, execuções já feitas no protocolo 1.1.0 (`experiments/results/<b>/aegis_full/`) | binário congelado |

- O A1 não usa agente. O controlador adaptativo (CAC, documento 14) está em
  desenvolvimento, mostrou resultado desfavorável na primeira rodada de
  desenvolvimento (CT, validação) e terá pré-registro próprio.
- Os pisos de ζ do currículo, o θ da ilha *free-run* e η = 1 continuam como
  no `aegis_full`, como no E3.

## 3. Dados, sementes e orçamento (iguais ao protocolo 1.1.0)

| Benchmark | Estimação | Teste | Orçamento | Sementes |
|---|---|---|---|---|
| CT | `cascaded_tanks/est.csv` | `cascaded_tanks/test.csv` | 3×10⁵ | 1–10 |
| WH | `wiener_hammerstein/est.csv` | `wiener_hammerstein/test.csv` | 1,5×10⁵ | 1–10 |
| SB | `silverbox/est.csv` | `silverbox/test_multisine.csv` | 1,5×10⁵ | 1–10 |

- Divisão: `trainRatio` = 0,8 do `est.csv`; validação = restante do
  `est.csv`; teste = arquivo de teste anexado (como `run_conditions.sh`).
- Execução: `experiments/a1/run_a1.sh`, até 6 processos, BelowNormal.
- **Cegamento:** as métricas de teste são gravadas nos `run_*.json`, como no
  protocolo, mas **ninguém as lê** antes de todas as 30 execuções terminarem
  e o manifesto ser enviado ao git. Então `a1_analysis.dart` roda **uma vez**.

## 4. Desfecho principal e critério

- **Medida:** RMSE de simulação livre no teste, em unidades originais
  (`report.metrics.test.rmseFreeRunOrig`), uma por execução.
- **Comparação:** A1 contra 1.1.0, pareada por semente (sementes 1–10 nos
  dois braços).
- **Teste estatístico:** Wilcoxon dos postos sinalizados, exato, unilateral
  (A1 < 1.1.0), sobre as diferenças de log RMSE por semente.
- **Critério (gate primário, como no parecer 07 §5):** no **WH e no SB**,
  mediana da razão A1/1.1.0 ≤ 0,90 **e** p de Holm (2 comparações) < 0,05 em
  ambos.
- **Divergência no teste** conta como RMSE infinito e entra na comparação
  como pior posto.

## 5. Desfechos secundários (reportados sempre, sem critério)

1. CT: mesma medida e teste, sem entrar no gate. O E1 mostrou que mais
   capacidade pode piorar o CT.
2. Divergências no teste por braço.
3. RMSE de validação (simulação livre).
4. K (`numParameters`), campeão admissível ao fim, refino final aplicado ou
   não (`postProcessing.simulationRefine.applied`).
5. Tempo de parede por execução. A referência rodou em outra máquina e com
   outro paralelismo: só ordem de grandeza.
6. **SB arrow** (extrapolação): os modelos dos dois braços são reavaliados em
   `silverbox/test_arrow.csv` com `aegis_evaluate_models`, sem reajuste.
   Descritivo.

## 6. Abertura dos testes do WH e do SB

Pela decisão do usuário, os testes do WH e do SB só são abertos depois do
congelamento deste desenho. A ordem fica:
1. commit deste pré-registro e do script de análise (congelamento);
2. as 30 execuções do A1;
3. commit do manifesto do A1;
4. **abertura:** `a1_analysis.dart` (A1 × 1.1.0) e, em seguida, a análise
   pendente do protocolo 1.1.0 (`analyze.dart` em WH e SB e a avaliação
   arrow), que deixam de estar bloqueadas.

## 7. O que não muda depois de ver resultados

Configuração, sementes, orçamento, métrica, teste estatístico, critério e
script de análise. Qualquer falha de execução é reportada e repetida com a
mesma semente, registrando o motivo.
