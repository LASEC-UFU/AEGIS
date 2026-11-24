# Fase 0: relatório de E1, E2 e E3

Data: 2026-11-20. Pré-registro: [PHASE0_PREREG.md](PHASE0_PREREG.md), commit
`d275810`, anterior a todas as execuções. Tabela completa por estrutura:
[SUMMARY_E1E2.md](../results_phase0/SUMMARY_E1E2.md). Dados brutos:
`experiments/results_phase0/<b>/e1e2.jsonl`. Manifesto com hashes:
`experiments/results_phase0/MANIFEST.jsonl`. O E3 (triagem só por
configuração) rodou depois do protocolo 1.1.0; seu relatório está na §7 (2026-11-23).

**Só validação.** Nenhum dado de teste foi lido. A métrica é o RMSE de
simulação livre na validação, em unidades originais. Não é comparável com os
números de teste da literatura (ver `docs/architecture/02_LITERATURA.md`).

## 1. Integridade

- **Testes da ferramenta:** 11 de 11 passaram antes do uso com dados reais.
- **Consistência:** o simulador da Fase 0 reproduziu o RMSE livre de treino
  do avaliador do núcleo em **todas** as 52 estruturas, com diferença
  relativa ≤ 1e−9.
- **Campeões:** os 7 + 3 + 3 campeões distintos do `aegis_full` 1.1.0 foram
  reajustados por QR com a mesma divisão. Os coeficientes são idênticos aos
  originais (diferença máxima 0), o que confirma que a divisão e o ajuste
  são os mesmos do estudo.
- **Sem execução:** nenhuma estrutura da tabela principal deixou de ser
  executada. Todas são polinomiais e nenhuma excede q = 150.

## 2. Resultado dos critérios pré-registrados

| | CT | WH | SB | Critério (2 de 3) |
|---|---|---|---|---|
| **E1**: PN_K40 (QR) / mediana dos campeões | 1,013 / 0,848 V = **1,19** ✗ | 26,5 / 50,8 mV = **0,52** ✓ | 0,60 / 3,34 mV = **0,18** ✓ | **apoiado** |
| **E2**: mediana de (V_LM − V_QR)/V_QR | **+4,8 %** ✗ (1 divergência com LM) | **−1,1 %** ✗ (1 divergência com LM) | **−52,1 %** ✓ (0 divergências) | **não apoiado** |

**Leitura pré-registrada:**
- **E1:** a capacidade, com estruturas fixas e QR, supera os campeões do
  AEGIS no WH e no SB.
- **E2:** o ajuste por erro de simulação, sem restrição de estabilidade, não
  melhora a validação de forma consistente.

## 3. Números principais (validação, RMSE de simulação livre)

| Estrutura | K | CT (V) QR → LM | WH (mV) QR → LM | SB (mV) QR → LM |
|---|---|---|---|---|
| Campeões AEGIS (mediana) | 4–7 | 0,848 → 0,942 | 50,8 → 48,2 | 3,34 → 1,94 |
| ARX_L (atrasos do DCE) | 14 / 19 / 22 | 0,859 → 0,949 | 48,2 → 48,1 | 6,27 → **76,7** |
| PN_K20 | 20 | 1,101 → **0,727** | 28,8 → 26,1 | 0,92 → 0,31 |
| PN_K40 | 40 | 1,013 → **28,5 (diverge)** | 26,5 → 26,1 | 0,60 → 0,27 |
| PN_DCE | 40 / 91 / 148 | 1,141 → 0,909 | 25,2 → **2 727 (diverge)** | 0,53 → 0,27 |
| E1b_5 (espinha ARX + 5) | 19 / 24 / 27 | 1,658 → 1,059 | 26,4 → 26,1 | 0,70 → 0,28 |

## 4. O que os dados mostram, e o que não mostram

