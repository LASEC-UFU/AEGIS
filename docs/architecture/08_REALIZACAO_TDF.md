# 08 — Realização em estados no estilo TDF-II dos modelos NARX do AEGIS

> **Nota de 2026-11-23, depois da auditoria [10_AUDITORIA_DO_09.md](10_AUDITORIA_DO_09.md):**
> - O usuário **não tem interesse em embarcar o código**; o objetivo é
>   velocidade e arquitetura, com expoentes reais.
> - Os tempos do E3 indicam que o gargalo nos modelos grandes é o ajuste e o
>   ERR (O(N·K²)), não a simulação.
> - A realização deste documento passa a ser a **etapa 2** (simulação livre),
>   depois da "TDF-II do ajuste" (10 §10.2). As seções de ponto fixo e
>   implantação (§7–§8) ficam como referência, sem prioridade.
> - O R4 deve ter três braços (10 §8).

Data: 2026-11-23. Situação: **proposta para revisão independente**. Nada
aqui foi implementado nem executado. O usuário pediu que outro agente
analise esta proposta com rigor; a §13 lista os pontos que o autor considera
mais frágeis e pede verificação explícita.

Origem: conversa com o usuário durante o E3 da Fase 0. O usuário quer manter
os **expoentes reais** (o diferencial do AEGIS) e avaliar contas em **ponto
fixo**, com inteiros de 16 bits para operar e 32 bits para acumular, numa
forma inspirada na *Transposed Direct Form II* (TDF-II) dos filtros IIR.

Convenções deste documento:

- **[código]** = fato conferido no código da árvore de trabalho
  (`audit/aegis-1.1.0-wip`, núcleo 1.1.0 congelado), com arquivo e linha.
- **[dado]** = fato conferido nos arquivos de resultados, lendo apenas
  `report.model` (permitido pelo pré-registro da Fase 0 §0); nenhum dado de
  teste de WH ou SB foi lido.
- **[hipótese]** = afirmação não verificada, a ser testada pelo plano da §11.
- **[decisão]** = escolha de projeto que o revisor pode contestar.

---

## 1. Resumo

1. Cada modelo do AEGIS é reescrito como um **anel de acumuladores de saídas
   futuras** (os estados), alimentado por **características não lineares**
   calculadas uma vez por amostra. Para modelos cujos termos têm um só
   fator, a realização é exatamente uma TDF-II sobre características. Termos
   com produto de fatores em atrasos diferentes exigem um histórico curto
   (forma híbrida DF-I/TDF-II).
2. A grade de expoentes atual (passo 0,5, de 0,5 a 3) se reduz a
   **uma raiz quadrada por variável e por amostra**, mais multiplicações.
   Expoentes contínuos se reduzem a log₂/exp₂ tabelados. Os expoentes reais
   são preservados.
3. Em ponto fixo: sinais e características em int16, coeficientes em int16
   com expoente por termo, **estados (acumuladores) em int32**. O limite de
   pior caso do acumulador é calculável antes de executar, porque os sinais
   são saturados. Cada slot recebe exatamente uma contribuição de cada termo,
   isto é, dezenas de produtos, e não os 16 000 de um produto interno de
   mínimos quadrados.
4. **O ajuste dos coeficientes continua em double (QR).** A proposta trata
   de *simular* e *executar* modelos, não de estimá-los.
5. Usos: (a) núcleo de simulação livre alternativo; (b) veto ou critério
   opcional de implantabilidade; (c) exportação para C sem ponto flutuante.
6. Plano R0–R4 (§11), só com validação, sem alterar o motor congelado,
   com critérios fixados antes de executar.

---

## 2. O modelo, exatamente como o núcleo o calcula

### 2.1 Forma

[código] `RationalModel::num_den_at` (`cpp/src/rational_model.cpp:81`):

```
num = c + Σ_{j ∈ N} θ_j · φ_j(k)
den = 1 + Σ_{j ∈ D} θ_j · φ_j(k)
ŷ(k) = num / den
```

- O intercepto c fica **no numerador**.
- Um regressor pertence ao denominador se **qualquer** de seus fatores tiver
  `isDenominator = true` [código] (`cpp/include/aegis/regressor_library.hpp:32`).
- Guarda do denominador: se |den| < `kMinDenominator` = 1e−12, den recebe
  ±1e−12 com o mesmo sinal [código] (`rational_model.hpp:113`,
  `rational_model.cpp:142`).

### 2.2 Regressores

[código] `Regressor::evaluate` (`cpp/src/regressor_library.cpp:37`):

```
φ_j(k) = Π_{f ∈ j} g_{p_f}( x_{v_f}(k − d_f) )
```

