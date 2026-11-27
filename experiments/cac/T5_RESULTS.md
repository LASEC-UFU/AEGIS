# CAC T5: v4 contra o pacote A1 sem agente e contra o v3 (validação)

d = log(RMSE agente / RMSE referência), pareado por semente; negativo = melhor. Principal: campeão no fim da busca. Secundária: validação final reportada.

| sistema | comparação | n | mediana d fim | melhores / piores | sign p | mediana d final | melhores / piores (final) | ações aceitas (mediana) |
|---|---|---|---|---|---|---|---|---|
| cascaded_tanks | cac4 vs none | 10 | -0.151 | 8 / 2 | 0.109 | 0.329 | 2 / 8 | 17 |
| cascaded_tanks | cac vs none | 10 | -0.216 | 8 / 1 | 0.039 | 0.188 | 4 / 5 | 16 |
| cascaded_tanks | cac4 vs cac | 10 | 0.081 | 5 / 5 | 1.000 | 0.300 | 4 / 6 | 17 |
| wiener_hammerstein | cac4 vs none | 5 | 0.205 | 1 / 4 | 0.375 | 0.131 | 0 / 5 | 3 |
| wiener_hammerstein | cac vs none | 5 | 0.006 | 2 / 3 | 1.000 | 0.053 | 1 / 4 | 5 |
| wiener_hammerstein | cac4 vs cac | 5 | 0.124 | 1 / 4 | 0.375 | 0.086 | 0 / 5 | 3 |
| silverbox | cac4 vs none | 5 | 0.007 | 2 / 3 | 1.000 | 0.017 | 1 / 4 | 2 |
| silverbox | cac vs none | 5 | 0.031 | 1 / 4 | 0.375 | 0.050 | 1 / 4 | 7 |
| silverbox | cac4 vs cac | 5 | -0.058 | 3 / 2 | 1.000 | -0.019 | 4 / 1 | 2 |
