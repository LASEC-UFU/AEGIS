# P6: relatório do refino por erro de simulação

Data: 2026-11-25. Pré-registro: [P6_PREREG.md](P6_PREREG.md), commit
`01d62e6`, anterior a todas as execuções. Ferramenta: `aegis_p6` (patch
`experiments/perf/p1_p2a_p6.patch`), build separado. Script:
`experiments/p6/run_p6.sh`. Resumo: `tool/experiments/p6_summary.dart` →
`experiments/results_p6/SUMMARY_P6.md` (fora do git). Dados brutos:
`experiments/results_p6/<b>.jsonl`.

**Só validação.** Nenhum arquivo de teste foi aberto. A medida principal é o
RMSE de simulação livre na **segunda metade da validação (V_B)**, que não
participa de nenhuma escolha. A primeira metade (V_A) só escolhe a iteração
do LM.

## 1. Integridade

- **Selftest antes dos dados reais:** sensibilidades racionais contra
  diferenças finitas centrais com diferença relativa máxima de 6e−10; o LM
  recupera um modelo racional sintético até perda 1e−31.
- **Consistência com o núcleo:** nos 233 modelos usados, o simulador da
  ferramenta reproduz o RMSE livre de treino e de validação do avaliador do
  núcleo com diferença relativa ≤ 1e−9. O modelo refinado também foi
  reavaliado pelo núcleo, com a mesma concordância.
- **Desvio (defeito da ferramenta, corrigido antes dos resultados):** na
  primeira execução, a ferramenta marcava como não diferenciável qualquer
  fator com expoente < 1 em x = 0, inclusive na **entrada** u, que não
  depende dos coeficientes. Todos os modelos do WH paravam na iteração 0. A
  correção restringe a verificação aos fatores da saída simulada, os únicos
  derivados. Nenhum resultado de refino foi usado para decidir a correção,
  só o status. A saída parcial foi arquivada e o P6 rodou de novo do zero
  (EXPERIMENT_LOG, 2026-11-25).
- **Excluídos (originais inadmissíveis):** 7 de 240, todos no CT. Em todos,
  o campeão do E3 **diverge na simulação livre do treino** (flag
  `freeRunDiverged` do próprio núcleo no `run_*.json`); em 2 deles também na
  validação.
  - CT `mr39_zero_simulation`: sementes 23, 26 e 28 (3 de 10);
  - CT `mr39_zero_one_step`: 21, 22 e 25;
  - CT `mr8_default_one_step`: 26.
- **LM:** 225 convergiram, 6 pararam no limite de 100 iterações, 2 por
  rejeições seguidas. Tempo mediano por modelo: 0,01–1,3 s.

## 2. Critério pré-registrado (célula `mr39_zero_simulation`)

r = RMSE_V_B(refinado) / RMSE_V_B(original). Critério: mediana de r ≤ 0,95 e
no máximo 2 modelos com r > 1,10, em pelo menos 2 dos 3 benchmarks.

| Benchmark | Modelos usados | Mediana de r | r < 0,95 | r > 1,10 | V_B mediano, original → refinado | Resultado |
|---|---|---|---|---|---|---|
| CT | 7 de 10 | 1,000 | 2 | 2 | 0,431 → 0,485 V | **não atingido** |
| WH | 10 | **0,873** | 7 | 0 | 11,0 → 9,5 mV | **atingido** |
| SB | 10 | **0,841** | 10 | 0 | 0,36 → 0,29 mV | **atingido** |

**Resultado: critério atingido em 2 de 3.** Pelo pré-registro, o P6 passa a
candidato a etapa final do pipeline (refino do campeão), a decidir no A1 com
teste próprio.

## 3. Demais células (descritivo)

Mediana de r em V_B:

| Célula | CT | WH | SB |
|---|---|---|---|
| mr39_zero_simulation | 1,000 | 0,873 | 0,841 |
| mr39_zero_one_step | 1,000 | **0,582** | 0,727 |
| mr8_zero_simulation | 1,000 | 0,803 | 0,601 |
| mr8_zero_one_step | 1,000 | 0,760 | 0,684 |
| mr39_default_simulation | 1,000 | 0,829 | 1,000 |
| mr39_default_one_step | 1,000 | 0,949 | **0,551** |
| mr8_default_simulation | **1,125** | 0,822 | 0,665 |
| mr8_default_one_step | 1,000 | 0,949 | 0,551 |

## 4. O que os dados mostram

1. **WH e SB: o refino melhora 15 das 16 células e não piora nenhuma,** com mediana de r
   entre 0,55 e 0,95 (a exceção é SB `mr39_default_simulation`, 1,000), sem
   nenhum modelo com r > 1,10. É o ganho que o E2 já
   sugeria no SB, agora também no WH e em modelos racionais.
2. **O ganho é maior onde a busca otimizou um passo à frente:** WH
   `mr39_zero_one_step` cai de 29,3 para 18,9 mV (r = 0,58); SB
   `mr39_default_one_step` de 3,43 para 1,89 mV. O refino corrige parte do
   desalinhamento entre o ajuste de um passo e o uso em simulação.
3. **CT: sem ganho, como no E2.** A mediana fica em 1,000 (em várias células
   a iteração 0 é a escolhida por V_A) e há pioras: 2 modelos com r > 1,10
   na célula principal e 5 em `mr8_default_simulation`. Com 102 amostras em
   V_A e 103 em V_B, a escolha por V_A é ruidosa e não protege V_B.
4. **Achado de estabilidade:** 3 dos 10 campeões da melhor célula do E3 no CT
   divergem em simulação livre **no treino**, embora sejam estáveis na
   validação, que é onde a busca os avaliou. O critério de seleção atual não
   vê isso. O veto de admissibilidade (M9 do parecer 07) deve incluir a
   simulação do treino.
5. **Custo:** desprezível (≤ 1,3 s por modelo), em linha com o 13 §3.3.

## 5. O que os dados não mostram

- **Desempenho no teste:** nada do teste foi usado.
- **Efeito dentro da busca:** o refino foi aplicado só ao campeão, depois da
  busca. Se usado dentro do laço evolutivo, o efeito pode ser outro.
- **CT:** V_A e V_B têm cerca de 100 amostras cada. O resultado do CT não
  separa "não ajuda" de "não dá para medir".
- O E3 tem uma única divisão por benchmark; o critério é de desenvolvimento.

## 6. Consequência

- Para o A1 (decisão do usuário): incluir o refino do campeão por erro de
  simulação, com veto e escolha numa parte da validação, como etapa final;
  no CT, manter a opção de não refinar (a iteração 0 é sempre candidata).
- Incluir a simulação livre do **treino** no veto de admissibilidade.