- Variáveis: coluna 0 = u, coluna 1 = y nos benchmarks (`outputCol` = 1).
- Até `maxTermsPerReg` = 3 fatores por regressor (configuração do estudo).
- **Atrasos d ≥ 1 sempre** [código]: geração em `de_optimizer.cpp:105`
  (`uniform_int_distribution(1, maxDelay)`) e reparos em `:142` e `:264`
  (`std::max(1, …)`). Nenhum termo usa o instante atual, então o modelo é
  estritamente causal e **não há laço algébrico**.

### 2.3 Base de potências

[código] `power_basis`, modo `hybrid` (`cpp/include/aegis/safe_power.hpp`):

| Expoente p | g_p(x) | Implementação atual |
|---|---|---|
| p = 1 | x | retorno direto |
| p inteiro n | xⁿ (potências pares são funções pares) | `int_power`, por quadrados sucessivos, sem `pow` |
| p não inteiro | sign(x)·\|x\|^p | `std::pow(|x|, p)` |

- Modo `signed`: sign(x)·|x|^p para todo p; x² vira x·|x|.
- Modo `legacy` (código original 9e4b1d8): sign(x)·(|x| + 1e−6)^p.
  **Fora do escopo desta proposta** (§10).
- Grade do estudo: `pmin` = 0,5, `pmax` = 3, `exponentStep` = 0,5. Os
  expoentes possíveis são {0,5; 1; 1,5; 2; 2,5; 3}.

### 2.4 Simulação livre atual (forma direta)

[código] `RationalModel::simulate` (`cpp/src/rational_model.cpp:117`):

1. Copia `md + n` linhas × `cols` dos dados num buffer mutável (`:129`), em
   que `md` é o maior atraso do modelo e `n` o horizonte.
2. Para cada k ≥ md:
   - calcula num e den percorrendo todos os regressores e fatores, lendo o
     buffer;
   - escreve ŷ(k) na coluna de saída do buffer, de modo que os atrasos
     seguintes leem a previsão.
3. Linhas k < md mantêm o **y medido** (condição inicial).
4. **Divergência:** se ŷ não é finito ou |ŷ| > `bound`:
   - marca `diverged` e o passo;
   - satura ŷ em ±bound;
   - daí em diante **repete o último valor** (`:136–137`).
5. `bound` = `kDivergenceFactor` × max|y_treino| = 10 × max|y_treino|
   [código] (`individual_evaluator.hpp:135`, `individual_evaluator.cpp:301`).
   Com normalização min–max ajustada no treino, max|y_treino| ≈ 1 e o
   limite fica em ≈ 10 em unidades normalizadas.

### 2.5 Onde a simulação entra no custo da busca

[código] `IndividualEvaluator::evaluate` (`cpp/src/individual_evaluator.cpp:355–380`):

- Cada avaliação de candidato simula no segmento de validação da ilha
  (`val_data`), ou no treino se não houver validação.
- Horizonte:
  - em `one_step`, `skip + freeRunHorizon` = 50 amostras;
  - em `simulation` (`error_mode == 1`) ou com `freeRunHorizon ≤ 0`,
    **o segmento inteiro**.
- O diagnóstico do campeão (`:471`) e as métricas finais (`model_io.cpp:120`)
  também simulam o segmento inteiro.

Consequência: no modo `simulation`, o que deu os melhores resultados no E3,
toda avaliação simula o segmento de validação inteiro.

---

## 3. A ideia: de "buscar o passado" para "empurrar para o futuro"

### 3.1 A analogia com a TDF-II

A TDF-II de um IIR de ordem N guarda N estados:

```
y(n)   = b0·x(n) + s1(n−1)
s_i(n) = b_i·x(n) − a_i·y(n) + s_{i+1}(n−1)
s_N(n) = b_N·x(n) − a_N·y(n)
```

Cada estado é uma **soma parcial de uma saída futura**. Quando x(n) e y(n)
ficam conhecidos, suas contribuições são multiplicadas e somadas aos estados
que viram saídas mais adiante. Calcular a saída é só ler um estado.

### 3.2 Generalização para termos NARX

Para cada regressor j:

- **atraso de disparo** m_j = min_f d_f: no instante t = k − m_j, todos os
  fatores do termo já são conhecidos;
- **atrasos relativos** r_f = d_f − m_j ≥ 0.

O termo vira uma característica calculada no instante t e agendada m_j
passos à frente:

```
z_j(t) = Π_f g_{p_f}( x_{v_f}(t − r_f) )
acc_B[t + m_j] += θ_j · z_j(t)        (B = N ou D, conforme o banco do termo)
```

e a saída no instante k é

```
ŷ(k) = (c + accN[k]) / (1 + accD[k])
```

