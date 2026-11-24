# 13 — P0: onde o tempo é gasto, e a escolha entre P1, P2′ e P6

Data: 2026-11-24. Etapa P0 da ordem de [10 §11.4](10_AUDITORIA_DO_09.md) e
[12 §6](12_AUDITORIA_DO_11.md). Autorizada pelo usuário em 2026-11-23.

Etiquetas: **[medido]** sai dos arquivos deste P0; **[inferência]** é
estimativa a confirmar; **[recomendação]**.

---

## 1. Como foi medido

- **Build:** código 1.1.0 sem alteração numérica, mais 9 marcadores de tempo
  em `IndividualEvaluator::evaluate`, ativados só com `-DAEGIS_PROFILE`
  (`experiments/perf/p0_probe.patch`). Foi compilado num git worktree
  separado, com o g++ 16.1 do MSYS2 desta máquina. `cpp/build` e
  `cpp/build_phase0` não foram tocados.
- **Conferências antes de medir:**
  - `core_tests` 91/0, `api_tests` 66/0, `phase0_tests` 11/0;
  - a execução de referência (CT `aegis_full`, semente 1) com o build base
    e com o build instrumentado deu `report.model`, `report.evaluations` e
    `report.metrics.validation` **idênticos bit a bit** aos do binário
    congelado (g++ 16.2);
  - custo da instrumentação: 24,5 s contra 23,9 s (≈ 2 %).
- **Execuções:** script `experiments/perf/run_p0.sh`, com a divisão e os
  overrides do E3, semente 21, sem arquivo de teste, uma execução por
  processo, 6 em paralelo, BelowNormal.
  - CT: células `mr8_default_simulation`, `mr39_zero_simulation` e
    `mr39_zero_one_step`, com orçamento completo (3×10⁵ avaliações).
  - WH: as mesmas três células com **3×10⁴ avaliações** (1/5 do orçamento).
    **Desvio:** isso cobre só o início da busca.
- **Análise:** `tool/experiments/p0_profile.dart`. Lê só tempos, contagens
  de estrutura e `wallSeconds`, nenhuma métrica. Saídas em
  `experiments/results_perf/` (fora do git).
- **Etapas medidas:**

| Etapa | Conteúdo |
|---|---|
| psi | montar Ψ de treino (potências e produtos) |
| fit | pseudo-linearização e QR de Householder |
| pred | predição de um passo no treino |
| err | ERR completo (`chrom.err`), **não usado no fitness** (10 §3.3) |
| ratio | ERR por grupo (razão de entrada, usada no fitness) |
| val | Ψ de validação e predição de um passo |
| sim | métricas e simulação livre |
| rest | estabilidade, correlação resíduo–entrada, montagem do fitness |

## 2. Resultados [medido]

### 2.1 Tempo dentro e fora do avaliador

| Execução | K mediano | Tempo de parede | Fora de `evaluate()` |
|---|---|---|---|
| CT, padrão, teto 8, `simulation` | 4 | 48,5 s | 8,0 % |
| CT, sem penalidades, teto 39, `simulation` | 30 | 936 s | 3,2 % |
| CT, sem penalidades, teto 39, `one_step` | 30 | 937 s | 3,0 % |
| WH, padrão, teto 8, `simulation` (3×10⁴) | 6 | 157 s | 0,5 % |
| WH, sem penalidades, teto 39, `simulation` (3×10⁴) | 34 | 2 628 s | 0,5 % |
| WH, sem penalidades, teto 39, `one_step` (3×10⁴) | 32 | 2 497 s | 0,5 % |

O DE, a migração, os diagnósticos e a escrita custam 0,5–8 % do tempo.
**Todo o ganho possível está dentro da avaliação.**

### 2.2 Partes da avaliação, candidatos com K entre 31 e 40

