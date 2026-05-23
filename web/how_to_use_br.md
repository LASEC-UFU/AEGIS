# Como Usar o AEGIS

> **Guia passo a passo para identificar modelos NARX usando o AEGIS.**

---

## 1. Carregando os Dados

1. Navegue até a aba **Data** na barra de navegação lateral (ou inferior no mobile).
2. Clique em **Load File** e selecione um arquivo `.csv`, `.tsv` ou texto separado por espaços contendo seus dados de série temporal.
3. Ative **Header row** se o arquivo tiver uma linha de nomes de colunas — o AEGIS a ignora automaticamente.
4. Clique no cabeçalho de cada coluna na tabela de preview para atribuí-la como **Entrada** ($u$) ou **Saída** ($y$). Pelo menos uma entrada e uma saída devem ser atribuídas antes de iniciar o motor.

### Requisitos dos Dados

| Requisito | Descrição |
|-----------|-----------|
| **Formato** | CSV, TSV, separado por espaços ou ponto-e-vírgula |
| **Colunas** | Pelo menos 2: uma entrada $u(k)$ e uma saída $y(k)$ |
| **Cabeçalho** | Opcional — o carregador detecta linhas numéricas automaticamente |
| **Tamanho** | Recomendado: 200–10.000 amostras |
| **Normalização** | Realizada automaticamente antes da identificação |

Os dados são divididos sequencialmente em **70% treino · 15% validação · 15% teste** após o carregamento.

---

## 2. Executando a Evolução

1. Vá para a aba **Evolution**.
2. Clique em **Start** para inicializar e começar a otimização por Evolução Diferencial.
3. O algoritmo evolui populações em múltiplas ilhas para encontrar a melhor estrutura de modelo NARX.
4. Use **Pause** / **Resume** para interromper sem perder o progresso. Use **Stop** para encerrar antecipadamente.

A barra de status mostra a geração atual, melhor fitness (BIC), $R^2$ e tempo decorrido.

### Seleção de Motor (automática)

| Plataforma | Motor utilizado |
|------------|----------------|
| Windows (com `aegis_core.dll`) | C++ multi-thread — mais rápido, mais diagnósticos |
| Windows (sem DLL) | Fallback Dart puro |
| Web / GitHub Pages | Dart puro |

---

## 3. Monitorando com o Painel do Agente

A aba **Agent** fornece visibilidade em tempo real do processo evolutivo.

### Grade de Indicadores

12 indicadores-chave são exibidos com cores semânticas (verde = saudável, amarelo = atenção, vermelho = problema):

| Indicador | O que significa |
|-----------|----------------|
| **Best BIC** | Melhor fitness composto encontrado (menor = melhor) |
| **RMSE Train / Val** | Erros de treino e validação |
| **$R^2$** | Coeficiente de determinação (1 = ajuste perfeito) |
| **Stagnation** | Gerações sem melhoria |
| **Diversity** | Dispersão da população — baixa indica convergência prematura |
| **Success Rate** | Fração de vetores trial aceitos nesta geração |

### Sliders de Ajuste

12 parâmetros podem ser ajustados **ao vivo** enquanto o motor está em execução:

| Parâmetro | Padrão | Quando alterar |
|-----------|--------|----------------|
| `mutationFactor` $F$ | 0.5 | Aumentar se a diversidade cair ou a estagnação crescer |
| `crossoverRate` $CR$ | 0.9 | Diminuir se $CR$ se aproximar de 1.0 com boa diversidade |
| `populationSize` $NP$ | 50 | Aumentar para problemas mais difíceis (maior custo por geração) |
| `elitismCount` | 2 | Aumentar para proteger as melhores soluções |
| `migrationInterval` | 20 | Diminuir para comunicação mais rápida entre ilhas |
| `migrationRate` | 0.1 | Aumentar se ilhas estagnam independentemente |
| `maxRegressors` | 8 | Aumentar se RMSE for alto e o modelo parecer simples demais |
| `maxExponent` | 3 | Aumentar para permitir termos mais não-lineares |
| `maxDelay` | 20 | Definir como a memória esperada do sistema (em amostras) |
| `complexityPenalty` | 1.0 | Aumentar em overfitting; diminuir em underfitting |
| `stagnationLimit` | 500 | Reduzir para parar mais cedo em runs claramente convergidos |
| `reinitializationRatio` | 0.1 | Aumentar para escapar de ótimos locais |