Equivalência algébrica: φ_j(k) = z_j(k − m_j), porque k − d_f =
(k − m_j) − r_f. Logo accN[k] acumula exatamente Σ θ_j φ_j(k), a menos da
ordem das somas em ponto flutuante.

### 3.3 Propriedade-chave

- **Termos univariados** (um fator): r = 0. Não há nenhuma linha de atraso
  de sinal; só o anel de acumuladores. É uma TDF-II pura sobre
  características não lineares.
- **Termos cruzados** (fatores com atrasos diferentes, por exemplo
  y(k−2)·u(k−7)): precisam do histórico do fator mais antigo por r_f
  amostras. Esse é o trecho DF-I da forma híbrida.

### 3.4 Atraso longo esparso custa O(1)

Os acumuladores ficam num **anel** de comprimento L = max_j m_j + 1, com
ponteiro rotativo. Não há deslocamento físico de estados. Em hardware, a
TDF-II clássica encadeia somadores; em software, o anel substitui isso.

### 3.5 Exemplo real: campeão CT `aegis_full`, semente 1

[dado] (unidades normalizadas):

```
ŷ(k) = 0,014172 + 0,995462·y(k−1) − 0,009485·y(k−30) + 0,046010·u(k−5)
```

Realização: anel de 30 acumuladores, nenhum histórico de sinal, 3 MACs e
1 leitura por amostra.

```
a cada instante t:
  acc[t+5]  += 0,046010 · u(t)      // disparo por u (m = 5)
  ŷ(t)       = acc[t]               // o intercepto foi pré-carregado no slot
  acc[t+1]  += 0,995462 · ŷ(t)      // disparo por y (m = 1)
  acc[t+30] += −0,009485 · ŷ(t)     // disparo por y (m = 30)
  acc[t]     = 0,014172             // o slot volta como t+30, já com c
```

**Truque:** pré-carregar c no slot quando ele é liberado elimina uma soma por
amostra.

---

## 4. Compilação de um modelo em realização

**Entrada:** JSON do modelo (`report.model`: `powerMode`, `intercept`,
`coefficients`, `regressors[].terms[]{variable, delay, exponent, isDenominator}`).

### 4.1 Passos

1. **Validação:** `powerMode` ∈ {hybrid, signed}; caso contrário, recusar
   com motivo. Todos os atrasos ≥ 1 e número de coeficientes igual ao de
   regressores (mesma checagem do núcleo, `rational_model.cpp:125`).
2. **Normalização dos termos:** para cada regressor j, calcular m_j, os r_f
   e o banco B_j.
   - **Variável de disparo:** u se todos os fatores com atraso m_j forem de
     u; caso contrário, y.
   - Termo disparado por y só pode ser espalhado depois de ŷ(t) calculado.
     Termo disparado por u pode ser espalhado assim que u(t) chega.
3. **Características distintas:** o conjunto 𝒢 de pares (v, p) usados no
   modelo. Na grade atual, |𝒢| ≤ 2 variáveis × 6 expoentes = 12.
4. **Históricos de características:** para cada (v, p) usado com r > 0,
   guardar g_{v,p} das últimas H_{v,p} = max r amostras.
   - Guardar a característica, e não o sinal bruto, evita recalcular
     potências.
   - **[decisão]** O revisor pode preferir guardar o sinal bruto quando
     H for grande e os expoentes variados; o custo de memória é |𝒢|·H
     contra 2·H.
5. **Listas de espalhamento:** termos agrupados por (variável de disparo,
   banco, m_j). Cada entrada guarda θ_j (ou sua forma quantizada) e a
   receita do produto z_j: quais (v, p, r) multiplicar.
6. **Condição inicial (aquecimento):** a simulação do núcleo começa em
   k = md com o **y medido** nas linhas 0..md−1 (§2.4). Para reproduzir
   isso exatamente:
   - para t = 0..md−1, calcular as características de u(t) e do **y medido**
     em t;
   - atualizar os históricos;
   - espalhar só as contribuições cujo destino t + m_j ≥ md;
   - nenhuma saída é emitida.

   Os índices necessários existem: um termo com destino k ≥ md lê linhas
   k − d_f ≥ md − md = 0.

### 4.2 Passo por amostra, em regime

```
para t = md, md+1, …:
  1. Gu ← características de u(t)                  (|𝒢_u| avaliações)
  2. para cada termo disparado por u: acc_B[t+m] += θ·z
  3. ŷ(t) ← accN[t] / (1 + accD[t])                  (c já pré-carregado em accN)
       guarda |den| < 1e−12 → ±1e−12 (mesma semântica do núcleo)
       se não finito ou |ŷ| > bound → divergência (mesma semântica do núcleo)
  4. Gy ← características de ŷ(t)                  (|𝒢_y| avaliações)
  5. para cada termo disparado por y: acc_B[t+m] += θ·z
  6. atualizar históricos; liberar o slot t (accN ← c, accD ← 0)
```