| Execução | psi | fit | err | ratio | val | sim | outros |
|---|---|---|---|---|---|---|---|
| CT, sem pen., `simulation` | 18,3 % | 26,4 % | 27,5 % | 23,2 % | 2,0 % | 1,8 % | 0,9 % |
| CT, sem pen., `one_step` | 19,2 % | 26,2 % | 27,0 % | 23,0 % | 2,1 % | 1,6 % | 0,9 % |
| WH, sem pen., `simulation` | 15,1 % | 34,7 % | 25,3 % | 21,9 % | 1,5 % | 0,7 % | 0,8 % |
| WH, sem pen., `one_step` | 15,3 % | 35,3 % | 25,3 % | 21,5 % | 1,5 % | 0,1 % | 0,9 % |

- **Ajuste e ERR (fit + err + ratio) somam 77–82 %.** Com a montagem de Ψ,
  chegam a 95–97 %.
- **A simulação livre custa 0,1–1,8 %**, mesmo no modo `simulation`, que
  simula a validação inteira. Isso confirma a conclusão do 10 §3: acelerar
  a simulação (realização em estados, P3′) não muda o tempo total hoje.
- **O ERR completo, que não entra no fitness, custa sozinho 25–27 %.**
- **Custo por candidato no WH:** ≈ 3,8 ms com K ≤ 5, 33 ms com K entre 11 e
  20, 64–66 ms com K entre 21 e 30, e 93–95 ms com K entre 31 e 40. Cresce
  aproximadamente com K² (10 §3.1).
- Nos modelos pequenos (padrão, K ≈ 4–6), a divisão é parecida: fit 32–38 %,
  err + ratio 34–35 %, psi 18 %.

### 2.3 Composição dos candidatos

- **Sem penalidades:** 99,7–99,9 % dos candidatos têm denominador, e 51–53 %
  dos fatores têm expoente não inteiro.
- **Padrão:** 4–6 % dos candidatos têm denominador, e 18–29 % dos fatores
  têm expoente não inteiro.
- Portanto, nos modelos grandes, os pares N·D e D·D (dois índices de
  atraso, 10 §11.1) são a regra.

### 2.4 Cache de estatísticas deslocáveis (P2′b), simulado

Cache sem limite de memória, acerto contado por chave (forma, atrasos).

| Execução | Acerto, 1 atraso (NN, Ny, Dy) | Acerto, 2 atrasos (ND, DD) | Chaves distintas |
|---|---|---|---|
| CT, sem pen., `simulation` | 64 % | 37 % | 71 milhões |
| CT, sem pen., `one_step` | 64 % | 32 % | 72 milhões |
| WH, sem pen., `simulation` (1/5 do orçamento) | 68 % | 37 % | 7,8 milhões |
| WH, sem pen., `one_step` (1/5 do orçamento) | 64 % | 34 % | 8,1 milhões |
| CT, padrão | 96 % | 18 % | 0,26 milhão |
| WH, padrão (1/5) | 96 % | 14 % | 0,05 milhão |

- Nos modelos grandes, o acerto global fica em ≈ 50–60 %. Cresce ao longo da
  execução (WH: de 31–33 % no primeiro décimo para 66–70 % no último).
- **Memória:** 71–72 milhões de chaves no CT, cada uma com um valor e um
  identificador, dão vários GB. Esta máquina tem 7,4 GB.

## 3. Análise: P1, P2′ e P6

### 3.1 P1, otimizações exatas

Três mudanças que não alteram nenhum número (10 §3.3):

| Mudança | Parte atacada | Ganho estimado no total (K = 31–40) |
|---|---|---|
| ERR completo só para o campeão e o relatório | err, 25–27 % | **−25 a −27 %, certo** [medido] |
| Cache das 12 séries de fator (sem `pow` na montagem de Ψ) | psi, 15–19 % | −7 a −12 % [inferência] |
| QR percorrendo a matriz por linhas | fit, 26–35 % | −9 a −23 % [inferência] |

- **Ganho total estimado: ≈ 1,8–2,3× mais rápido** [inferência]. O primeiro
  item sozinho dá **≈ 1,35×** com certeza, porque é tempo medido que deixa
  de existir.
- **Risco: nenhum.** A validação é reprodução bit a bit das execuções
  existentes, como foi feito neste P0.
- **Esforço: pequeno.** São alterações locais no avaliador, no QR e na
  montagem de Ψ.

### 3.2 P2′, ajuste por estatísticas reutilizáveis

