# P6: pré-registro do refino por erro de simulação (Passada B)

Data: 2026-11-25. Autorização: o usuário pediu "o P6 em paralelo como trilho
de qualidade" em 2026-11-25. Origem: [12_AUDITORIA_DO_11.md](../../docs/architecture/12_AUDITORIA_DO_11.md)
§4 e §6, e [13_P0_PROFILING.md](../../docs/architecture/13_P0_PROFILING.md) §3.3.

**Este arquivo é escrito e enviado ao git antes de qualquer execução do P6.**
Mudanças posteriores viram nova versão, com motivo registrado. Resultados
desfavoráveis são reportados.

## 1. Pergunta

Refinar os coeficientes de um modelo já escolhido pelo AEGIS, minimizando o
erro de **simulação livre** no treino em vez do erro de um passo, melhora a
simulação livre em dados não usados na escolha, desde que se impeça modelo
inadmissível?

O E2 (Fase 0) testou o LM por simulação **sem** veto e sem parada por
validação: −52 % no SB, −1 % no WH, +4,8 % no CT, com divergências. O P6
acrescenta as duas proteções e passa a tratar **modelos racionais**, que o E2
não rodava.

## 2. Objetos

- **Modelos:** os campeões do E3 (`experiments/results_phase0/<b>/e3/<célula>/run_*.json`),
  3 benchmarks × 8 células × 10 sementes = 240 modelos. Só `report.model` é
  lido (estrutura, coeficientes e intercepto).
- **Nada da estrutura muda:** variáveis, atrasos, expoentes (na grade de 0,5)
  e numerador/denominador ficam fixos. Só os coeficientes e o intercepto são
  refinados.
- **Dados:** só `est.csv`, com a divisão do E3. Nenhum arquivo de teste é
  aberto; a ferramenta não tem opção de teste.
  - CT: treino 0–819, validação 819–1024;
  - WH e SB: treino 0–16000, validação 16000–20000.
- **Normalização e convenções de simulação:** as do avaliador do núcleo,
  como no pré-registro da Fase 0 §0 (min–max em [−1, 1] no treino; treino
  simulado desde o maior atraso e pontuado a partir da linha 40; validação
  simulada desde `trainEnd − 40` e pontuada de `trainEnd` a `valEnd`;
  denominador protegido em ±1e−12; divergência quando |ŷ| > 10·max|y_treino|).

## 3. Divisão da validação

A validação é dividida em duas metades contíguas, **na mesma trajetória de
simulação** (uma única simulação desde `trainEnd − 40`):

| Benchmark | V_A (escolha da iteração) | V_B (medida) |
|---|---|---|
| CT | 819–921 | 921–1024 |
| WH, SB | 16000–18000 | 18000–20000 |

- **V_A** serve só para escolher qual iteração do LM é mantida.
- **V_B** é a medida principal. Não participa de nenhuma escolha.
- O RMSE na validação inteira é reportado como descritivo, sabendo que inclui
  V_A.

## 4. Método

1. **Ponto de partida:** os coeficientes do campeão (iteração 0).
2. **Levenberg–Marquardt** sobre a soma dos quadrados do erro de simulação
   livre no **treino**, com sensibilidades diretas exatas (modo direto) para
   numerador e denominador, inclusive a dependência pelas saídas simuladas.
   Configuração igual à do E2: no máximo 100 iterações, λ₀ = 1e−3, ×10 na
   rejeição e ÷3 na aceitação, escalonamento de Marquardt, parada em 10
   rejeições seguidas, ganho relativo < 1e−10 ou passo relativo < 1e−10.
3. **Veto de admissibilidade,** avaliado em cada iteração aceita do LM e na
   iteração 0. Uma iteração é admissível quando:
   - a simulação do treino e a da validação não divergem;
   - em modelos racionais, o denominador D(k) nas duas trajetórias:
     - não muda de sinal mais vezes que no modelo original;
     - tem min|D| ≥ τ, com τ = min(0,01; 0,5 × min|D| do modelo original nas
       mesmas trajetórias).
4. **Escolha:** entre as iterações admissíveis (a 0 sempre conta se for
   admissível), fica a de menor RMSE de simulação em **V_A**. Se nenhuma for
   admissível, fica a iteração 0 e o caso é contado como "sem refino".
5. Nenhum hiperparâmetro deste método é ajustado depois de ver resultados.

## 5. Critério (de desenvolvimento, não confirmatório)

- **Célula principal:** `mr39_zero_simulation` (o melhor pacote do E3).
- **Medida:** para cada modelo, razão r = RMSE_V_B(refinado) /
  RMSE_V_B(original), em unidades originais.
- **Critério:** mediana de r ≤ 0,95 em pelo menos 2 dos 3 benchmarks, **e**
  em nenhum benchmark mais de 2 dos 10 modelos com r > 1,10.
- **Consequência se atingido:** o P6 passa a candidato a etapa final do
  pipeline (refino do campeão), a ser decidido no A1 com teste próprio.
- **Se não atingido:** o P6 não entra no pipeline nesta forma; os dados são
  reportados.
- **Demais células:** descritivo, com a mesma medida.

## 6. Consistência e integridade (antes de usar os resultados)

- O simulador da ferramenta deve reproduzir o RMSE livre de treino e de
  validação do avaliador do núcleo (`aegis_evaluate_model`, sem reajuste) com
  diferença relativa ≤ 1e−9 para a iteração 0. Modelo que falhar é
  reportado como "inconsistente" e excluído do critério, com contagem.
- As sensibilidades são conferidas contra diferenças finitas num modelo
  racional pequeno antes do uso com dados reais (teste da ferramenta).
- Relatar: número de modelos, sem refino, inconsistentes, iterações, tempo
  por modelo, divergências e valores de τ.

## 7. Saídas

- `experiments/results_p6/<b>.jsonl`, uma linha por modelo (fora do git,
  como os demais resultados), e `experiments/results_p6/MANIFEST.jsonl` com o
  SHA-256 deste arquivo, do executável e dos dados.
- Relatório: `experiments/p6/P6_REPORT.md`.
- Build: worktree separado; `cpp/build` e `cpp/build_phase0` não são
  tocados. Código em `experiments/perf/` como patch.
