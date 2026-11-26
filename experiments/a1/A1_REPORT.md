# A1: relatório

Data: 2026-11-26. Pré-registro: [A1_PREREG.md](A1_PREREG.md), congelado no
commit `f51b8a7` antes de qualquer execução. Manifesto das 30 execuções com
hashes: [MANIFEST_A1.txt](MANIFEST_A1.txt) (`5d1c5b8`), enviado antes de
abrir a análise. Saída da análise, rodada uma vez:
[A1_RESULTS.md](A1_RESULTS.md) (`4953ee1`).

## 1. O que foi comparado

- **A1:** melhor pacote do E3 (penalidades γ = δ = β = α = 0, teto de 39
  regressores, `errorMode` = `simulation`) + P2′a (`fitMethod` = `normal`) +
  veto de admissibilidade (`vetoTopK` = 5) + refino final por simulação
  (P6). Sem agente.
- **1.1.0:** `aegis_full`, execuções do protocolo 1.1.0.
- **Igual nos dois braços:** dados, divisão, arquivos de teste (CT e WH
  `test.csv`, SB `test_multisine.csv`), sementes 1–10 e orçamentos (CT
  3×10⁵, WH e SB 1,5×10⁵ avaliações).

## 2. Integridade

- 30 de 30 execuções completas e válidas (CT 07:41–07:45; SB até 09:55; WH
  até 10:00 de 2026-11-26).
- **Cegamento:** nenhum dado de teste foi lido antes do commit do manifesto.
  O script de análise e o pré-registro não mudaram desde o congelamento
  (conferido com `git diff`).
- **Desvio sem efeito nos resultados:** a primeira tentativa de execução
  falhou antes de rodar qualquer coisa (diretório de saída inexistente).
- Durante o A1, uma recompilação de desenvolvimento falhou no link. O
  executável do A1 foi conferido pelo hash do manifesto e está intacto.

## 3. Resultado do critério pré-registrado

RMSE de simulação livre no **teste**, unidades originais; Wilcoxon dos
postos sinalizados exato, unilateral, pareado por semente; Holm sobre WH e
SB.

| Benchmark | Mediana A1 | Mediana 1.1.0 | Razão | p | p Holm | Divergências no teste A1 / 1.1.0 |
|---|---|---|---|---|---|---|
| **WH** | **9,32 mV** | 46,1 mV | **0,202** | 0,001 | 0,002 | 0 / 0 |
| **SB** (multisine) | **0,349 mV** | 3,78 mV | **0,092** | 0,001 | 0,002 | 0 / 0 |
| CT (secundário) | 0,712 V | 0,661 V | 1,078 | 0,86 | — | **3** / 0 |

**Gate primário: atingido.** No WH e no SB, o A1 é melhor que o 1.1.0 nas
10 sementes (p = 1/1024 é o mínimo possível com 10 pares).

## 4. Desfechos secundários

| | CT | WH | SB |
|---|---|---|---|
| RMSE de validação, mediana A1 / 1.1.0 | 0,431 / 0,834 V | 8,55 / 50,8 mV | 0,309 / 3,34 mV |
| K mediano A1 / 1.1.0 | 28 / 4 | 34 / 6 | 28,5 / 7 |
| Refino final aplicado | 6 de 10 | 8 de 10 | 10 de 10 |
| Tempo de parede mediano A1 / 1.1.0 | 127 / 29 s | 2 294 / 502 s | 2 136 / 502 s |

- **Tempo:** o 1.1.0 rodou na máquina original, com outro paralelismo; a
  comparação é só ordem de grandeza. O A1 usa modelos ≈ 5× maiores, e o
  custo por avaliação cresce com K². Sem o P2′a, as execuções do A1 no WH e
  no SB levariam de 7 a 8 h cada (E3).
- **SB arrow (extrapolação),** reavaliado sem reajuste com
  `aegis_evaluate_models`. O avaliador reproduz exatamente o RMSE de teste
  multisine do próprio `run_1.json` (0,0003456230774 V).

| | Mediana | Faixa | Divergências |
|---|---|---|---|
| A1 | **0,507 mV** | 0,435–0,986 | 0 |
| 1.1.0 | 7,56 mV | 7,41–7,56 | 0 |

## 5. Leitura

1. **No WH e no SB o ganho é grande e consistente:** 5× no WH, 11× no SB
   multisine e 15× no SB arrow, sem nenhuma divergência. A validação
   antecipou o teste: os ganhos têm a mesma ordem.
2. **CT: a validação melhora e o teste piora.** O RMSE de validação cai pela
   metade (0,83 → 0,43 V), mas o teste piora 8 %, com 3 divergências.
   - É o padrão do E1: com 819 amostras de treino e 205 de validação, mais
     capacidade sobreajusta a validação curta.
   - A investigação do pós-processamento (diário, 2026-11-26) mostrou duas
     coisas: a busca otimiza a validação com convenção de início diferente
     da reportada, e a poda e o refino introduzem variância no CT.
   - Corrigir isso é candidato a A2; não é do A1, que está congelado.
3. **Comparação descritiva com a literatura** (`docs/architecture/02_LITERATURA.md`;
   protocolos diferem, ver ressalvas):

| | A1 | Referências conferidas |
|---|---|---|
| WH (mV) | 9,3 | pNARX 30,5; GP-NARX 12,8; MLP-NARX 87,2; TAG + programação genética (método mais parecido) 23,5; LS-SVM 4,07; RNN/LSTM 1,5–4,9; espaço de estados 0,24–0,49 |
| SB multisine (mV) | 0,35 | pNARX 0,505; GP-NARX 0,418; SUBNET 0,36 |
| SB arrow completo (mV) | 0,51 | pNARX 1,41; GP-NARX 0,77; SUBNET 1,4; PNLSS 0,26; LS-SVM 0,32 |

## 6. Limitações

- Estimação com 20 000 amostras no WH e no SB (não o conjunto completo); uma
  divisão treino/validação; 10 sementes.
- Protocolos da literatura (janela inicial, `n_ini`, partes do arrow)
  diferem; a tabela da §5 é contexto, não comparação controlada.
- O pacote A1 muda quatro coisas de uma vez (penalidades, teto, modo de erro,
  veto/refino); este experimento não atribui o ganho a cada parte. O E3 já
  indicou que penalidades e teto respondem pela maior parte no WH e no SB.
- O CT piorou no teste. O A1 não deve ser apresentado como melhor em todos
  os sistemas.
