# 11 — Realização transposta adaptativa para identificação NARX

Data: 2026-11-23. Situação: **proposta conceitual para auditoria**. Nada
deste algoritmo foi implementado, executado ou medido.

Origem: discussão dos documentos
[08_REALIZACAO_TDF.md](08_REALIZACAO_TDF.md),
[09_ESTADOS_TRANPOSTOS_IDENTIFICACAO.md](09_ESTADOS_TRANPOSTOS_IDENTIFICACAO.md)
e [10_AUDITORIA_DO_09.md](10_AUDITORIA_DO_09.md). O usuário busca **ganho de
velocidade e de convergência na identificação** de modelos grandes, com
expoentes reais e uma equação de diferenças interpretável. Não há interesse
em embarcar código por si só. Ponto fixo entra apenas se trouxer ganho
medido. A analogia desejada é com a organização por estados da TDF-II de
filtros IIR, sem pressupor que a transposição linear seja aplicável sem
adaptação a termos NARX não lineares e racionais.

Etiquetas: **[código]** conferido no núcleo atual; **[dedução]** decorre das
equações sob condições explícitas; **[hipótese]** exige experimento;
**[decisão]** escolha proposta que a auditoria deve contestar.

---

## 1. Resumo

Propõe-se uma realização com **estados de características por regressor** e
dois acumuladores transitórios para numerador e denominador. Os estados
guardam características **sem multiplicá-las pelos coeficientes**. Assim,
coeficientes podem ser atualizados durante a identificação sem corrigir
contribuições antigas já agendadas. Cada amostra custa, em princípio,
`O(K+F)` operações aritméticas básicas, além da avaliação das potências,
para `K` regressores e `F` fatores ativos.

A identificação teria três movimentos:

1. **Ajuste em fluxo com y medido:** aprendizado barato de coeficientes
   pelo erro de equação; uma passada não exige Ψ completa nem QR para
   cada estrutura.
2. **Refino por simulação em janelas:** os mesmos estados passam a receber
   ŷ e o erro livre orienta coeficientes e expoentes por gradiente da
   trajetória, com parâmetros fixos durante cada janela.
3. **Revisão estrutural periódica:** poucos regressores são acrescentados,
   retirados ou modificados; a aceitação usa reajuste e simulação exatos.

QR completo permanece como referência numérica e pode recalibrar modelos
selecionados. **[hipótese]** O conjunto reduz o tempo para obter uma boa
solução de validação com aproximadamente 20–40 parâmetros. Não se afirma
que cada passada barata converge sozinha, nem que o resultado atual já
demonstra esse ganho.

---

## 2. Modelo e fato que motiva a mudança

O modelo continua sendo

```
φ_j(k) = Π_f g_{p_f}(x_{v_f}(k−d_f))
N(k) = c + Σ_{j∈N} θ_j φ_j(k)
D(k) = 1 + Σ_{j∈D} θ_j φ_j(k)
ŷ(k) = N(k)/D(k)
```

Os atrasos são causais (`d_f ≥ 1`) nos modelos gerados pelo núcleo.
`g_p` preserva o modo de potência (`hybrid` ou `signed`); os expoentes
podem ser reais. A semântica exata de `legacy` exigiria ramo próprio.

[código] O avaliador atual constrói Ψ de treino, ajusta θ e c por QR,
calcula ERR, constrói Ψ de validação e simula o modelo
(`cpp/src/individual_evaluator.cpp:289–379`). O QR racional usa colunas
`−y_medido(k)φ_j(k)` no denominador
(`cpp/src/rational_model.cpp:12–36`). [dedução] A pontuação por simulação
não transforma esse ajuste em minimização do erro de simulação.

O documento 10 aponta custo possivelmente dominante em QR e nas duas
passagens de ERR para modelos grandes. É uma **hipótese de perfil de custo**:
tempos de parede do E3 e K do campeão não medem, sozinhos, a distribuição
de custo por candidato. Uma medição por etapa deve preceder qualquer
implementação ampla desta proposta.

---

## 3. Os estados: características antes dos coeficientes

Para o regressor `j`, definir

```
m_j = min_f d_f
r_f = d_f − m_j
z_j(t) = Π_f g_{p_f}(x_{v_f}(t−r_f))
φ_j(k) = z_j(k−m_j)
```

Um anel do regressor, ou uma fila de eventos equivalente, entrega
`z_j(t)` ao instante `t+m_j`. Termos cruzados usam históricos curtos dos
fatores com `r_f>0`. Características `(variável, expoente, modo)` repetidas
são calculadas uma vez por amostra e compartilhadas. A compilação deve
preservar a multiplicidade e a ordem dos fatores quando comparada ao
`Regressor::evaluate` atual.