### 4.3 Semântica de divergência

Para equivalência, depois da divergência a realização **repete o último
valor** e para de atualizar os acumuladores. Isso reproduz o
`yp = res.yhat[i−1]` do núcleo. O índice do passo de divergência deve ser
idêntico.

---

## 5. Custo por amostra

Notação: T = número de regressores; F = número total de fatores; F_nf =
fatores com expoente não inteiro; |𝒢| = pares (v, p) distintos.

| Operação | Forma direta atual [código] | Realização TDF |
|---|---|---|
| `pow` ou raiz | F_nf (uma por fator fracionário) | **≤ 1 √ por variável** na grade de 0,5 (§6) |
| Potência inteira | por fator, `int_power` | por par (v, p) distinto, uma vez |
| Multiplicações dentro do termo | F − T | F − T (mesmas, sobre características já prontas) |
| MAC de coeficiente | T | T |
| Leitura de memória | F leituras com passo `cols` no buffer | leituras no anel e nos históricos (contíguas) |
| Cópia de buffer | `(md + n)·cols` doubles por chamada | nenhuma; só u é lido |

**Números de referência** [dado], expoentes dos 10 modelos de cada
conjunto:

| Conjunto | Fatores/modelo | Fracionários/modelo |
|---|---|---|
| CT `aegis_full` | 3,0 | 0,1 |
| WH `aegis_full` | 5,2 | 0,1 |
| SB `aegis_full` | 5,8 | 1,0 |
| WH E3 `mr39_zero_simulation` | 50 | ~20 (197/500) |
| CT E3 `mr39_zero_simulation` | 37 | ~18 (183/368) |

**[hipótese] O ganho de velocidade da TDF é moderado e se concentra na
simulação livre.**

- Nos modelos grandes do E3, a forma direta faz ~20 `pow` por amostra; a
  TDF, ≤ 2 raízes.
- Mas o custo total de uma avaliação inclui montar Ψ no treino
  (16 000 linhas × F fatores, com os mesmos `pow`) e o QR (≈ N·K² com
  K ≈ 33). Esses dois termos podem dominar.
- **A TDF não acelera o QR nem a montagem de Ψ.** Para estes, as alavancas
  são cache de colunas e mínimos quadrados incrementais, que estão fora
  desta proposta.
- Só um *profiling* e o R4 dizem a fração real.
- O autor **não** afirma ganho de ordem de grandeza na busca.

---

## 6. Expoentes reais com custo fixo

### 6.1 Grade de 0,5

Seja s = √|x|. Então:

| p | g_p(x), modo hybrid | Operações a partir de x e s |
|---|---|---|
| 0,5 | sign(x)·s | 0 multiplicações |
| 1 | x | — |
| 1,5 | sign(x)·\|x\|·s = x·s | 1 |
| 2 | x·x | 1 |
| 2,5 | sign(x)·x²·s = x·\|x\|·s | 2 |
| 3 | x·x·x | 2 |

Conferência do 1,5: sign(x)·|x|^1,5 = sign(x)·|x|·√|x| = x·√|x|. Correto
para x < 0, porque sign(x)·|x| = x.

Conferência do 2,5: sign(x)·|x|^2,5 = sign(x)·x²·√|x|. Também vale
x·|x|·√|x|, já que sign(x)·x² = x·|x|.

**A grade inteira custa uma raiz por variável por amostra.** Em double, isso
troca `pow` por `sqrt`, que é exato com arredondamento correto pelo IEEE 754.
Atenção: `pow(|x|, 1,5)` e `|x|·sqrt(|x|)` podem diferir no último bit. O R1
usa tolerância, não igualdade bit a bit (§11).

### 6.2 Expoentes contínuos (modo `signed`, `exponentStep` = 0)

|x|^p = 2^(p·log₂|x|). Em ponto fixo, isso é uma tabela de log₂, uma
multiplicação por p quantizado e uma tabela de exp₂. Qualquer p real tem o
mesmo custo. A precisão depende das tabelas (§7.4).

### 6.3 Raiz em ponto fixo

Três opções, a escolher pelo R2:

- **(a) Tabela completa:** 65 536 entradas int16 indexadas pelo próprio
  x_int16, ou seja, 128 KB. Exata até o arredondamento da saída. Viável em
  PC e em microcontroladores com flash grande.
