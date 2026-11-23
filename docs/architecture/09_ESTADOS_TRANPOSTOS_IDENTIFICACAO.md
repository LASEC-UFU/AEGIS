# 09 — Estados transpostos e identificação incremental para modelos NARX grandes

Data: 2026-11-23. Situação: **proposta conceitual para auditoria independente**.
Nenhum algoritmo deste documento foi implementado ou medido. Este texto amplia
[08_REALIZACAO_TDF.md](08_REALIZACAO_TDF.md), após a precisão do usuário: os
estados podem pertencer **à realização global, a cada regressor, ou aos dois**.
O objetivo principal é obter ganho de velocidade **na arquitetura atual de
identificação**, inclusive no tempo até encontrar bons modelos com dezenas de
regressores. Ponto fixo e implantação são possibilidades posteriores, não
condições de êxito desta proposta. Expoentes reais devem permanecer disponíveis.

Convenções: **[código]** conferido nos arquivos citados; **[dado]** lido de
resumos de validação existentes; **[dedução]** segue das equações, sob as
condições declaradas; **[hipótese]** exige medição; **[decisão]** escolha
arquitetural a contestar. A outra agente deve conferir inclusive os fatos
marcados [código] e [dedução].

---

## 1. Tese e decisão que a auditoria deve ajudar a tomar

Propõe-se um **motor de características e estados de dois níveis**:

1. Dois anéis globais de acumuladores, numerador e denominador, realizam a
   simulação livre no estilo transposto do documento 08.
2. Cada regressor possui uma receita independente de característica,
   contribuição e atraso. Na identificação, sua coluna no treino pode ser
   reutilizada ou reconstruída isoladamente. Na simulação, seu registro de
   contribuições pode ser materializado quando uma mutação o exige.
3. Uma fatoração QR atualizável examina inserção/remoção/troca de colunas sob
   dados medidos. Sensibilidades da trajetória livre *classificam* movimentos
   quanto ao objetivo real. Poucos candidatos passam por refit e simulação
   exatos antes da aceitação.

**[hipótese]** O conjunto pode reduzir (a) custo por avaliação e (b) número
de avaliações necessário para uma qualidade dada. São resultados distintos.
**Não se reivindica ineditismo** de QR incremental, seleção ortogonal,
projeção de parâmetros ou diferenciação reversa isoladamente. A combinação
proposta e seu eventual ganho no AEGIS constituem a hipótese de pesquisa.

**Gate:** nenhum código da nova arquitetura deve entrar no motor de produção
por elegância formal. A adoção exige equivalência, qualidade e ganho medido
sob o mesmo orçamento de tempo. O protótipo pode ser isolado.

---

## 2. Fatos relevantes da arquitetura atual

- [código] `Regressor::evaluate` multiplica fatores
  `power_basis(x_variable(k-delay), exponent, mode)`
  (`cpp/src/regressor_library.cpp:37`). `build_psi_matrix` percorre os
  fatores de cada regressor em todas as linhas (`:131`).
- [código] `IndividualEvaluator::evaluate` constrói Ψ de treino, ajusta
  coeficientes por `fit_from_psi`, calcula ERR, constrói Ψ de validação e
  depois chama `RationalModel::simulate`
  (`cpp/src/individual_evaluator.cpp:289–379`).
- [código] Para um regressor do denominador, `fit_from_psi` substitui sua
  coluna por `−y_medido(k)·φ_j(k)` e acrescenta intercepto. O QR minimiza o
  **erro de equação de um passo**, inclusive quando o fitness usa simulação
  (`cpp/src/rational_model.cpp:12–36`).
- [código] O QR atual é Householder e descarta colunas julgadas dependentes,
  sem pivoteamento por norma (`cpp/src/regressor_library.cpp:190–266`).
  Alterar a ordem de inserção pode alterar que coluna recebe coeficiente
  zero. Isso importa para equivalência de um QR incremental.
- [código] `RationalModel::simulate` copia `md+n` linhas, usa o y medido até
  `md−1`, realimenta as previsões e, após divergência, repete a última
  previsão saturada (`cpp/src/rational_model.cpp:117–158`).
- [código] O cromossomo pode ter expoente contínuo quando
  `exponentStep ≤ 0`; a grade usual do estudo é 0,5
  (`cpp/include/aegis/safe_power.hpp:114–122`).