**P2′a (Gram + Cholesky + ERR em K×K, sem cache):**
- Substitui fit e ratio, hoje 50–57 % do tempo. O Gram custa
  ≈ ½·N·K² operações com acesso sequencial. O QR custa ≈ 2·N·K² com acesso
  por colunas, e o ERR por grupo, ≈ 4·N·K².
- **Ganho estimado, somado ao P1: ≈ 4–6× sobre o atual** [inferência].
- **Risco: médio.**
  - Os resultados mudam no último dígito e a busca diverge por caos.
  - A validação é estatística: θ, posto, SSE e fitness por candidato
    dentro de tolerância, mais qualidade × tempo com sementes pareadas.
  - É preciso um *fallback* para o Householder em candidatos mal
    condicionados. Com 52 % de expoentes não inteiros e colunas −y·φ, eles
    vão existir. A frequência é desconhecida.
- **Esforço: médio.**

**P2′b (cache de estatísticas deslocáveis):** **[recomendação] não fazer.**
- Acerto de só 50–60 % nos modelos grandes, onde o custo está.
- Cada falta custa O(N), o mesmo que calcular a entrada do Gram.
- Depois do P2′a, o Gram restante seria ≈ 5–10 % do tempo atual. Com metade
  de acerto, o ganho ficaria em ≈ 3–5 % do total.
- Exige vários GB de memória.
- Era a hipótese de "O(N·K)" da §10.2 do documento 10: os dados a
  refutam para o AEGIS racional. A revisão externa estava certa em exigir
  essa medição.

### 3.3 P6, refino por simulação (Passada B)

- **Não é velocidade, é qualidade.** Ataca o desalinhamento entre ajuste de
  um passo e uso em simulação, que o E3 mostrou ser grande (WH 28,2 → 10,7
  mV só por mudar o critério da busca).
- **Custo baixo onde seria usado:** a simulação custa ≤ 2 % por avaliação.
  Refinar só o campeão com sensibilidades diretas (P ≈ 35 parâmetros,
  ≈ 20 iterações) custa da ordem de segundos por execução [inferência],
  desprezível diante de horas.
- **Risco: alto na qualidade, se feito sem proteção.** O E2 mostrou que o
  LM por simulação sem veto ajuda no SB (−52 %), é neutro no WH e piora o CT,
  com divergências. O P6 precisa antes do **veto de admissibilidade** (M9
  do parecer 07) e de um critério de parada na validação.
- **Esforço: médio.** Parte do `LocalRefiner` existente.
- Mexe numa parte do código diferente de P1 e P2′a.

### 3.4 Comparação

| | P1 | P2′a | P2′b | P6 |
|---|---|---|---|---|
| O que ganha | velocidade | velocidade | velocidade | qualidade |
| Ganho estimado | 1,8–2,3× (1,35× certo) | 4–6× com P1 | ≈ 3–5 % a mais | a medir (E2: −52 % a +5 %) |
| Muda resultados? | não (bit a bit) | sim, no último dígito | sim | sim, por desenho |
| Validação | reprodução | estatística, sementes pareadas | — | pré-registro, validação |
| Pré-requisito | nenhum | P1 | P2′a | veto de admissibilidade |
| Esforço | pequeno | médio | grande | médio |

## 4. Recomendação

1. **P1 primeiro.** Ganho certo, sem risco, e a validação já está montada.
   Também reduz o custo de todos os experimentos seguintes, inclusive os do
   A1: as células grandes do E3 levaram 7 h por execução no WH.
2. **P2′a em seguida,** com estudo de concordância por candidato antes de
   qualquer execução completa.
3. **P2′b fora da lista,** pelos dados da §2.4.
4. **P6 em paralelo, como trilho de qualidade,** depois do veto de
   admissibilidade. É decisão do A1 e precisa de pré-registro.
5. **P3′ (simulação em estados)** continua sem justificativa de velocidade
   (§2.2). Os estados por regressor seguem úteis para interpretação e para
   o P6, não para o tempo.

**Expoentes reais:** nenhuma das etapas recomendadas toca na representação.
P1 e P2′a mudam só como as contas são feitas. O cache de fatores do P1 vale
para qualquer expoente da grade de 0,5.