1. **WH e SB: o AEGIS 1.1.0 fica preso em modelos pequenos demais.**
   - No WH, os campeões (6–7 coeficientes) empatam com um ARX linear
     (48–51 mV).
   - Estruturas univariadas simples de 20–40 termos, escolhidas por FROLS
     só no treino e ajustadas por QR, chegam a cerca de 26 mV.
   - No SB a diferença é de 5 a 6 vezes.
   - Isso apoia a hipótese do 06 (capacidade e parcimônia) e o H8.
   - **O que isso não mostra:** se a causa é o teto de regressores, as
     penalidades ou a exploração. O E3 e o H8 reduzido servem para separar
     essas causas.
2. **CT: mais capacidade piora a validação.**
   - Com o registro curto (819 amostras de treino) e uma validação de 205
     amostras, modelos de 20–40 termos ajustados por QR simulam pior que os
     campeões de 4 coeficientes.
   - A hipótese de capacidade **não** vale para o CT. Não se deve
     generalizar a partir de WH e SB.
3. **O ajuste por simulação (LM) ajuda no SB, é neutro no WH e atrapalha no
   CT.**
   - Ele sempre reduz o erro de **treino** (exceto em casos já no ótimo).
   - Mas sobreajusta a trajetória: no CT os campeões pioram de 0,85 para
     0,94 V.
   - Gera modelos que divergem na validação: PN_K40 no CT e PN_DCE no WH.
   - Também piora muito o ARX_L do SB (6,3 → 76,7 mV), apesar de reduzir
     o erro de treino.
   - Sem veto de admissibilidade e sem regularização, **o LM não deve
     entrar como componente padrão.** Isso confirma a ordem defendida no
     parecer: veto de admissibilidade antes do LM.
4. **E1b, a espinha linear (descritivo):**
   - no WH e no SB, a espinha ARX com 3 a 5 termos não lineares chega perto
     do PN_K40 com menos termos: WH 26,4 contra 26,5 mV; SB 0,70 contra
     0,60 mV;
   - no CT é pior que os campeões.
   - Apoia manter o H9 como hipótese, não adotá-lo.
5. **Controle u(k) contemporâneo (descritivo, com QR):**
   - **WH:** muda menos de 1 %.
   - **SB:** melhora de 8 a 16 % (ARX 6,27 → 5,75 mV; PN_DCE 0,529 →
     0,445 mV).
   - **CT:** piora o ARX (0,861 → 0,888 V) e melhora o PN_DCE (1,143 →
     1,092 V).
   - Leitura: a convenção de atrasos do AEGIS (a partir de 1) custa algo no
     SB, mas não explica a diferença principal, que é de 5 a 6 vezes entre
     campeões e estruturas maiores. Incluir u(k) é decisão de representação
     a registrar no A1, não um ajuste silencioso.

## 5. Consequência para o A1, conforme o pré-registro

**Priorizar** capacidade, representação e pressão de seleção:

- teto de regressores;
- pesos de parcimônia;
- avaliação de candidatos maiores;
- a espinha linear como hipótese.

O E3 diz se a triagem só por configuração já mostra esse efeito dentro do
próprio AEGIS. Depois vem o H8 reduzido (M7).

**Não priorizar** o ajustador LM como componente padrão. Ele pode voltar
como refinamento opcional, só depois do veto de admissibilidade e com teste
próprio. Isso seria um plano novo, não este.

**No CT,** qualquer aumento de capacidade precisa de controle de
complexidade que funcione com registros curtos. É um caso de teste
importante para não piorar o CT ao melhorar WH e SB.

## 6. Limitações

- Uma única divisão treino/validação por benchmark. As estruturas não são
  amostras independentes. Os critérios são de desenvolvimento, não
  confirmatórios.
- No WH e no SB a estimação usa 20 000 amostras, não o conjunto completo.
- Os campeões são do estudo 1.1.0, com a configuração `aegis_full`. Outras
  configurações do AEGIS podem gerar modelos maiores; o E3 testa isso.
- O LM seguiu exatamente o pré-registro: sem regularização, sem restrição de
  estabilidade, 100 iterações. Variantes regularizadas não foram testadas e
  não devem ser inferidas destes resultados.

