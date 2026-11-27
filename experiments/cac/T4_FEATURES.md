# CAC T4: sinal de sobreajuste para os pesos β, δ, γ (validação)

Ramos de peso (β, δ, γ ↑) do T1 e do T2/T3: 800. Rótulo: ajuda se d < 0 (log RMSE fim ramo / controle). Atributos lidos no controle da mesma semente na geração da ação.

## Distribuição dos atributos nos controles (a cada 25 gerações)

| sistema | n | gapOS p10 / p50 / p90 | gapFR p10 / p50 / p90 | spp p10 / p50 / p90 | nReg p10 / p50 / p90 |
|---|---|---|---|---|---|
| cascaded_tanks | 1580 | 0.233 / 0.401 / 0.764 | 0.994 / 1.976 / 2.324 | 24.088 / 30.333 / 43.105 | 19.000 / 27.000 / 34.000 |
| wiener_hammerstein | 35 | -0.008 / 0.016 / 0.039 | 1.778 / 2.134 / 2.841 | 421.053 / 470.588 / 615.385 | 26.000 / 34.000 / 38.000 |
| silverbox | 35 | -0.104 / -0.049 / -0.031 | 0.500 / 0.960 / 1.441 | 432.432 / 457.143 / 533.333 | 30.000 / 35.000 / 37.000 |

## Efeito por sistema

| sistema | ramos | ajuda (d<0) | mediana d |
|---|---|---|---|
| cascaded_tanks | 520 | 321 | -0.068 |
| wiener_hammerstein | 140 | 2 | 0.410 |
| silverbox | 140 | 17 | 1.016 |

## Regra de limiar por atributo ("subir só se atributo ≥ t" ou "≤ t")

Ganho = soma de −d nos ramos em que a regra autoriza subir (o que o controlador teria ganho; nunca subir = 0). Validação cruzada deixando um sistema de fora: limiar escolhido em dois sistemas, aplicado no terceiro.

| atributo | regra (todos) | ramos autorizados | ganho total | ganho fora: CT | WH | SB | autorizados fora CT / WH / SB |
|---|---|---|---|---|---|---|---|
| gapOS | ≥ 0.400 | 306/800 | 33.321 | — | 0.000 | 0.000 | — / 0/140 / 0/140 |
| gapFR | ≥ 2.646 | 68/800 | 18.107 | — | -32.938 | 0.000 | — / 77/140 / 0/140 |
| spp | ≤ 91.000 | 520/800 | 31.624 | — | 0.000 | 0.000 | — / 0/140 / 0/140 |
| nReg | ≤ 27.000 | 372/800 | 25.111 | — | -3.124 | -11.677 | — / 7/140 / 14/140 |

## Dentro do CT: efeito por tercil de gapOS e por peso

| peso | tercil gapOS (faixa) | ramos | ajuda | mediana d |
|---|---|---|---|---|
| beta | -0.055–0.364 | 64 | 46 | -0.112 |
| beta | 0.364–0.573 | 64 | 46 | -0.110 |
| beta | 0.573–1.165 | 72 | 51 | -0.130 |
| delta | -0.055–0.364 | 52 | 34 | -0.082 |
| delta | 0.364–0.573 | 52 | 36 | -0.124 |
| delta | 0.573–1.165 | 56 | 40 | -0.208 |
| gamma | -0.055–0.364 | 52 | 21 | 0.171 |
| gamma | 0.364–0.573 | 52 | 19 | 0.102 |
| gamma | 0.573–1.165 | 56 | 28 | 0.016 |
