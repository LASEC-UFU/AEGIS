# 12 — Auditoria do documento 11 (realização transposta adaptativa)

Data: 2026-11-23. Auditado:
[11_REALIZACAO_TRANPOSTA_ADAPTATIVA.md](11_REALIZACAO_TRANPOSTA_ADAPTATIVA.md).
Contexto: [10_AUDITORIA_DO_09.md](10_AUDITORIA_DO_09.md) §11 (ordem P0 →
P1 → P2′a → P2′b → P3′ → P4/P5).

Etiquetas como nos documentos anteriores: **[código]** conferido;
**[dedução]**; **[inferência]**; **[recomendação]**. Referências externas
estão marcadas "conferir" quando citadas de memória.

---

## 1. Veredito

O 11 é a proposta mais cuidadosa da série: separa hipótese de dedução,
exige P0, pede comparação por tempo total e não reivindica ganho sem
medição. As ressalvas da §8 do 11 estão corretas. Três pontos mudam a sua
leitura:

1. **O estado de características do §3 não é uma forma transposta.** É a
   forma direta com linhas de atraso por regressor (§2 abaixo). Está
   correto e é útil para adaptar coeficientes, mas não traz o ganho
   estrutural da TDF-II.
2. **A Passada A (§4) é dominada pela solução exata.** Gradiente
   normalizado em fluxo não vence mínimos quadrados exatos em qualidade por
   tempo nas colunas do AEGIS, que são muito correlacionadas (§3 abaixo).
   O papel dela deve ser ocupado pelo P2′a do documento 10.
3. **A Passada B (§5) é a parte valiosa, e não é velocidade: é
   alinhamento do ajuste com a simulação livre.** Tem antecedentes
   próximos na literatura (§4 abaixo) e um ponto de partida no próprio
   núcleo, `LocalRefiner`.

**Recomendação:** manter P0 → P1 → P2′a como trilho de velocidade, e
acrescentar a Passada B como trilho de **qualidade** (P6, §6), começando
pela extensão do `LocalRefiner` para erro de simulação.

---

## 2. §3: estados de características (resposta ao pedido 1 e 2)

**[dedução]** Guardar z_j(t) sem coeficiente e entregá-lo em t + m_j é
ler φ_j(k) = z_j(k − m_j) de um histórico. Isso é a **forma direta**
(DF-I) com uma linha de atraso por regressor. A TDF-II economiza porque
**pré-multiplica pelos coeficientes e funde** as contribuições num número
pequeno de acumuladores. O 11 abre mão disso de propósito (coeficientes
aplicados na leitura), e a justificativa está certa: assim θ pode mudar
sem corrigir eventos agendados. O nome "transposta" deve ser trocado por
"forma direta com estados de características", para não sugerir o ganho
da TDF-II.

- **Reprodução dos termos do núcleo:** sim, sob as mesmas condições do
  08. Termos cruzados exigem histórico de r_f para cada fator. O racional
  é N/D na leitura. O aquecimento é idêntico se o estado for preenchido
  com o y medido nas md primeiras amostras, como `simulate` faz. A
  divergência, se a regra de retenção de `simulate` for copiada
  (`rational_model.cpp:117–156`). [código]
- **Fatores duplicados:** `canonicalize` já remove fatores (var, atraso)
  repetidos no mesmo regressor (`regressor_library.cpp:110–114`). O
  compartilhamento que importa é **entre** regressores: a mesma
  característica (var, expoente) calculada uma vez por amostra, com
  históricos por (var, expoente), não por regressor.
- **Custo O(K+F) por amostra:** correto, e é **o mesmo** da opção (b) do
  §9 do 11 (forma direta com características compartilhadas). Sem
  históricos por característica, a variante (d) guarda K anéis em vez de
  ≤ 12 séries; o acesso é pior, não melhor. **[inferência]** Para simular
  um modelo fixo, (b) ≥ (d) em tempo; (d) só se justifica se a Passada A
  em fluxo for mantida, e a §3 abaixo recomenda não mantê-la.