- [dado] No E3, a configuração `mr39_zero_simulation` teve mediana de
  **K=22 coeficientes com intercepto no CT** e **K=33 no WH**; não são 40
  regressores efetivos. As medianas de tempo por execução foram 874 s e
  24 752 s, respectivamente. Elas **não isolam** custo de Ψ, QR, ERR,
  simulação ou busca (`experiments/results_phase0/SUMMARY_E3.md`).

O documento 08 acelera sobretudo a simulação. Para ganhar na identificação,
é necessário atacar também reconstrução de Ψ, QR e escolha de mutações.

---

## 3. Duas famílias de estados e uma regra de validade

Para cada regressor `j`, sejam `m_j=min_f d_f`, `r_f=d_f−m_j` e

```
z_j(t) = Π_f g_{p_f}(x_{v_f}(t−r_f))
e_j(t) = θ_j · z_j(t)
A_{B_j}[t+m_j] += e_j(t)             B_j ∈ {N,D}
ŷ(t) = (c+A_N[t]) / (1+A_D[t])
```

### 3.1 Estado global

[dedução] Os dois anéis globais são o caminho rápido da saída. Um slot
contém contribuições de vários regressores. Na amostra atual, lê-se um slot
de cada banco; depois, cada regressor agenda uma contribuição futura.
Produtos cruzados com atrasos diferentes ainda exigem históricos de sinais
ou características. Ver §3–4 do documento 08 para aquecimento e disparo.

### 3.2 Estado por regressor

[decisão] Cada regressor compilado contém identificador estrutural, banco,
`m_j`, receita de `z_j`, coeficiente e uma **geração de trajetória**. É
possível materializar um anel ou uma janela de `e_j` para diagnóstico,
edição e sensitividade. Manter todos os anéis individuais permanentemente
é uma variante a medir, não requisito: para `T` regressores, somar seus
slots a cada amostra acrescentaria `O(T)` leituras/somas à leitura do anel
global. Um registro sob demanda conserva o caminho rápido.

### 3.3 Regra de validade dos registros

Se um regressor alterado depende de y, a nova saída altera características
futuras de outros regressores. Mesmo um termo só de u pode mudar y e,
indiretamente, todos os termos realimentados. Portanto:

> **[dedução] Subtrair do anel global as contribuições antigas de um
> regressor e acrescentar as novas produz resultado exato somente enquanto
> a trajetória de y usada para construir todas essas contribuições permanece
> fixa.**

Exemplo mínimo: `y(k)=a·y(k−1)+b·u(k−1)`. Retirar `a` modifica `y(k)` e
todas as amostras posteriores. Uma mutação invalida os registros dinâmicos
gerados na trajetória antiga; a geração de trajetória impede reutilização
indevida. A edição local fornece triagem ou estado inicial, e a aceitação
exige nova simulação exata. Compartilhar prefixos idênticos da trajetória é
possível, mas não se presume que isso economize muito: alterações em
coeficientes podem afetar a primeira amostra simulada.

---

## 4. Representação compilada comum a treino e simulação

### 4.1 Grafo de características

[decisão] Compilar nós de fator identificados por `(variável, expoente
exato, powerMode)` e nós de produto identificados pela sequência de
fatores com seus atrasos e banco. Compartilhar o cálculo dos fatores entre
regressores, mas preservar a ordem de multiplicação de cada regressor para
comparação numérica com o núcleo. Atrasos permitem ler posições diferentes
do mesmo vetor de características. Termos duplicados vindos de JSON não
canonicalizado devem continuar multiplicados, como em `evaluate`.

No treino, u e y medidos são imutáveis: vetores de fatores e colunas de
regressores podem ser reutilizados entre candidatos. Na simulação, y
previsto muda com o modelo: só receitas e estruturas, não valores dos
fatores de y de uma trajetória anterior, podem ser compartilhadas.

**Memória:** uma Ψ de 16 000 linhas × 40 colunas em double ocupa
aproximadamente 5,12 MB, sem cópias, QR, ERR ou cache. Armazenar colunas
de todos os candidatos de todas as ilhas pode ser inviável. O cache deve
ter orçamento explícito, chave que inclua dataset, split, normalização,
modo de potência, fatores/atrasos, intervalo de linhas e revisão do
algoritmo. Expoentes contínuos quase iguais **não** compartilham coluna
exata. Hash é índice; colisões exigem comparação estrutural.

### 4.2 Intervalo de linhas