---

## 7. E3: triagem só por configuração (2026-11-23)

Pré-registro: [PHASE0_PREREG.md](PHASE0_PREREG.md) §3. Resumo gerado por
`tool/experiments/phase0_e3_summary.dart`:
[SUMMARY_E3.md](../results_phase0/SUMMARY_E3.md). Dados:
`experiments/results_phase0/<b>/e3/<célula>/run_*.json`, `MANIFEST.jsonl`
(hash do binário e da configuração por célula). Script:
`experiments/phase0/run_e3.sh`, sem alteração.

**Só validação.** As execuções usam divisão explícita sem segmento de teste
(`testStartRow` = `valEndRow`), então não existe métrica de teste nelas.

### 7.1 Integridade

- **240 de 240 execuções** completas: 3 benchmarks × 8 células × sementes
  21–30, todas com 10/10.
- Binário congelado `cpp/build/aegis_batch.exe` (1.1.0), configuração
  `aegis_full.json`, orçamento do estudo (mediana de avaliações: ≈ 3,0×10⁵
  no CT, ≈ 1,5×10⁵ no WH e no SB).
- **Divergências na validação:** 2 execuções, ambas no CT
  `mr39_zero_one_step`. Nenhuma nas demais 23 células.
- **Máquina:** todo o E3 rodou na segunda máquina (Ryzen 5 PRO 5650G,
  6C/12T), diferente da que gerou o protocolo 1.1.0 e o E1/E2. A reprodução
  bit a bit entre as máquinas foi conferida antes (EXPERIMENT_LOG,
  2026-11-21). Os tempos de parede do E3 não são comparáveis aos do estudo.
- Execução com até 6 em paralelo, prioridade BelowNormal.

### 7.2 Critério pré-registrado

Comparação: penalidades zeradas com teto 39 contra o padrão com teto 8, no
mesmo `errorMode`. Critério: razão das medianas ≤ 0,90 em pelo menos 2 de 3
benchmarks.

| `errorMode` | CT (V) | WH (mV) | SB (mV) | Resultado |
|---|---|---|---|---|
| `one_step` | 0,938 → 1,146 = **1,22** ✗ | 50,8 → 28,2 = **0,56** ✓ | 3,34 → 0,41 = **0,12** ✓ | **2 de 3: atingido** |
| `simulation` | 0,947 → 0,494 = **0,52** ✓ | 38,9 → 10,7 = **0,28** ✓ | 2,59 → 0,34 = **0,13** ✓ | **3 de 3: atingido** |

**Consequência pré-registrada:** decompor a pressão de parcimônia antes de
qualquer conclusão causal.

### 7.3 O que os dados mostram (descritivo)

1. **O teto de regressores não é a restrição ativa com as penalidades
   padrão.** Com o teto 39 e penalidades padrão, os campeões ficam com
   K mediano de 4 a 7, como com o teto 8, e o RMSE muda pouco (CT
   0,862 contra 0,938 V; WH 50,8 contra 50,8 mV; SB 3,34 contra 3,34 mV, em
   `one_step`). Quem limita o tamanho são as penalidades.
2. **Sem penalidades, o AEGIS chega por conta própria às estruturas de
   20–40 termos do E1, e supera o ajuste por QR delas no WH e no SB.** Com
   teto 39 e
   penalidades zeradas, K mediano 22–33. Na validação, em `simulation`:
   - WH: 10,7 mV, contra 26,5 mV do PN_K40 (QR) e 26,1 mV com LM no E1;
   - SB: 0,34 mV, contra 0,60 mV do PN_K40 (QR); o PN_K40 com LM no E1
     (0,27 mV) continua melhor;
   - CT: 0,494 V, contra 0,848 V dos campeões 1.1.0 e 1,013 V do PN_K40.
   Os números do E1 e do E3 usam a mesma divisão e a mesma métrica.