No instante `k`:

```
N ← c; D ← 1
para cada regressor j:
    φ_j ← retirar característica devida do estado j
    se j é numerador:   N ← N + θ_j·φ_j
    se j é denominador: D ← D + θ_j·φ_j
ŷ(k) ← N / guarda(D)
calcular características de u(k) e do y escolhido para a passada
formar z_j(k) quando todos os seus fatores estão disponíveis
agendar z_j(k) no estado j para k+m_j
```

**[dedução]** Os coeficientes entram somente quando a característica
vence. Portanto, alterar θ não exige editar eventos futuros armazenados.
Isso evita um problema da forma global que agenda `θ_j z_j`: nela, mudar
θ deixaria contribuições pendentes calculadas com o coeficiente antigo.

**Custo:** produzir uma saída requer `K` leituras de características e
`K` MACs, mais cálculo dos `F` fatores/produtos necessários. Para `K≈40`,
esse custo deve ser comparado, em tempo real, ao simulador direto com
cache de potências e ao anel global do documento 08. O anel global pode
ser mais rápido para **simular um modelo fixo**, enquanto o anel de
características é mais simples para **adaptar coeficientes**. Não se
presume que este último seja o simulador mais rápido.

**Memória:** um limite bruto de `K·(Dmax+1)` valores double, se cada termo
tiver um anel de comprimento máximo; com `K=40` e `Dmax=40`, são cerca
de 13 KB, fora históricos de fatores e tape de gradientes. Comprimentos
específicos por termo, filas esparsas ou partilha de fatores podem reduzir
isso. A memória não é o principal argumento de adoção; medir cache e
acesso importa.

---

## 4. Passada A: ajuste barato pelo erro de equação

Durante esta passada, os estados recebem o **y medido**. Para uma
estrutura fixa, construir implicitamente o vetor por amostra

```
a(k) = [1, φ_j(k) para j∈N, −y(k)φ_j(k) para j∈D]
e_eq(k) = y(k) − a(k)ᵀ θ̃
θ̃ = [c, θ_1, …, θ_K]
```

Isso é o mesmo problema de erro de equação pseudo linear do QR atual,
mas resolvido aproximadamente em fluxo. Uma atualização inicial a
comparar é gradiente normalizado com regularização:

```
θ̃ ← θ̃ + η · a(k)e_eq(k)/(ε + ||a(k)||²) − ηλ·R(θ̃)
```

`R` e a aplicação da regularização precisam ser especificados; uma
penalização indiscriminada pode enviesar o intercepto ou reprimir termos
úteis. Normalização das colunas e passos por parâmetro são alternativas
experimentais. O aprendizado pode ser feito em mais de uma época, com
ordem temporal preservada e custo de cada época contabilizado.

**[dedução]** Uma atualização do vetor custa `O(K)` por amostra, além de
formar as características. **Não equivale ao QR:** gradiente em fluxo
tem convergência dependente de escala, correlação de colunas, passo e
excitação dos dados. Modelos racionais com colunas quase dependentes
podem convergir lentamente. Comparar com QR em qualidade **por tempo**,
não por uma única passada. Um QR completo ocasional pode servir de
recalibração e controle; seu custo entra no orçamento.

Não se deve usar `e_eq` como medida final de qualidade dinâmica. Seu
papel é produzir rapidamente uma boa condição inicial para a Passada B.

---

## 5. Passada B: ajustar o comportamento em simulação

Durante uma janela `[s,s+H)`, os parâmetros ficam **congelados**. O
aquecimento usa o y medido antes de `s`, conforme um contrato único de
condição inicial. A partir de `s`, os estados recebem ŷ; y medido só
fornece o alvo da perda. Ao fim da janela:

```
L_H = Σ_{k=s}^{s+H−1} ρ(ŷ(k)−y(k))
```

`ρ` pode começar quadrático, com política explícita para divergência e
denominador quase nulo. Uma passagem reversa pelos estados, produtos,
atrasos e divisão fornece a direção de ajuste dos coeficientes e dos
expoentes ativos. Localmente, longe da guarda do denominador:

```
δŷ(k) = [δN(k) − ŷ(k)·δD(k)] / D(k)
```

Os `δN` e `δD` incluem efeitos indiretos das saídas passadas. Truncar
a diferenciação na fronteira da janela introduz viés; janelas curtas
podem favorecer dinâmica de curto prazo. **[decisão]** Comparar uma
progressão de horizontes curtos para longos, com janelas contíguas e
esquema de aquecimento pré-definido. Uma trajetória completa em treino
continua necessária para certificar cada modelo selecionado.

