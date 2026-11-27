# CAC T6: v4.1 + postProcessGuard contra o pacote A1 + postProcessGuard (validação)

d = log(RMSE agente / RMSE referência), pareado por semente; negativo = melhor. Principal: campeão no fim da busca. Secundária: validação final reportada.

| sistema | comparação | n | mediana d fim | melhores / piores | sign p | mediana d final | melhores / piores (final) | ações aceitas (mediana) |
|---|---|---|---|---|---|---|---|---|
| cascaded_tanks | cac41_guard vs none_guard | 10 | -0.184 | 8 / 2 | 0.109 | 0.604 | 3 / 7 | 3 |
| cascaded_tanks | none_guard vs none | 10 | 0.000 | 0 / 0 | 1.000 | 0.000 | 4 / 0 | 0 |
| wiener_hammerstein | cac41_guard vs none_guard | 5 | 0.000 | 0 / 0 | 1.000 | 0.000 | 0 / 0 | 0 |
| wiener_hammerstein | none_guard vs none | 0 | — | 0 / 0 | 1.000 | — | 0 / 0 | — |
| silverbox | cac41_guard vs none_guard | 5 | 0.000 | 0 / 0 | 1.000 | 0.000 | 0 / 0 | 0 |
| silverbox | none_guard vs none | 0 | — | 0 / 0 | 1.000 | — | 0 / 0 | — |