[código] Hoje o ajuste começa no maior atraso do próprio cromossomo.
Mudar o maior atraso muda `y`, o número de linhas e **todas** as colunas
alinhadas. Há duas alternativas legítimas, a comparar separadamente:

- **Semântica histórica:** reconstruir QR quando `md` mudar; a atualização
  local é exata apenas para candidatos com o mesmo intervalo.
- **Janela comum experimental:** começar todo ajuste em atraso global 40,
  como o plano de `06_CAPACIDADE_E_AJUSTE.md:184` propõe. Facilita
  comparação e reuso, mas é uma mudança do estimador atual e precisa de
  braço controle próprio.

---

## 5. Inserção, remoção e ajuste por QR

No intervalo fixo, a coluna candidata é `a=φ_j` (numerador) ou
`a=−y_medido·φ_j` (denominador). O intercepto participa da base. Se `Q`
for uma base ortonormal das colunas aceitas e `r=y−Aθ`, então

```
q = a − Q(Qᵀa)
ΔSSE = (qᵀr)² / (qᵀq), se qᵀq for confiável
```

[dedução] Essa é a redução de SSE de mínimos quadrados de um passo por
adicionar **uma** coluna, mantendo linhas e as demais colunas fixas.
Não é redução de RMSE livre, de fitness completo nem garantia para
adições simultâneas. Para posto quase deficiente, a previsão fica instável
e a coluna deve ser rejeitada ou submetida ao QR completo.

[decisão] Inserção usa ortogonalização incremental; remoção usa downdate
estável ou refatoração; troca de expoente, atraso, variável ou banco é
remoção seguida de inserção da coluna afetada. Comparar coeficientes,
posto e SSE com o QR completo. A equivalência exata com o solver atual
pode falhar em colunas dependentes por causa da ordem e do limiar de posto;
nesse caso, definir um solver de referência comum para ambos os braços ou
refatorar antes da aceitação. Não usar equações normais como substituto
inadvertido do QR.

O ERR e a razão de contribuição da entrada são calculados no avaliador
atual a partir de Ψ (`individual_evaluator.cpp:177–246,321–325`). Se a
proposta usar aproximações desses valores na triagem, a avaliação final
deve recalcular a semântica do fitness; otimizar apenas o QR não equivale a
otimizar todo o avaliador.

---

## 6. Sensibilidade da simulação para escolher mutações

### 6.1 Derivada local

Para `y=N/D` e `|D|` longe da guarda, uma perturbação satisfaz

```
δy(t) = [δN(t) − y(t)·δD(t)] / D(t)
```

Os `δN` e `δD` incluem contribuições **diretas** da mutação e
contribuições **indiretas** via saídas passadas. A diferenciação deve
atravessar características, produtos, atrasos, anéis e divisão. Uma
passagem reversa pela trajetória pode acumular gradientes de muitos
parâmetros sem repetir uma simulação completa para cada parâmetro;
precisa armazenar ou recomputar estados intermediários. Esta é uma
proposta de custo `O(n·F)` para um gradiente, **não** para avaliar
exatamente todos os novos regressores possíveis. Memória, checkpointing
e custo real são hipóteses a medir.

### 6.2 Triagem de movimentos

[decisão] Para cada indivíduo promissor:

1. Obter ajuste QR e trajetória livre **exatos**.
2. Gerar candidatos de inserção/remoção/troca por mutação estrutural,
   resíduos e diversidade. Não limitar a busca aos melhores scores locais.
3. Usar `ΔSSE`, correlação com resíduo e sensibilidade livre para
   classificar candidatos. Incluir custo estimado de avaliação e incerteza
   da aproximação; reservar uma fração das avaliações para exploração sem
   triagem, evitando viés irreversível.
4. Reajustar e simular integralmente os melhores `M` candidatos. **Apenas**
   o fitness exato e as regras de admissibilidade decidem aceitação.

O valor `M` e a fração de exploração precisam ser pré-fixados ou ajustados
com dados de treino apenas, dentro do orçamento comum. A ordem das
operações é importante: após um refit QR, todos os coeficientes podem
mudar. Um score de sensibilidade com θ congelado **não** prevê exatamente
esse efeito. Sua calibração deve ser medida por correlação de ranking e
taxa de candidatos promissores perdidos.

### 6.3 Refinamento de expoentes e coeficientes

