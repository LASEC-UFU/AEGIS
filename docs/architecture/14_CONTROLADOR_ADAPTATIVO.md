# 14 — Controlador adaptativo de convergência (CAC)

Data: 2026-11-26. Situação: **desenho para implementação**, pedido pelo
usuário em 2026-11-26:

> "criar uma ou a combinação destes sistemas para que ele a cada conjunto de
> iterações mude estes parâmetros de forma que para cada situação ele extraia
> o máximo da convergência, sendo capaz de estimar o número de iterações
> futuras que ele vai agir novamente" — "ele tem que ser capaz de atuar em
> todos os parâmetros que o sistema dispõe".

Etiquetas: **[código]** conferido; **[desenho]** escolha deste documento;
**[hipótese]** a medir.

---

## 1. O que existe hoje [código]

| Agente | Decide | Quando age | Parâmetros |
|---|---|---|---|
| UCB1 (`LocalAdaptiveAgent`) | heurísticas geram candidatos; UCB1 escolhe entre braços (parâmetro, direção) | a cada 25 gerações, fixo | 8, escritos à mão |
| Fuzzy (`FuzzyPolicyAgent`, `expert-v2`) | regras Takagi–Sugeno de ordem zero | a cada ciclo fixo | 8, escritos à mão |
| LLM (`LlmAgent`) | modelo de linguagem, uma ação por consulta | a cada `consultEvery` gerações, fixo | todos os do esquema, com custo |

Limitações em relação ao pedido:
1. **Intervalo fixo:** nenhum agente estima quando voltar a agir.
2. **Cobertura parcial:** os agentes locais tocam metade dos parâmetros.
3. **Sem contexto no aprendizado:** o UCB1 aprende "qual braço paga" sem
   distinguir a situação da busca.
4. **Recompensa contra tendência ingênua:** o efeito é medido contra a
   variação do mesmo número de gerações antes da ação, não contra uma
   previsão da convergência.
5. No estudo 1.1.0 (CT, sementes 1–20) **nenhum agente mostrou ganho**
   (parecer 07 §5). O CAC é uma hipótese nova, não uma melhoria garantida.

## 2. Ideia

Um controlador por **blocos de gerações**, que combina:
- **fuzzy** para diagnosticar a situação (interpretável);
- **bandido contextual** para aprender qual ajuste paga em cada situação;
- **modelo de convergência** para estimar quando agir de novo e para medir
  o efeito de cada ação contra uma previsão.

```
a cada bloco:
  1. observar o snapshot (só treino e validação)
  2. atualizar o modelo de convergência L(g) do campeão
  3. se houver ação pendente cujo horizonte terminou: recompensa =
     ganho observado − ganho previsto sem a ação
  4. classificar a situação (fuzzy)
  5. escolher ação em TODOS os parâmetros do esquema (bandido contextual,
     com prior das regras fuzzy) ou "não agir"
  6. estimar h = número de gerações até agir de novo
  7. registrar decisão, situação, previsão e h
```

## 3. Espaço de ações: todos os parâmetros [desenho]

- Lido em tempo de execução de `aegis_get_action_schema()`: nome, faixa,
  passo máximo, inteiro ou não, *cooldown*, efeito sobre o orçamento.
- **Ações por parâmetro:** {−passo, +passo}, com passo = ½ do passo máximo
  do esquema (arredondado para inteiros), mais o evento `triggerRestart`.
- **Ação nula:** "não agir" é um braço como os outros.
- **Máscara de inércia:** parâmetros sem efeito na configuração atual não
  são oferecidos. Exemplo: `freeRunPenalty` e `freeRunHorizon` com
  `errorMode` = `simulation`, lido do `search` do snapshot.
- **Parâmetros de orçamento** (`stagnationLimit`) só entram se a execução
  permitir (`allowBudgetActions`). No A1, o orçamento em avaliações é fixo
  e igual entre braços, então o CAC não pode ganhar gastando mais.

Com 16 parâmetros: até 33 braços por situação (2 × 16 + o nulo), mais o
reinício.

## 4. Situações (contexto) [desenho]

Variáveis fuzzy (as do `expert-v2` e duas novas):