Clique no ícone de reset ao lado de qualquer slider para restaurar o valor padrão.

### Monitor de Ilhas

O gráfico de barras na parte inferior mostra o melhor fitness por ilha. Barras muito semelhantes indicam convergência; grande dispersão indica que o arquipélago ainda está explorando.

### Agente LLM (somente Windows)

Quando `aegis_core.dll` está presente e uma chave de API Anthropic está configurada, o **agente Claude** monitora o motor a cada 50 gerações e pode sugerir ajustes de parâmetros automaticamente. As sugestões aparecem no log de ajuste e são aplicadas imediatamente.

**Configuração (Windows):**

```powershell
# Opção A — variável de ambiente (sessão atual)
$env:ANTHROPIC_API_KEY = "sk-ant-..."

# Opção B — arquivo ao lado do executável
echo "sk-ant-..." > pasta_do_aegis.exe\anthropic_api_key.txt
```

O agente sugere no máximo uma mudança de parâmetro por chamada e apenas quando o motor apresenta sinais de estagnação, overfitting ou perda de diversidade. Quando o motor está saudável, ele responde `null` e não faz alterações.

---

## 4. Visualizando os Resultados

Após o término da evolução (ou após parar), vá para a aba **Results**:

1. **Equação do Modelo** — A expressão NARX identificada com coeficientes, ex.:
   ```
   y_hat(k) = (0.8732·y(k-1) + 0.1241·u(k-1)²) / (1 + 0.0034·y(k-1)·u(k-2))
   ```
2. **Métricas de Qualidade** — RMSE (treino / validação / teste), $R^2$, AIC, BIC, FPE, MDL, SSE
3. **Tabela ERR** — Cada regressor classificado por sua contribuição de Error Reduction Ratio
4. **Autocorrelação Residual** — Gráfico com bandas de confiança de 95% ($\pm 1.96/\sqrt{n}$). Barras dentro das bandas indicam resíduos de ruído branco (modelo adequado).
5. **Diagnósticos** (somente C++) — Estabilidade (BIBO), colinearidade (VIF), flags de overfitting / underfitting

---

## 5. Dicas e Boas Práticas

- **Comece com os valores padrão** — o motor é calibrado para uma ampla gama de sistemas; ajuste apenas se as métricas indicarem um problema.
- **Verifique a diversidade cedo** — se `phenotypicDiversity` cair abaixo de 0,01 nas primeiras 50 gerações, aumente `mutationFactor` ou `migrationRate`.
- **Observe RMSE_val vs RMSE_train** — se a diferença crescer (overfitting), aumente `complexityPenalty` ou diminua `maxRegressors`.
- **$R^2$ baixo após 200+ gerações** — tente aumentar `maxRegressors`, `maxDelay` ou `maxExponent`.
- **Na web** — o motor Dart puro é mais lento que a build C++. Para conjuntos de dados grandes (> 2.000 amostras) ou execuções longas, use a build Windows.
- **No Windows** — o agente LLM pode substituir o ajuste manual. Mantenha a chave de API configurada e monitore suas sugestões no log do console.

---

## 6. Sobre / Referência Técnica

A tela **About** renderiza o documento completo `IDENTIFICATION_PROCESS.md`, que cobre:

- O pipeline completo de identificação com detalhes matemáticos
- Descrições dos módulos C++ (normalizer, solver QR, refiner local, diagnósticos)
- A função de fitness composta e todas as penalidades
- Design da ponte FFI e modelo de execução WASM
- Fluxo do agente LLM e notas de segurança da chave de API

Ambas as telas suportam alternância de **modo escuro/claro** (ícone no canto superior direito) e são totalmente **selecionáveis** para copiar e colar.

---

<div align="center">

**AEGIS v2.0** · Guia de Como Usar

*Para detalhes técnicos, consulte a seção About.*

</div>