3. **O CT se comporta diferente do E1.** No E1, mais capacidade piorava o
   CT. No E3 piora em `one_step` (1,146 V, 2 divergências) e melhora muito
   em `simulation` (0,494 V). Com o teto 8 sem penalidades o CT já chega a
   0,505 V em `simulation`: **no CT, as penalidades explicam quase todo o
   ganho**, não o teto.
4. **No WH e no SB, as duas mudanças contam.** Sem penalidades e com teto 8:
   WH 32,5 mV, SB 0,84 mV (`simulation`). Com teto 39: 10,7 e 0,34 mV.
5. **O `errorMode` `simulation` é melhor em 11 das 12
   comparações de pares de célula** (mesmo teto e mesmas penalidades). A
   exceção é o CT com teto 8 e penalidades padrão (0,938 → 0,947 V). A
   maior diferença é no WH com teto 39 sem penalidades (28,2 → 10,7 mV) e no
   CT (1,146 → 0,494 V).
6. **Composição dos campeões (só `report.model`):**
   - penalidades padrão: predominam expoentes inteiros (no WH em
     `one_step`, só inteiros), e não há nenhum termo de
     denominador em nenhuma das 120 execuções;
   - penalidades zeradas, teto 39: 32 % (SB) a 50 % (CT) dos fatores com
     expoente não inteiro (sempre múltiplo de 0,5), e 61–116 fatores de
     denominador por célula de 10 execuções;
   - ou seja, **quando a pressão é retirada, a busca usa os expoentes reais
     e a forma racional extensivamente.** É descritivo: não mostra que eles
     causam o ganho.
7. **Custo:** as células com teto 39 sem penalidades levam ≈ 20–40× o tempo
   de parede da célula padrão com teto 8 (CT 874 contra 45 s; WH 24 752
   contra 743 s; SB 25 746 contra 615 s por execução,
   mediana, `simulation`). O orçamento em avaliações é o mesmo; o custo por
   avaliação cresce com K (documento 10 §3).

### 7.4 O que os dados não mostram

- **Atribuição causal.** "Penalidades zeradas" é um pacote: γ, δ, β, α e o
  recozimento de γ vão a zero juntos. Os pisos de ζ do currículo
  (1,5 / 0,8 / 1,0 / 1,0), o θ da ilha free-run (≥ 0,15) e η = 1 continuam
  ativos. O E3 não diz qual penalidade importa.
- **Desempenho no teste.** Nenhum dado de teste foi lido. A validação do CT
  tem 205 amostras e uma única divisão.
- **Generalização a outras sementes ou divisões.** Uma divisão por
  benchmark; 10 sementes por célula.
- **Interpretabilidade.** Modelos de 30 termos com denominador não foram
  avaliados quanto à leitura física.

### 7.5 Limitações e desvios

- **Discrepância de documento, não de execução:** o parecer 07 §10.4
  descreve as células padrão do E3 com `gammaAnnealStart` =
  `gammaAnnealEnd`. O pré-registro §3, que governa, mantém os valores do
  `aegis_full` (0,01 → 0,1) nas células padrão e zera ambos nas células
  sem penalidades. O script seguiu o pré-registro.
- **Recozimento de γ efetivamente inativo:** o recozimento usa
  geração/`maxGenerations` com `maxGenerations` = 100 000, e as execuções
  param pelo orçamento de avaliações muito antes. Nas células padrão, γ
  fica perto do valor inicial.
- **Máquina diferente da do estudo 1.1.0 e do E1/E2** (§7.1).
- O tempo de parede foi medido com a máquina compartilhada; serve só como
  ordem de grandeza.

### 7.6 Consequência para o A1

Pelo pré-registro, o próximo passo é **decompor a pressão de parcimônia**
(qual das penalidades limita o tamanho) antes de qualquer conclusão causal.
O E3 também indica:
- o `errorMode` `simulation` como candidato a padrão (a decidir no A1);
- o custo por avaliação em modelos grandes como gargalo prático
  (documentos 10 a 12).

A direção do A1, a abertura do teste WH/SB e a escolha do padrão são
decisões do usuário.