| Variável | Definição | Termos |
|---|---|---|
| `stag` | estagnação do campeão / limite de fase | baixo, médio, alto |
| `sr` | taxa de sucesso das tentativas | baixa, média, alta |
| `div` | estruturas únicas / população | baixa, média, alta |
| `gap` | (RMSE_val − RMSE_treino) / RMSE_treino | ok, alto |
| `adm` | campeão admissível (veto) | não, sim |
| `rate` | taxa de convergência ρ do modelo da §5, normalizada | parada, lenta, rápida |
| `phase` | fase do currículo | 0, 1, 2, 3 |

- **Situação** = termo de maior pertinência de `stag`, `sr`, `div` e
  `rate`, mais `adm` e `phase`. São no máximo 3·3·3·3·2·4 = 648 situações,
  mas poucas aparecem numa execução.
- Para compartilhar informação, cada braço tem uma estimativa global e uma
  por situação, combinadas por encolhimento: média ponderada pelo número de
  observações.

## 5. Modelo de convergência e o horizonte h [desenho]

Seja L(g) = log RMSE de simulação livre do campeão na validação (completa),
na geração g. É monótona não crescente, porque o campeão só troca para
melhor, salvo troca de pesos.

**Ajuste local:** nas últimas W gerações, regressão robusta de Theil–Sen de
L sobre g. Fornece:
- ρ = −dL/dg, taxa de convergência atual (≥ 0);
- σ_ρ, incerteza da taxa (dispersão das inclinações pareadas).

**Previsão sem ação:** L̂(g + h) = L(g) − ρ·h. É a linha de base
contrafactual.

**Horizonte até a próxima ação.** Agir cedo demais impede medir o efeito da
ação anterior; agir tarde desperdiça gerações num platô. Então:
1. **Horizonte de detecção** h_d: o menor h em que um efeito relevante
   (ε = 0,5 % de redução do RMSE, isto é ΔL = ε) se distingue da incerteza
   da previsão: h_d = (z·σ_L + ε) / max(ρ, ρ_min), com z = 1,
   σ_L o desvio dos resíduos do ajuste e ρ_min um piso para evitar divisão
   por zero.
2. **Horizonte de oportunidade:**
   - se a busca está rápida (ρ alta), o controlador espera: h_o = tempo
     previsto até a melhora relativa desacelerar abaixo de ε por bloco;
   - se está em platô (ρ ≈ 0), h_o = h_min.
3. **h = h_min se a busca está parada** (ρ·h_max < ε); senão h = h_d, elevado a
   pelo menos h_max/2 se a busca está rápida (ρ·h_min ≥ 4ε); sempre dentro de
   [h_min, h_max], com h_min = 10 e h_max = 200
   gerações, e em múltiplos de 5.
4. **Eventos antecipam h:**
   - campeão inadmissível;
   - divergência;
   - mudança de fase;
   - estagnação saltando de termo.
5. **Calibração:** cada decisão registra h e L̂(g + h). Ao fim, o erro de
   previsão |L(g + h) − L̂(g + h)| e a fração de antecipações por evento
   medem se a estimativa do número de iterações é útil.

## 6. Recompensa [desenho]

- Para a ação aplicada na geração g₀ com horizonte h:
  r = [L̂(g₀ + h) − L(g₀ + h)] / max(ε, |L̂(g₀ + h) − L(g₀)|).
- É o ganho além do previsto, em unidades do ganho previsto, cortado em
  [−1, 1].
- Mudança de fase ou reinício reflexo dentro da janela torna a observação
  inconclusiva, como hoje.
- O braço "não agir" recebe a mesma recompensa: se a busca seguiu o
  previsto, r ≈ 0.

## 7. Escolha da ação [desenho]

- **Thompson sampling** com prior gaussiano por braço e situação.
- **Prior vindo das regras fuzzy:** se uma regra do `expert-v2` dispara na
  situação com força μ e recomenda o braço, a média a priori recebe
  +0,2·μ; caso contrário, 0. Assim o controlador começa com o conhecimento
  especialista e aprende a corrigi-lo.
- **Restrições do núcleo continuam valendo:** faixa, passo, *cooldown*,
  orçamento. Uma ação rejeitada vira recompensa nula e não conta como
  tentativa.