- **(b) Tabela segmentada:** ~256 entradas com interpolação linear e
  segmentos mais densos perto de zero, onde d√x/dx → ∞. Adequada a
  microcontroladores pequenos.
- **(c) Raiz inteira bit a bit:** 16 iterações de deslocamento e subtração,
  sem tabela.

---

## 7. Ponto fixo: 16 bits para operar, 32 para acumular

### 7.1 Formatos

Notação Qa.b: 1 bit de sinal, a bits inteiros, b bits fracionários,
1 + a + b = 16 (int16) ou 32 (int32).

| Grandeza | Formato proposto [decisão] | Comentário |
|---|---|---|
| u, ŷ | int16 **Q2.13** (faixa [−4, 4), passo 2⁻¹³ ≈ 1,22×10⁻⁴); alternativa **Q3.12** (±8, 2,44×10⁻⁴) | Dados normalizados em [−1, 1] no treino; a margem acomoda excursões da validação. **Q2.13 não representa o limite de divergência do núcleo (≈ 10)**: a saturação em ±4 passa a ser um evento próprio, contado. Representar ±10 exige Q4.11 (passo 4,9×10⁻⁴) |
| Características g, z | int16 no mesmo formato dos sinais, ou formato próprio por (v, p) | x³ com \|x\| ≤ 4 chega a 64: **não cabe em Q2.13**. É preciso formato por característica ou saturação contada. Ver §7.3 |
| Coeficientes θ | mantissa int16 normalizada m (2¹⁴ ≤ \|m\| < 2¹⁵) e expoente e_j por termo: θ_j ≈ m_j·2^(−e_j) | Erro relativo ≤ 2⁻¹⁵ ≈ 3×10⁻⁵ em todo coeficiente, inclusive nos pequenos (0,0095 e 0,995 no mesmo modelo, §3.5) |
| Acumuladores (estados) | **int32** com F_acc bits fracionários | Nunca int16 (§9.1) |
| Intercepto c | pré-carregado no formato do acumulador | — |

### 7.2 Aritmética do MAC

- Produto: m_j (int16) × z (int16, F_z bits fracionários) cabe em int32 (|·| ≤ 2³⁰), com escala 2^−(e_j + F_z).
- Alinhamento ao acumulador: deslocamento à direita, com arredondamento, de
  s_j = e_j + F_z − F_acc bits. É preciso s_j ≥ 0. Coeficientes grandes
  (e_j pequeno) podem exigir s_j < 0, um deslocamento à esquerda com risco
  de estouro, coberto pela análise da §7.3.
- Erro de alinhamento por termo: ≤ 2^−(F_acc+1). Com T termos, o erro
  acumulado é ≤ T·2^−(F_acc+1).
- **Requisito:** F_acc ≥ F_y + ⌈log₂ T⌉ + 2, para que esse erro fique abaixo
  da requantização de ŷ.

### 7.3 Limite de estouro (pior caso)

Como **cada slot recebe exatamente uma contribuição de cada termo do seu
banco** (uma por instante de disparo), o limite é o mesmo para todos os
slots:

```
B_N = |c| + Σ_{j ∈ N} |θ_j| · Zmax_j
B_D = 1   + Σ_{j ∈ D} |θ_j| · Zmax_j
Zmax_j = Π_f Gmax(v_f, p_f),   Gmax(v, p) = máximo de |g_p| na faixa representável de v
```

- **Por que isso prova a ausência de estouro, e não só estima:** os sinais
  são saturados no formato (por exemplo ±4 em Q2.13), então
  Gmax(v, p) = 4^p é um limite **garantido**. Bits inteiros necessários no
  acumulador: G = ⌈log₂ B⌉ + 1, e F_acc = 31 − G.
- **Somas parciais:** se o valor final cabe, os estouros intermediários se
  cancelam na aritmética de complemento de dois, que é modular. Isso só
  vale **sem saturação no acumulador**. A ordem das somas não importa se o
  acumulador não satura.
- **Conservadorismo:** com |x| ≤ 4 e p = 3, Gmax = 64. O limite garantido
  pode ser muito pessimista e consumir bits fracionários.
- **[decisão]** Relatar dois limites:
  - (i) **garantido**, pela faixa do formato;
  - (ii) **empírico**, pela faixa observada no treino × margem 2.

  O compilador escolhe F_acc pelo garantido se F_acc ≥ requisito da §7.2.
  Caso contrário, registra a escolha (int64 ou limite empírico) e a
  realização deixa de ter garantia formal.

### 7.4 Pontos de arredondamento (lista completa)

A resposta no chat dizia "uma única requantização por amostra". **Isso só
vale para o caminho de acumulação.** A lista completa:

1. **Entrada:** u medido → int16. Uma vez por amostra.
2. **Características:** a tabela √ (ou log₂/exp₂) arredonda a saída. Cada
   multiplicação dentro de x·s, x·x, x·x·x e dos produtos entre fatores é
   int16 × int16 → int32 → int16, com arredondamento. São até ~3 pontos por
   característica e mais 1 por fator extra no termo.
3. **Alinhamento** do produto θ·z ao acumulador (§7.2).
4. **Saída:** acc → ŷ int16 (arredondamento para o mais próximo, com
   saturação). **Este é o único arredondamento dentro da realimentação
   linear**; os do item 2 entram pela parte não linear.
5. **Divisão** (modelos racionais): recíproco tabelado mais uma iteração de
   Newton–Raphson, ou divisão inteira int32/int32. Arredondamento próprio.

Consequência: a previsão de ruído do R3 (§11) precisa modelar fontes em 2,
4 e 5, não só em 4.

### 7.5 Pontos sensíveis

- **√ perto de zero:** derivada infinita. Um erro de quantização em x
  pequeno vira erro grande em √|x|. Afeta os expoentes 0,5, comuns nos
  modelos do E3 (80 fatores com p = 0,5 em 368 no CT; 78 em 500 no WH)
  [dado].
- **Polos perto de 1:** o coeficiente de y(k−1) no CT é 0,995462, e o polo
  dominante da parte AR linear é 0,9766 (parecer 07 §10.1). Erro relativo
  de 3×10⁻⁵ no coeficiente desloca o polo pouco, mas o erro de saída é
  amplificado por ~1/(1 − ρ) ≈ 43 na realimentação. **[hipótese]** O efeito
  é aceitável em Q2.13; o R2 mede.
- **Divisão nos racionais:** perto de |den| pequeno, a divisão amplifica o
  erro. Os modelos grandes do E3 têm muitos fatores no denominador (116 em
  368 no CT; 85 em 500 no WH) [dado]. **[hipótese]** São os mais frágeis
  em ponto fixo.

---

## 8. Usos no AEGIS

1. **Núcleo de simulação livre (double).** Substituir `RationalModel::simulate`
   por uma realização compilada, depois de aprovada no R1 e só no A1, nunca
   no núcleo congelado. Ganho esperado: moderado (§5).
2. **Implantabilidade (opcional).** Simular candidatos a campeão na
   realização quantizada, na validação:
   - como **veto**: estouro, saturação de ŷ ou divergência nova;
   - ou como objetivo secundário.

   Liga-se ao veto de admissibilidade do parecer 07 (§9.5, §10.3), que
   atua na promoção e na troca do campeão.
3. **Exportação.** Modelo → C99 sem ponto flutuante:
   - cabeçalho com mantissas, expoentes, deslocamentos e tabela √;
   - anel de acumuladores;
   - vetores de teste gerados pela simulação em double, para verificação
     no alvo.

   HDL para FPGA, se fizer sentido, fica para depois.
4. **Artigo.** Afirmação possível, **se** o R2 for favorável: modelos NARX
   interpretáveis com expoentes reais, identificados em double, implantáveis
   em 16 bits com ausência de estouro demonstrada. Sem o R2, isso não pode
   ser afirmado.

---

## 9. Riscos e alternativas

### 9.1 TDF-II em ponto fixo tem fama ruim, com razão

Na literatura clássica de filtros digitais, a TDF-II em ponto fixo exige
estados com a largura do acumulador. Com estados no tamanho da palavra
(16 bits) ela é pior que a DF-I, que usa um único acumulador largo e
requantiza só a saída. Fonte: tratamento padrão de estruturas e ruído de
arredondamento em Oppenheim & Schafer, *Discrete-Time Signal Processing*,
capítulo de estruturas de sistemas discretos; **o revisor deve conferir a
edição e a seção**.

Esta proposta **guarda todos os estados em int32**, o que contorna o
problema ao custo de memória: L estados × 4 bytes, irrisório para L ≤ 41.

**Alternativa a avaliar:** uma realização **DF-I com um acumulador**:
- guarda os históricos das características até o maior atraso;
- a cada amostra soma Σ θ_j z_j(k − m_j) num único int32.

Tem o mesmo número de arredondamentos e memória maior (|𝒢| × maxDelay), mas
é mais simples de analisar. **O R2 deve comparar TDF e DF-I** para não
favorecer a TDF por preferência (§11).

### 9.2 Sensibilidade dos coeficientes da parte linear

As formas diretas, inclusive a TDF-II, são sensíveis à quantização dos
coeficientes quando há polos agrupados perto do círculo unitário. Remédio
clássico: cascata de seções de 2ª ordem (biquads).

