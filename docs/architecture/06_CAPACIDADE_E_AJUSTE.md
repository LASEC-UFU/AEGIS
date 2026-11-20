# Capacidade, parcimônia e ajuste por simulação — duas hipóteses ligadas

Data: 2026-11-20. Complemento solicitado pelo usuário durante a análise.
**Não houve nova execução experimental, alteração de configuração ou leitura
de teste WH/SB.** Evidência de código e do CT já exposto, com discussão causal
limitada a hipóteses. Este estudo passa a integrar os gates anteriores.

## 1. O que “quatro parâmetros” significa aqui

`identification_pipeline.cpp:1230` reporta `num_regressors()+1`: são
**coeficientes ajustados**, incluindo intercepto. Não conta as escolhas de
atrasos, variáveis, expoentes, produtos e denominador feitas pela busca.
Portanto “quatro parâmetros” não significa quatro graus de liberdade totais
do processo de seleção. Registrar separadamente coeficientes, fatores,
expoentes/atrasos livres e custo de busca; BIC com k igual só aos coeficientes
também não contabiliza toda essa seleção estrutural.

O relatório CT da seed 1 contém três regressores, três fatores e intercepto:

`ŷ(k) = −0.00948517 y(k−30) + 0.995462 y(k−1) + 0.0460098 u(k−5) + 0.0141719`

Equação em coordenadas normalizadas, coeficientes exibidos com a precisão
da string exportada, sem pretender que o arredondamento reproduza o JSON
completo. Denominador 1, todos os expoentes 1: neste exemplo, modelo linear.
Fonte: `experiments/results/cascaded_tanks/aegis_full/run_1.json`, campos
`report.model`, `report.equation`, sem usar teste para uma decisão nova.
As dez seeds da referência têm quatro coeficientes no resumo existente.
`no_postprocessing` também tem quatro; a poda final não explica sozinha esse
tamanho. A semente 1 registra zero remoções no pós-processamento.

## 2. Há um teto duro antes de qualquer penalidade

`experiments/configs/conditions/aegis_full.json` fixa `maxRegressors=8`.
Com intercepto, o teto é **nove coeficientes**. O modelo com quatro não
atinge esse teto, então há duas perguntas diferentes:

1. Por que a busca escolhe quatro quando pode chegar a nove?
2. Nove são suficientes para uma representação que precisa de dezenas?

Retirar γ não responde à segunda pergunta. A proposta inicial com a mesma
gramática e limite de oito regressores preserva a comparação histórica, mas
não testa a hipótese de capacidade próxima de 40. É preciso um estudo
separado, com orçamento igualado e limites variados, antes de decidir o
limite padrão futuro. Não aumentar o limite do protocolo em andamento.

## 3. Conferência da referência pNARX e diferenças de representação