- **Persistência entre execuções:** a tabela (situação, braço) pode ser
  salva e recarregada. **No A1 ela só pode ser treinada em execuções de
  desenvolvimento (CT e validação), nunca com teste.**

## 8. Validação antes do A1

1. **Testes unitários:** máscara de inércia, cobertura de todos os
   parâmetros do esquema, previsão de h em trajetórias sintéticas (platô →
   h_min; queda rápida → h maior), recompensa contra a previsão, persistência
   da tabela.
2. **Desenvolvimento** (sem teste): CT completo e WH/SB com orçamento
   reduzido. Mede ações aceitas e rejeitadas, distribuição de h, erro de
   previsão e custo de CPU.
3. Só depois disso o CAC entra no pré-registro do A1, congelado (código e
   tabela inicial) antes das execuções.

## 9. Posição no A1

- **Braço principal do A1:** pacote E3 sem agente.
- **Braço secundário:** A1 + CAC, com as mesmas sementes. A pergunta é se o
  CAC melhora o A1, em validação e depois em teste.
- O CAC não substitui a avaliação do A1. Se não mostrar ganho, isso é
  reportado como no estudo 1.1.0.

## 10. Convergência prematura × estagnação; cataclismo (acréscimo de 2026-11-26)

- **Convergência prematura:** a população colapsa cedo num ponto, por perda
  de diversidade (deriva genética). Remédio clássico: **cataclismo**
  (*cataclysmic mutation*, CHC, Eshelman 1991): reinicializar toda a
  população menos a elite.
- **Estagnação** (Lampinen e Zelinka, 2000): a população continua diversa,
  mas não progride. Reiniciar não ajuda; os ajustes úteis são passos de
  mutação e de cruzamento e a migração.
- **No núcleo:** `triggerRestart` passa a aceitar fração até 1,0. A elite de
  cada ilha (`elitismCount`) e o campeão global são sempre preservados, então
  1,0 é o cataclismo.
- **No CAC:**
  - o reinício parcial (30 %) é sempre um braço;
  - o **cataclismo** só é oferecido quando o diagnóstico é de convergência
    prematura: diversidade baixa, convergência parada e estagnação média ou
    alta.
  - O *cooldown* de 50 gerações do núcleo vale para os dois.
- **Correção da §5:** com a busca parada, o horizonte é h_min, ou seja, agir
  logo. A versão anterior da fórmula dava h_max nesse caso, e o teste
  unitário pegou.

## 11. Versão 2, depois da primeira rodada de desenvolvimento (2026-11-26)

**Resultado da v1** (CT, validação, sementes 21–23, pacote A1): pior que
sem agente nas 3 sementes. RMSE de validação 0,723 / 0,851 / 0,640 V contra
0,592 / 0,659 / 0,494 V, e campeões com K = 5. Causas medidas:
- horizonte mediano de 10 gerações, porque os platôs normais do campeão
  foram lidos como "parado";
- cerca de 150 ações por execução;
- exploração quase uniforme sobre mais de 30 braços, que subiu as
  penalidades que o pacote zera.

**Mudanças da v2:**

| | v1 | v2 |
|---|---|---|
| h_min / janela do modelo de convergência | 10 / 40 | **25 / 80** gerações |
| Variância a priori dos braços | 0,25 | **0,01**: ação só com evidência |
| Prior do braço "não agir" | 0 | **+0,25** |
| Escala do prior fuzzy | 0,2·μ | **0,4·μ** |
| Pesos do fitness | livres | **âncoras** = valores no início da execução (o pacote): mover para longe custa 0,15 de prior por passo; braço "voltar à âncora" com prior +0,1 |
| Tabela entre execuções | não usada | **treino** em sementes de desenvolvimento, carregada congelada na avaliação |

Todos os parâmetros do esquema continuam disponíveis. As âncoras só tornam
o afastamento do pacote uma decisão que precisa de evidência.

**Protocolo de desenvolvimento** (`experiments/perf/cac_dev.sh`, só CT, só
validação):
- treino nas sementes 31–40, com a tabela carregada de uma execução para a
  seguinte;
- avaliação nas sementes 21–23, com a tabela treinada congelada e sem
  tabela, comparadas ao A1 sem agente das mesmas sementes.