**Fase 2, condicionada ao R2:**
- separar a parte AR linear, y = F / A(q), em que F reúne todos os outros
  termos;
- fatorar A(q) pelas raízes, com `StabilityAnalyzer::monic_roots`
  (Durand–Kerner, já no núcleo [código], `stability_analyzer.hpp:34–40`);
- realizar 1/A(q) como cascata de biquads em TDF-II.

O histórico de ŷ continua necessário para os termos não lineares em y.
Só vale a complexidade se o R2 mostrar que a quantização dos coeficientes
AR domina o erro.

### 9.3 Outros riscos

- Modelos `legacy` ficam fora (§10).
- A faixa de sinais escolhida pelo treino pode ser excedida na validação ou
  no teste. A saturação é contada e relatada, nunca escondida.
- A equivalência em double não é bit a bit: a ordem das somas e √ no lugar
  de `pow` mudam o último bit, e em modelos quase divergentes isso pode
  mudar o passo de divergência. O critério do R1 trata disso.
- A proposta não resolve o desalinhamento entre ajuste por QR um passo à
  frente e uso em simulação, discutido em 01 §3.A e no E2.

---

## 10. Escopo e restrições

- **Motor congelado:** nada em `cpp/build` nem em `cpp/build_phase0` é
  recompilado. A ferramenta seria um alvo separado (`aegis_realize`, build
  `cpp/build_realize`), nos moldes do `aegis_phase0`. Ela usa
  `RationalModel::simulate` do núcleo apenas como **referência** para a
  equivalência.
- **Compilador:** a máquina atual (Ryzen 5 PRO 5650G) **não tem compilador
  C++**. Instalar o MSYS2 UCRT64 (g++), como na máquina original, exige
  autorização do usuário.
- **Linguagens:** C++ e Dart, sem Python (regra do usuário).
- **Dados:** só `experiments/data/processed/<b>/est.csv`, segmentos de
  treino e validação com a divisão explícita da Fase 0 (§0 do pré-registro).
  Nenhum CSV de teste é aberto.
- **Modelos:** lidos só de `report.model`. Nenhum campo de teste é lido.
- **Modos de potência:** `hybrid` e `signed`. `legacy` (modelos
  `legacy_head`) fica fora: a semântica (|x| + 1e−6)^p não se reduz à
  grade de √.
- **Ordem:** só depois de o E3 terminar (SB em andamento em 2026-11-23),
  para não disputar a CPU. Limite de 6 processos e prioridade BelowNormal.

---

## 11. Plano de validação (a pré-registrar antes de executar)

Os critérios abaixo são a proposta do autor. Eles **devem ser fixados**, com
eventuais ajustes do revisor e do usuário, **antes** de qualquer execução
com modelos reais.

| Etapa | O que mede | Critério |
|---|---|---|
| **R0**: testes da ferramenta, sintéticos | (a) TDF em double contra `RationalModel::simulate` em modelos com expoentes 1, 2, 3, 0,5, 1,5, 2,5, termos cruzados com r > 0, racionais, e um modelo forçado a divergir; (b) tabela/raiz contra `std::sqrt`; (c) análise de estouro: casos construídos para estourar devem ser detectados, e para não estourar, aprovados; (d) aquecimento (§4.1, passo 6) | (a) diferença máxima por amostra ≤ 1e−12 (unidades normalizadas) e passo de divergência idêntico; (b) erro ≤ meio LSB do formato de saída; (c) 100 % de acerto; (d) idem (a) |
| **R1**: equivalência em modelos reais, double | 30 campeões `aegis_full` (CT, WH, SB) e os 240 do E3, no segmento de validação | Diferença relativa de RMSE livre de validação ≤ 1e−9; mesmo veredito de divergência. Se o passo de divergência diferir, relatar caso a caso |
| **R2**: quantização | Fatores: formato de sinal {Q2.13, Q3.12}; acumulador {int32, int64}; raiz {tabela completa, segmentada}; estrutura {TDF, DF-I}; referência float32. Medidas: ΔRMSE relativo de validação (unidades originais) contra double, saturações de ŷ e de características, estouros, divergências novas. Estratificação: benchmark; tamanho (`aegis_full` × E3); polinomial × racional; só inteiros × com fracionários | **Implantável** = sem estouro, sem divergência nova, sem saturação de ŷ e ΔRMSE ≤ 5 % (limiar a confirmar antes) |
| **R3**: previsão de ruído | RMS do erro de quantização previsto (ruído branco uniforme nas fontes da §7.4, propagado pelo modelo tangente-linear ao longo da trajetória) contra o medido | Descritivo; razão previsto/medido relatada |
| **R4**: velocidade | Tempo de simulação livre em double: TDF × `RationalModel::simulate`, mesmos modelos e segmentos, mediana de 20 repetições, máquina ociosa, prioridade fixa | Adotar a TDF como simulador no A1 se R1 for aprovado e o ganho for ≥ 2× nos modelos do E3. Relatar também o ganho em modelos `aegis_full` |