No [DCE 2026, §4.2 e Tabelas 2–3](https://www.cambridge.org/core/journals/data-centric-engineering/article/benchmarking-for-nonlinear-system-identification-submission-platform-and-baseline-results/BD06B2C87096B4A700EE173A298A0FEC),
CT usa 11 lags de entrada, dois de saída e grau três. A fórmula univariada
tem `(11+2)×3=39` colunas de Legendre. “Cerca de 40” é justificável como
contagem aproximada de coeficientes; não certificar intercepto adicional
sem conferir o código da referência. O ajuste é de um passo. O vetor descrito
inclui `u(t)`; o AEGIS usa atrasos a partir de 1. Essa diferença de convenção
temporal deve ser controlada, sem introduzir `y(t)` como regressor causal.

**Inferência nossa:** uma base Legendre univariada de grau três pode ser
expandida em monômios univariados mais constante. Sem regularização e com
mesmo suporte/escala/linhas, as duas bases geram o mesmo espaço linear.
Diferenças numéricas de condicionamento não são capacidade adicional.
Entretanto, um único termo Legendre cúbico não corresponde necessariamente
a um único regressor monomial: sua expansão pode ocupar vários. Comparar
número de “termos” sem a base e o posto é insuficiente.

O AEGIS permite produtos e racionais que esse pNARX não usa, mas ser mais
geral na forma de cada termo não significa cobrir a mesma combinação com
apenas oito regressores. Não se conclui que 39 colunas sejam todas necessárias
ou independentes; medir posto, condicionamento e curva de validação.

## 4. Quanto as penalidades podem pesar

Em `individual_evaluator.cpp:21`, complexidade é **número de fatores**, não
de coeficientes. Produtos são mais caros que termos univariados. A soma inclui
também BIC/n (`:97`) e desvio de expoentes (`:25`); grau dois/três custa mais,
mesmo sem aumentar o número de coeficientes em cada regressor.

Para adicionar um termo polinomial de um fator e expoente p, com maxlag e
linhas de treino fixos, a mudança de fitness no modo um passo é:

\[
\Delta f=\Delta E_{val}+\alpha\log(MSE_{novo}/MSE_{antigo})
 +\alpha\frac{\log n}{n}+\gamma+\delta|p-1|
 +\theta\Delta E_{fr}+\zeta\Delta P_I+\eta\Delta P_S.
\]

Com α=0,05, n≈800, γ=0,01 e δ=0,01, o incremento de contagem BIC é
aproximadamente **0,000418**, contra **0,01** pelo fator e **0,01** adicional
se p=2. São unidades do fitness normalizado, **não volts**. Exemplo analítico,
não cálculo de efeito observado. A parte log(MSE) pode compensar a penalidade;
não se pode simplesmente somar custos e dizer que o termo será rejeitado.
γ/θ efetivos dependem da fase/ilha/ação; registrar seus valores reais. Ao
mudar maxlag, n também muda no ajuste atual: não aplicar esta conta sem
controlar as linhas de estimação.

Isso mostra uma pressão explícita maior que o simples acréscimo de k no BIC,
mas não prova que seja excessiva para estes dados. Ruído, colinearidade e
validação curta podem justificar parcimônia. Atenuar só γ deixa δ, BIC,
perfil da ilha e pisos da contribuição de entrada ativos; `no_curriculum`
também não é ablação limpa da penalidade de complexidade.

## 5. A segunda observação: resultados baixos frequentemente ajustam simulação

A revisão existente contém métodos de erro de simulação, TSEM, SUBNET e
modelos recorrentes entre os bons resultados CT; outros incorporam física.
Isso **motiva** testar ajuste livre, mas “quase todos abaixo de 0,35 V” é
uma observação da amostra de artigos conferidos, não um levantamento
exaustivo ou uma relação causal estimada. Não converter esse limiar
retrospectivo em meta para escolher modelos no teste.

Há dois contrastes essenciais:

- O pNARX que melhora o AEGIS ainda usa ajuste de um passo: logo mudar a
  loss não é condição necessária para melhorar a referência atual.
- O `aegis_sim` ainda ajusta coeficientes por QR de um passo: logo seu
  resultado não refuta a hipótese de **ajustar** por erro livre; só testa
  outra maneira de pontuar a estrutura com o ajuste antigo.

Ajuste por simulação é não linear também nos coeficientes de um modelo
polinomial com realimentação. QR é ótimo para predição com regressores
medidos, não para a trajetória recursiva. Se existe ruído de saída, usar
y observado como entrada do ajuste pode introduzir erro nas variáveis;
output error ajuda a alinhar o problema, mas não é garantia de ausência de
viés, sobretudo com ruído de processo, estrutura errada ou contexto inicial
ruidoso. Não atribuir tudo à loss sem controlar esses fatores.

## 6. Estudo discriminante A1-C, anterior às execuções

Estender o plano A1 com **H8 (capacidade/parcimônia)**, sem consumir reservas
confirmatórias. Desenvolvimento: só treino/validação CT/WH/SB, seeds 21–30,
mesmos splits, contador e tratamento de falhas do plano principal.

### 6.1 Curvas de capacidade fora da busca evolutiva

Construir bases univariadas polinomiais prefixadas de tamanho K, ajustadas
nas mesmas linhas do treino, com contextos e atrasos comuns. QR com posto
reportado. Fazer dois controles temporais: convenção AEGIS (entradas
atrasadas) e suporte equivalente ao DCE com entrada contemporânea quando
compatível com a definição oficial de dados. Rotular controle de suporte,
não alteração silenciosa da gramática do AEGIS. Nunca incluir saída atual.

Comparar Legendre/monômios com espaço idêntico, constante explícita e escala
ajustada no treino; registrar equivalência das predições em caso bem
condicionado. Fazer curvas em K={4,9,20,40}, selecionando subconjuntos só por
treino (ERR forward com ordem determinística), nunca buscando o melhor K
no teste. Executar QR e LM livre em cada estrutura fixa, com mesma cota.
Regressões mal condicionadas são falhas registradas, não colunas ocultamente
eliminadas sem informar o posto efetivo.

**Leitura:** se bases maiores já melhoram validação com QR, capacidade merece
prioridade mesmo sem LM. Se só melhoram com LM, há interação capacidade×ajuste.
Se Legendre só melhora condicionamento, corrigir numérica sem atribuir o
ganho a capacidade. Se suporte temporal explica o ganho, revisar esse contrato
antes de ampliar tudo. Se nenhuma melhora, não adotar 40 por analogia.

### 6.2 Fatorial no AEGIS para separar as causas

Fatores pré-fixados:

| Fator | Níveis |
|---|---|
| Teto de coeficientes Kmax | 4, 9, 20, 40 (`maxRegressors`=3,8,19,39) |
| Penalidade de fatores γ | 0; 0,001; 0,01 |
| Ajuste de coeficientes | QR um passo; LM de simulação curto→longo |

São 24 células × dez seeds por benchmark. Estudo científico **proposto**,
não executado. Manter horizonte longo na avaliação e mesma regra de segurança,
sem agente; zerar δ e β em todos os braços polinomiais deste fatorial,
desligar annealing/overrides de γ e fixar contribuição de entrada como
diagnóstico, para não reintroduzir parcimônia por outro caminho. α fica
fixo em 0,05; um segundo contraste α=0 no nível Kmax=40, γ=0 separa a
regularização BIC residual, sem chamá-lo de ablação de γ. Papéis de ilha
mantêm preferências conhecidas; publicar γ efetivo por ilha (multiplicador
parsimony=2). Mesma inicialização e RNG por seed onde aplicável, sem exigir
trajetórias idênticas após as decisões divergirem.

Comparador escalar controlado neste estudo:
`f = E_sim,val longo + α·[ln(MSE_train,um-passo) + K·ln(n)/n] + γ·nFactors`.
É um objetivo diagnóstico próprio, igual nos dois braços de ajuste; não
usar B0 num braço e Pareto no outro ao tentar atribuir efeito a LM.
Treino/validação e regra de segurança são iguais. Em paralelo, pontuar
os candidatos por erro longo sem penalidades apenas para diagnosticar
inversões de ranking; esse score paralelo não orienta a busca escalar.

Todos os ajustes do fatorial usam a mesma primeira linha de treino (atraso
global 40), independentemente do atraso da estrutura, e a mesma janela de
validação. Isso evita atribuir à capacidade uma diferença de amostras
ajustadas; o caminho histórico, que hoje ajusta desde o atraso próprio,
permanece intacto. Essa convenção é parte explícita do braço diagnóstico.

W total igual por célula, incluindo semeadura/QR/LM e certificação. Mesmo
N de população; K maior torna avaliação mais cara e pode reduzir número de
estruturas tentadas. Registrar ambas as quantidades. Orçamento W calculado
com a mesma unidade U de referência, **não aumentar U quando Kmax aumenta**.
Análise secundária de adequação computacional em 2W para **todas** as células
do extremo Kmax=40, se planejada no manifesto antes das execuções, sem
comparar esse braço isoladamente como ganho com custo igual.

Desfechos de desenvolvimento: erro longo de validação, erro de treino,
gap treino–validação, K realizado, não linearidade/fatores, posto/condição,
geração e custo de descoberta/eliminação de estruturas maiores. Histograma
de candidatos **propostos → ajustados → admissíveis → sobreviventes** por K
e razões de rejeição. Curva de aprendizagem em prefixos temporais de 50%,
75% e 100% do treino, com a validação fixa, auxilia a distinguir capacidade
de variância por poucos dados. Não usar o teste CT para escolher o ponto.

### 6.3 Contrastes e regra de decisão antes dos dados

Comparações pareadas principais em cada benchmark, família H8 de quatro
contrastes com Holm separado e rotulado como estudo de desenvolvimento:

1. capacidade: Kmax40 vs Kmax9, γ=0, QR;
2. γ: 0 vs 0,01, Kmax40, QR;
3. ajuste: LM vs QR, Kmax40, γ=0;
4. interação: diferença do efeito LM−QR em Kmax40 vs Kmax9, γ=0.

Melhora de erro: mediana pareada relativa ≥10%, p bilateral exato <0,05
após Holm, sem aumentar falhas. Para o contraste de interação, testar a
diferença pareada dos log-ratios de erro (erro zero tratado como caso
especial explicitamente no manifesto, sem epsilon escolhido pelos dados).
Interação significativa indica que efeito do ajuste depende da capacidade;
não chamar um efeito principal isolado de explicação completa.

Se K cresce e só o treino melhora, há evidência contra aumentar capacidade
nesse regime de dados. Se bons modelos grandes são propostos/admissíveis
e eliminados por γ, há evidência de seleção excessivamente parcimoniosa.
Se não são propostos apesar do teto, investigar exploração/orçamento antes
de culpar γ. Se a escolha escalar diverge da escolha sem penalidades mas a
validação não melhora, não concluir que mais complexidade é melhor.

Escolher para confirmação a menor capacidade cujo erro de validação esteja
a até 1% do melhor dentre as configurações que passaram segurança, com
desempate determinístico; congelar junto à decisão de LM e à seleção do
plano principal. Reservas 1001–1020/2001–2020 permanecem intocadas durante
essa escolha. Confirmação da configuração escolhida vs B0C integra a família
primária do plano principal, não uma segunda chance no mesmo teste.

## 7. Consequência para a recomendação

Não recomendar apenas “trocar o objetivo para simulação” nem “aumentar para
40”. Recomendar **ajuste de simulação e estudo explícito de capacidade**,
com teste independente da pressão de parcimônia. A ordem passa a ser:
infraestrutura → estruturas fixas/capacidade → ajustador → seleção/arquivo
→ semeadura/movimento local → agentes. O teto de oito regressores fica
congelado no estudo histórico e é um fator experimental no desenho futuro.

É plausível que o ganho venha de várias interações. Nenhuma redução em V
é prometida; mais coeficientes pode elevar custo e variância. A alegação
de que o AEGIS está “simples demais” só será adotada após essas evidências.