**Custo esperado de uma passada:** proporcional às operações da
trajetória percorrida, mais uma passagem reversa e armazenamento ou
recomputação dos valores intermediários. Não são `K` simulações separadas
para obter um gradiente de `K` parâmetros. O custo total depende do
número de épocas, janelas, rejeições de passo e certificações exatas;
essa contagem deve ser publicada. Se a passagem reversa não se pagar
para `K≈20–40`, um refino local restrito a poucos parâmetros é controle
obrigatório.

Atualizar θ **entre** janelas, e não durante uma trajetória cuja perda
será diferenciada, mantém claro qual modelo gerou cada estado. Reiniciar
e aquecer a janela após a atualização evita misturar estados gerados por
coeficientes anteriores. Uma variante adaptativa online contínua pode
ser estudada separadamente; sua trajetória é de um sistema que muda no
tempo, não a simulação de uma equação de diferenças fixa.

---

## 6. Revisão estrutural em ritmo mais lento

Manter no máximo `Kmax` regressores ativos (por exemplo, 39 mais
intercepto) e um conjunto pequeno de propostas. Cada ciclo de revisão:

1. Usar resíduos de equação da Passada A para sugerir variáveis,
   atrasos, expoentes e produtos ainda ausentes.
2. Gerar também alterações por exploração estrutural, para não depender
   inteiramente de uma triagem local.
3. Estimar o efeito de inserção, remoção ou troca no objetivo de treino;
   quando disponível, usar gradientes da Passada B como **ranking**, sem
   tratá-los como novo fitness.
4. Reajustar os poucos candidatos escolhidos e simular cada trajetória
   inteira de forma exata. Decidir por validação, admissibilidade e
   custo, dentro do mesmo orçamento do controle.

No modelo com realimentação, apagar a série de um termo do acumulador
antigo **não produz** a trajetória do novo modelo: y futuro muda. Estados
antigos servem para gerar propostas, mas a aceitação exige nova trajetória.
Essa regra já aparece no documento 09 §3.3 e continua válida aqui.

**[decisão]** Experimentar a revisão estrutural como operador próprio,
comparado ao DE/JADE atual. Não supor que atualizações locais substituam
a diversidade entre ilhas; a variante pode coexistir com ilhas globais ou
receber sementes delas. A contribuição do operador deve aparecer na
fronteira **qualidade × tempo total**, não apenas em menos avaliações.

---

## 7. Expoentes reais, ramos e derivadas

Na grade de 0,5, fatores iguais de uma variável podem compartilhar
`sqrt(|x|)` e produtos. Com expoentes contínuos, compartilhar cálculo
depende de expoentes **exatamente** iguais; a proposta não pressupõe
um dicionário finito. Potência contínua pode ser o custo dominante depois
de reduzir QR/ERR, e isso precisa de profiling próprio.

Para um ramo `signed`, e `x≠0`,

```
∂g_p(x)/∂p = g_p(x)·ln|x|
```

No modo `hybrid`, para `x<0`, os expoentes inteiros pares dão `x^p>0`,
enquanto a vizinhança não inteira dá `−|x|^p<0`. **[dedução]** A função
salta em inteiros pares; gradiente em p não pode cruzá-los como se o
objetivo fosse suave. Inteiros pares devem ser escolhas discretas;
expoentes não inteiros podem ser refinados dentro de seu ramo. Em
`x=0`, `∂g/∂x` pode ser singular quando `0<p<1`; qualquer derivada
regularizada serve somente para propor passos. A aceitação usa sempre a
base exata do modelo.

---

## 8. Estabilidade e limites de interpretação

- No racional, queda de `e_eq` pode coincidir com denominador quase zero.
  Monitorar `min|D|`, mudanças de sinal, divergência e RMSE livre em
  treino/validação. Limites e penalidades devem ser fixados antes do
  experimento; não afirmar estabilidade global a partir de janelas
  finitas.
- O treino com y medido pode ter viés por ruído de saída e pelo erro de
  equação. A Passada B reduz desalinhamento com o uso final, mas não
  garante identificar a dinâmica verdadeira.
- Gradiente normalizado pode estagnar com regressores muito correlacionados.
  Normalização, pré-condicionamento barato, QR ocasional ou seleção de
  colunas são variantes a comparar, cada qual com seu custo.
- O algoritmo produz uma equação fixa **após** a identificação. Durante
  ajustes online, θ varia no tempo; uma trajetória criada nesse período
  não representa a resposta livre de um único modelo fixo.