**Custo estimado:**
- desenvolvimento de 2 a 4 dias;
- execução de minutos: 270 modelos × poucas variantes × ~4 000 amostras.

**Saídas:**
- `experiments/results_realize/<b>/*.jsonl`;
- manifesto com SHA-256 do executável, do pré-registro e dos `est.csv`;
- relatório `experiments/realize/REALIZE_REPORT.md` com todos os resultados,
  inclusive os desfavoráveis.

---

## 12. Correções feitas em relação à versão dita no chat

Para transparência com o usuário e com o revisor:

1. **"~100 `pow` por amostra" estava errado.** O núcleo já usa
   multiplicação para expoentes inteiros (§2.3). O número correto é cerca
   de 20 por amostra nos modelos grandes do E3, e menos de 1 nos campeões
   `aegis_full` (§5).
2. **"Única requantização por amostra" só vale no caminho de acumulação**
   (§7.4).
3. **O limite de estouro não é "por slot":** cada slot recebe todos os
   termos uma vez, então o limite é o mesmo para todos (§7.3).
4. **"`simulate` copia o bloco de dados inteiro":** copia `md + n` linhas.
   No modo `simulation`, isso é o segmento inteiro; no `one_step`, só
   md + 50 linhas (§2.4).
5. **O ganho de velocidade na busca foi apresentado com otimismo.** A TDF
   não toca no QR nem na montagem de Ψ, que podem dominar (§5).

---

## 13. Pedido ao revisor: pontos a examinar com prioridade

1. **Equivalência (§3.2, §4):** a reescrita φ_j(k) = z_j(k − m_j), a escolha
   da variável de disparo, o aquecimento e a semântica de divergência
   reproduzem exatamente `RationalModel::simulate`? Há caso de borda com
   fatores repetidos da mesma variável e do mesmo atraso dentro de um termo?
   [código] A canonicalização (`regressor_library.cpp:110–114`) **descarta**
   o segundo fator com a mesma (variável, atraso) e força o banco do termo
   ao do regressor. Mas `Regressor::evaluate` (`:37`) multiplica todos os
   fatores presentes. Se um JSON trouxer duplicatas não canonicalizadas, a
   realização deve seguir `evaluate` (multiplicar), não a canonicalização.
   Conferir se os modelos exportados estão sempre canonicalizados.
2. **Base `hybrid` (§6.1):** as identidades de 1,5 e 2,5 estão certas para
   x < 0 e x = 0? Para p não inteiro, o núcleo usa sign(x)·|x|^p com
   sign(0) → 0 via `x < 0.0 ? −r : r`, e r = 0 em x = 0.
3. **Formatos (§7.1):** Q2.13 é adequado? A saturação em ±4 pode mascarar
   divergências que o núcleo detecta só em ±10?
4. **Limite de estouro (§7.3):** a prova vale? O argumento de complemento
   de dois para somas parciais está correto nas condições dadas? O limite
   garantido é pessimista demais para ser útil?
5. **Arredondamentos (§7.4):** a lista está completa?
6. **TDF contra DF-I (§9.1):** há razão para preferir uma delas antes do R2?
   A citação clássica sobre TDF-II em ponto fixo está correta?
7. **Plano (§11):** os critérios são adequados e fixáveis antes? Falta algum
   controle? Por exemplo: float32 como referência, ou modelos `signed_continuous`
   do CT para os expoentes contínuos.
8. **Velocidade (§5):** a estimativa de que QR e montagem de Ψ dominam o
   custo é plausível? Que *profiling* mínimo resolveria isso antes de
   escrever a ferramenta?
9. **Regras (§10):** algo viola as regras do usuário (teste fechado, motor
   congelado, sem Python, carga da máquina)?

---

## 14. Referências internas

- `docs/architecture/01_ARQUITETURA_ATUAL.md`: fluxo do núcleo; §3.A
  (ajuste × uso) e §3.E (custo).
- `docs/architecture/06_CAPACIDADE_E_AJUSTE.md` e `07_PARECER_REVISAO.md`
  (§9.5, §10.1, §10.3): admissibilidade, polo dominante do CT.
- `experiments/phase0/PHASE0_PREREG.md` (§0, regras de dados) e
  `PHASE0_REPORT.md`: resultados E1/E2.
- `experiments/results_phase0/SUMMARY_E3.md`: E3; o SB ainda estava em
  execução quando este documento foi escrito.