Para `x≠0` em um ramo não inteiro da base assinada,
`∂g_p(x)/∂p = g_p(x)·ln|x|`. Em `x=0` e `p>0`, o limite desta derivada é
zero; `∂g/∂x` pode ser singular para `0<p<1`. Limitar a derivada usada
na **proposta de passo**, manter a avaliação exata e reduzir o passo se
ela falhar. Divisores próximos de zero também exigem rejeitar o passo
local ou voltar à busca discreta.

**Descontinuidade da base `hybrid`:** para `x<0`, em `p=2` vale `x²>0`,
mas para `p` não inteiro tendendo a 2 vale `−|x|^p<0`.
Consequentemente, não se pode passar por um inteiro par com uma otimização
suave de p. Manter expoentes inteiros pares como ramos discretos; refinar
expoentes não inteiros dentro do ramo permitido. `signed` contínuo é um
controle útil. Isso preserva expoentes reais sem fingir que o objetivo
`hybrid` é globalmente diferenciável.

**Ajuste QR × simulação:** o coeficiente ótimo por QR é função da
estrutura e de p; gradiente de simulação mantendo θ fixo é apenas uma
triagem. Para refino correto há duas opções: diferenciar também o refit
ou otimizar θ e p pelo erro de simulação a partir do QR, com passo de
confiança e aceitação exata. Comparar ambas com custo contado. Não
atribuir ganho de convergência ao adjunto sem esse controle.

---

## 7. Pseudocódigo do ciclo proposto

```
para cada indivíduo avaliado:
    obter colunas de treino do cache, materializando as ausentes
    ajustar θ e c por QR na janela definida
    simular exatamente pelos anéis globais em double
    calcular fitness completo e, se selecionado, sensibilidades

para gerar uma vizinhança dirigida:
    criar movimentos de inserção, remoção, troca e expoente
    estimar ΔSSE por coluna e efeito livre por sensibilidade
    escolher M promissores + uma cota de exploração aleatória
    para cada escolhido:
        atualizar ou refazer QR conforme posto e intervalo
        simular integralmente a nova trajetória
        recalcular todas as métricas e aplicar seleção existente
    invalidar registros dinâmicos da trajetória anterior se mudou o modelo
```

O caminho original JADE/multi-ilha pode permanecer como controle ou fonte
de diversidade. A vizinhança dirigida não deve ser creditada com ganho
de velocidade caso simplesmente consuma mais tempo por geração.

---

## 8. Métricas e controles para saber se houve ganho

Separar três efeitos:

| Efeito | Comparação | Medida decisiva |
|---|---|---|
| Simulação | anéis globais × `simulate` atual, mesmas estruturas, θ e dados | tempo por amostra, equivalência e divergência |
| Avaliação | cache/QR incremental × montagem/QR completos | tempo por candidato **incluindo** cache, ERR, cópias e falhas de posto |
| Convergência | JADE atual × JADE com vizinhança dirigida | melhor RMSE livre de validação por tempo total e por avaliações exatas |

Registrar também custo de compilar, aquecer cache, sensitividade,
refatorações, memória de pico, candidatos triados, qualidade do ranking
previsto, divergência, distribuição de K e número de expoentes distintos.
Relatar tempo frio e quente: um cache aquecido por modelos anteriores não
pode ser comparado a um controle iniciado do zero. Métricas por avaliação
não substituem qualidade por tempo total.

[decisão] Gates preliminares para auditoria, **não pré-registro final**:

- Equivalência do simulador em double: mesmo veredito de divergência e
  RMSE livre relativo dentro da tolerância justificada por arredondamento;
  diferenças de trajetória e de passo de divergência relatadas, não
  ocultadas por um único RMSE. Usar o R0/R1 do documento 08 como base.
- QR incremental: posto, SSE, θ e fitness final comparados ao refit no
  mesmo intervalo; se a ordem do solver alterar a solução em posto
  deficiente, contar e analisar separadamente.
- Ganho de simulação: usar inicialmente o limiar `≥2×` do R4 do documento
  08 para modelos grandes, mas não inferir ganho total da busca daí.
- Ganho de identificação: exigir melhoria da fronteira **qualidade × tempo**
  em validação sob orçamento igual, com sementes e configurações pareadas.
  Limiar numérico e protocolo devem ser fixados antes da execução.

Incluir ablações: só anéis; só cache; cache+QR; esses componentes com
triagem por sensibilidade; versão completa. Incluir `K` pequeno e grande,
polinomial/racional, grade 0,5 e expoentes contínuos, casos com termos
cruzados e `md` mutável. Um braço com janela de treino fixa deve ter seu
próprio controle, pois muda o estimador.