- Estados e gradientes são recursos de cálculo. A equação de diferenças
  permanece interpretável, mas a contribuição dinâmica de um termo não
  se obtém apenas de `θ_j φ_j`: remover o termo muda toda a realimentação.

---

## 9. Comparações mínimas e critérios para investir

**P0 — medir antes de construir:** tempos por etapa em candidatos reais do
E3, incluindo construção de Ψ, QR, as duas rotinas de ERR, predição,
simulação, mutação e diagnósticos. Registrar distribuição de K, número de
fatores, expoentes fracionários e termos do denominador. Separar treino e
validação, custo frio e quente.

**Controle numérico:** para estruturas fixas, comparar Passada A com QR
em SSE de equação, coeficientes, posto, tempo e memória; para a Passada B,
comparar com o mesmo modelo inicial sem refino e com um método de refino
por simulação definido previamente. Reportar falhas e divergências.

**Comparação arquitetural:** para simular o mesmo modelo fixo, comparar
(a) núcleo atual, (b) forma direta com características compartilhadas,
(c) anel global do documento 08 e (d) estados de características deste
documento. A variante (d) pode perder em tempo por amostra e ainda ganhar
tempo total de identificação por permitir adaptação barata.

**Comparação de identificação:** mesmo treino, validação, condições
iniciais, K máximo, sementes pareadas e orçamento **de tempo total**.
Publicar curva de melhor RMSE livre de validação versus tempo e número
de avaliações exatas, distribuição final de K, divergências, memória e
CPU. Incluir ablações: só Passada A; A+B; A+B+revisão estrutural;
DE/JADE de referência. Não contar uma passada barata como equivalente a
uma avaliação completa.

**Gate de adoção:** a arquitetura só avança se entregar ganho consistente
na fronteira qualidade × tempo em modelos grandes, sem piorar de modo
relevante admissibilidade ou interpretabilidade. O limiar numérico, os
benchmarks e o orçamento devem ser pré-registrados antes da execução.
Nenhum dado de teste WH/SB participa de escolha de algoritmo; seguir
`experiments/phase0/PHASE0_PREREG.md` para divisão e normalização.

---

## 10. Pedido à agente auditora

1. A realização de características sem coeficientes reproduz todos os
   termos do núcleo, inclusive termos cruzados, racional, aquecimento e
   divergência? Qual a melhor organização do estado quando há atrasos
   relativos e fatores duplicados?
2. O custo `O(K+F)` por amostra omite alguma recomputação ou acesso caro?
   Estimar custo para K≈20–40 e comparar anel global, forma direta com
   cache e estado individual.
3. A atualização normalizada da Passada A é adequada a colunas
   pseudo lineares correlacionadas e a denominadores? Qual alternativa
   incremental tem melhor compromisso entre tempo e qualidade?
4. Derivar a passagem reversa da Passada B para termos cruzados e
   racionais; definir custo de memória e o efeito do truncamento.
5. Como comparar o ajuste de equação em fluxo com QR sem atribuir ao
   algoritmo uma vantagem decorrente de menos trabalho ou menos épocas?
6. O tratamento de expoentes reais e da descontinuidade `hybrid` está
   correto? Que restrições de passo e de proximidade de zero são necessárias?
7. O operador de revisão estrutural pode manter diversidade e melhorar a
   convergência em modelos grandes? Que controles mostram ganho real por
   tempo total, além de ganho por avaliação?
8. Existe antecedente científico próximo dessa combinação de realização
   transposta, ajuste em fluxo, refino livre em janelas e revisão
   estrutural? Delimitar novidade sem inferi-la apenas da combinação.
9. O profiling do E3 justifica esta direção frente às otimizações mais
   simples listadas no documento 10, especialmente ERR sob demanda e
   cache de fatores?

## 11. Referências internas

- `08_REALIZACAO_TDF.md`: anéis globais e equivalência de simulação.
- `09_ESTADOS_TRANPOSTOS_IDENTIFICACAO.md`: estados por regressor e regra
  de validade após mutação.
- `10_AUDITORIA_DO_09.md`: hipótese de custo em QR/ERR e estatísticas
  deslocáveis, ainda sujeitas a auditoria para colunas racionais.
- `01_ARQUITETURA_ATUAL.md` e `06_CAPACIDADE_E_AJUSTE.md`: diferença entre
  ajuste de um passo e simulação, capacidade e controle de orçamento.
- `experiments/phase0/PHASE0_PREREG.md` e
  `experiments/results_phase0/SUMMARY_E3.md`: regras dos dados e resumo E3.