## 3. §4: Passada A (resposta ao pedido 3 e 5)

**[dedução]** O gradiente normalizado (NLMS) converge em um número de
amostras que cresce com o espalhamento dos autovalores do Gram das
colunas. No AEGIS esse espalhamento é grande por construção:
- potências da mesma variável na grade de 0,5 (x, |x|^1,5, x², …) são
  quase colineares;
- as colunas pseudo-lineares −y·φ do denominador são correlacionadas com
  as do numerador que compartilham fatores.

Uma época de NLMS custa O(N·K), mas o número de épocas para chegar perto
do mínimo cresce com o condicionamento. Já a solução exata custa
≈ ½·N·K² para formar o Gram e O(K³) para resolver (P2′a do 10), ou menos
com as tabelas deslocáveis (P2′b). Com K ≈ 40, a solução exata custa o
equivalente a ≈ 20 épocas de NLMS e entrega o mínimo exato.
**[inferência]** Para colunas mal condicionadas, isso é muito menos do que
o NLMS precisaria.

- **Alternativa incremental exata:** RLS (mínimos quadrados recursivos)
  dá a mesma solução que o QR, mas custa O(K²) por amostra, o mesmo que
  formar o Gram, e é numericamente pior. Só vale para uso **online**, que
  não é o objetivo.
- **Comparação justa (pedido 5):** quando a referência exata custa
  ½·N·K² + K³, não existe comparação em que a Passada A ganhe qualidade
  por tempo sem que o ganho venha de resolver um problema pior. A métrica
  certa é o **SSE de equação atingido por tempo de CPU**, com o QR e o
  Gram/Cholesky no mesmo gráfico. Se isso for medido, que seja num banco
  isolado com estruturas fixas tiradas dos campeões do E3, antes de
  qualquer integração.
- **Recomendação:** substituir a Passada A por P2′a como fonte da
  condição inicial da Passada B. O resultado é o mesmo papel (θ inicial
  barato), com solução exata.

## 4. §5: Passada B (resposta ao pedido 4 e 8)

É a parte mais importante do 11. O ajuste atual é sempre de um passo
(QR), mesmo no modo `simulation`, e o E3 mostrou que otimizar pela
simulação livre muda muito o resultado (WH: 10,7 mV contra 28,2 mV na
validação, mediana; `SUMMARY_E3.md`). Ajustar **os coeficientes** pelo
erro de simulação ataca o desalinhamento descrito no 01 §3.A
diretamente.

**Antecedentes próximos (conferir as referências antes de citar):**
- minimização do erro de simulação para NARX polinomial: Piroddi e
  Spinelli (2003, *Int. J. Control*), e trabalhos posteriores de Farina e
  Piroddi;
- métodos de erro de predição e de erro de saída (*output error*):
  Ljung, *System Identification*;