---

## 9. Fronteiras, riscos e escopo

- **Ponto fixo:** fora do primeiro gate. Se double não trouxer ganho útil,
  quantização não justifica a arquitetura para o objetivo declarado. A
  proposta do documento 08 para ponto fixo continua separada.
- **Semântica do núcleo:** preservar intercepto, banco do denominador,
  guarda de `1e−12`, aquecimento com y medido, limites de divergência e
  repetição da última saída. A ordem de soma altera arredondamento; não
  prometer identidade bit a bit.
- **Cache:** valores em treino podem ser compartilhados; valores da
  trajetória livre só com identidade de modelo, θ, dados e geração. Cache
  de fitness por hash estrutural deixa de ser suficiente se coeficientes
  refinados distintos forem preservados para a mesma estrutura, como já
  observado em `01_ARQUITETURA_ATUAL.md:127–134`.
- **Racionais:** um `ΔSSE` excelente no sistema pseudo linear pode piorar
  a simulação ou induzir denominador quase nulo. Regras de admissibilidade
  e validação livre continuam obrigatórias.
- **Dados:** seguir o pré-registro da Fase 0: treino/validação dos arquivos
  de estimação, normalização ajustada no treino, sem abrir teste WH/SB.
  O protótipo e os resultados devem ficar separados do motor congelado.
- **Carga e ferramentas:** não inferir disponibilidade de compilador da
  análise estática; verificar no momento de implementar. Não disputar CPU
  com protocolo em andamento. Respeitar a regra existente do projeto de
  não usar Python nesta linha de trabalho.

---

## 10. Pedido à agente revisora

1. **Matemática:** a regra de validade dos estados por regressor e a
   equivalência do anel global são corretas para termos cruzados,
   denominador e aquecimento? Há edição exata mais barata em algum caso?
2. **Custo:** os anéis individuais sob demanda preservam ganho? Estimar
   operações, memória e cache miss para K≈20–40, CT e WH; considerar que
   ERR pode dominar após otimizar QR.
3. **QR:** conferir a fórmula de `ΔSSE`, as condições de posto, a falta
   de pivoteamento e a influência da ordem das colunas no solver atual.
   Propor atualização/downdate numericamente defensáveis.
4. **Objetivo racional:** medir o risco de o erro pseudo linear orientar a
   triagem na direção errada; propor guarda/controle sem consultar teste.
5. **Sensibilidade:** derivar a passagem reversa completa pela realização,
   incluindo fatores atrasados e divisão; estimar custo de memória,
   estabilidade numérica e ranking útil de mutações.
6. **Expoentes:** conferir a descontinuidade `hybrid` em inteiros pares,
   derivadas perto de zero e comportamento de `signed_continuous`.
7. **Experimental:** quais ablações e limiares distinguem ganho por amostra,
   ganho por avaliação e convergência? Como manter comparação justa diante
   de cache quente, janela de treino e diferentes K?
8. **Novidade:** localizar trabalhos prévios próximos à combinação de
   estados transpostos, seleção incremental de termos e sensibilidade
   livre; delimitar com honestidade qualquer contribuição publicável.
9. **Recomendação:** priorizar, reduzir ou rejeitar esta primeira investida
   conforme plausibilidade de ganho na identificação atual. Não recomendar
   implantação em ponto fixo sem evidência específica.

## 11. Referências internas e antecedentes

- `08_REALIZACAO_TDF.md`: realização global e equivalência de simulação.
- `01_ARQUITETURA_ATUAL.md`: fluxo, ajuste de um passo versus simulação e
  risco do cache por hash estrutural.
- `06_CAPACIDADE_E_AJUSTE.md`: estudo de K até 40, janela comum e orçamento.
- `experiments/phase0/PHASE0_PREREG.md`: regras de dados e teste fechado.
- `experiments/results_phase0/SUMMARY_E3.md`: observações de validação E3;
  arquivo de trabalho ainda não versionado quando este texto foi criado.
- Billings e Chen, seleção ortogonal em NARX:
  https://www.southampton.ac.uk/~sqc/listP/IJC1989-50-5a.pdf
- Golub e LeVeque, projeção em mínimos quadrados separáveis:
  https://faculty.washington.edu/rjl/pubs/GolubLeVeque1979/GolubLeVeque1979.pdf