- *multiple shooting* para suavizar o erro de simulação em janelas:
  Ribeiro, Tiels, Aguirre e Schön (2020, L4DC, "On the smoothness of
  nonlinear system identification");
- retropropagação truncada no tempo (TBPTT), de redes recorrentes.

A combinação do 11 (janelas + derivadas + revisão estrutural) não é nova
em cada peça. A novidade defensável é a aplicação a **NARX racional com
expoentes reais** dentro de uma busca evolutiva. É preciso delimitar isso
com revisão bibliográfica, não pela combinação.

**Derivação (pedido 4):** para θ com estrutura fixa, a sensibilidade
s_i(k) = ∂ŷ(k)/∂θ_i satisfaz a recursão (modo direto)

```
s_i(k) = [ ∂N/∂θ_i − ŷ(k)·∂D/∂θ_i + Σ_j (∂N/∂φ_j − ŷ(k)·∂D/∂φ_j)·Σ_f ∂φ_j/∂ŷ(k−d_f)·s_i(k−d_f) ] / D(k)
```

onde o somatório interno percorre só os fatores de saída (variável y) do
regressor j.
- **Custo do modo direto:** O(P·(K+F)) por amostra para P parâmetros.
  Com P ≈ 40, ≈ 40 simulações. Memória O(P·Dmax).
- **Custo do modo reverso:** ≈ 2–3 simulações por gradiente, mas memória
  O(H·(K+F)) por janela, ou recomputação.
- **Gauss-Newton e Levenberg–Marquardt** precisam do Jacobiano completo,
  ou seja do modo direto. Para P ≤ 40, o modo direto é mais simples,
  exato e sem fita (*tape*). **[recomendação]** Começar por ele.
- **Truncamento:** truncar a sensibilidade na borda da janela é o que o
  *multiple shooting* trata ao tornar o estado inicial de cada janela
  variável de decisão com restrição de continuidade. Janelas com
  aquecimento pelo y medido, como o 11 propõe, são a versão sem restrição
  e introduzem o viés que o próprio 11 aponta.

**[código] Ponto de partida no núcleo:** `LocalRefiner`
(`local_refiner.hpp`, `identification_pipeline.cpp:1114`) já refina θ
por TRF/LM com Jacobiano numérico, mas sobre o **erro de um passo**
(`predict_one_step`, `local_refiner.cpp:32, 44, 72`). Trocar o resíduo por
erro de simulação e o Jacobiano numérico pelas sensibilidades acima é a
implementação mínima da Passada B. Essa versão só refina o campeão. Usá-la
dentro da busca, com mais candidatos, é uma etapa posterior.

## 5. §7: expoentes reais (resposta ao pedido 6)

A análise da descontinuidade `hybrid` está correta: para x < 0 o salto
ocorre nos inteiros **pares**. Nos ímpares, x^p = −|x|^p e a função é
contínua. Em x = 0 e 0 < p < 1, ∂g/∂x é singular. ∂g/∂p = g·ln|x| tende a
0 para p > 0.

**Cuidado adicional que o 11 não registra:** refinar expoentes por
gradiente tira-os da grade de 0,5. A única evidência que existe sobre
expoentes contínuos é desfavorável: `signed_continuous` foi pior que a
grade no CT, no teste (0,884 contra 0,661 V, p = 0,025; protocolo 1.1.0).
Isso não proíbe o refino, mas impõe que ele seja comparado com o mesmo
modelo **com expoentes fixos na grade**, refinando só θ. A versão só-θ
deve vir primeiro.

## 6. §6 e §9: revisão estrutural e critérios (pedido 7 e 9)

- A revisão estrutural do §6 coincide com o operador dirigido do 09 (P4 do
  10). A regra de aceitação com trajetória nova está correta. Sem
  comentário além do 10 §5.
- **Pedido 9:** o profiling ainda não existe. O P0 do 11 (§9) é o mesmo
  P0 do 10 §11.3, com dois acréscimos que esta auditoria adota:
  - tempo **fora** do avaliador (mutação, migração, diagnósticos),
    medido como tempo de parede menos a soma dos tempos de `evaluate`;
  - custo frio e quente, relevante para P2′b.

**Ordem resultante (acrescenta P6 ao 10 §11.4):**

| Etapa | Conteúdo | Trilho |
|---|---|---|
| P0 | *Profiling* por etapa e fora do avaliador | medição |
| P1 | Exatos: ERR sob demanda, QR por linhas, cache de fatores | velocidade |
| P2′a/b | Gram + Cholesky + ERR em K×K; estatísticas deslocáveis | velocidade |
| **P6** | **Passada B:** `LocalRefiner` com erro de simulação e sensibilidades diretas; só θ, expoentes na grade; aplicado ao campeão | qualidade |
| P3′ | Simulação em estados (forma direta com características compartilhadas) | velocidade, se o P0 indicar |
| P4/P5 | Revisão estrutural / sensibilidades dentro da busca | convergência |

A Passada A sai da lista. P6 pode correr em paralelo a P1–P2′ porque toca
outra parte do código. O critério de adoção do 11 §9 (fronteira qualidade
× tempo, pré-registrada, sem teste WH/SB) vale para P6 sem mudança.
