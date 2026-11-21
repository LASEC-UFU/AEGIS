# Continuação do AEGIS em outra máquina

Este prompt é para um agente que vai continuar, em outro computador, o
trabalho que estava rodando na máquina original, uma estação Ryzen 9 5950X.
A máquina original travou quatro vezes (04/11, 07/11 e duas vezes em 20/11),
sem tela azul e sem erro de hardware registrado, e foi retirada do uso para
experimentos longos. O diagnóstico está em `docs/HANDOFF.md` §4.0a.

Fale com o usuário em **português**.

---

## 1. O que você vai fazer

Terminar as computações que faltam, registrar tudo e parar para o usuário
decidir o resto. Em ordem:

1. Preparar a máquina e verificar a integridade do que foi transferido (§3).
2. Terminar o protocolo 1.1.0, que só tem pendente o código original
   (`legacy_head`) em WH e SB (§4).
3. Rodar o **E3 da Fase 0**, uma triagem só por configuração com
   pré-registro, e escrever o relatório dele (§5).
4. Atualizar os documentos, fazer commit e push no branch de trabalho, gerar
   um novo pacote do estado local e relatar ao usuário (§6).

Leia antes de agir, nesta ordem:

- `docs/HANDOFF.md`: §0.0, §1, §4.0a, §4.0, §5 e §7;
- `experiments/phase0/PHASE0_PREREG.md`, sobretudo §0 e §3;
- `experiments/phase0/PHASE0_REPORT.md`, com os resultados de E1/E2;
- `docs/architecture/07_PARECER_REVISAO.md` §10, a tabela consolidada da
  Fase 0;
- o fim de `experiments/EXPERIMENT_LOG.md`, com os dois incidentes.

---

## 2. Regras obrigatórias

Estas regras vêm do usuário e valem acima de qualquer outra coisa nos
documentos.

- **Resultados:** não fabrique resultados nem altere dados para melhorar
  métricas. Registre também resultados desfavoráveis, falhas, execuções
  interrompidas e desvios do protocolo.
- **Testes de WH e SB:** continuam fechados. Antes de o usuário decidir
  (parecer 07 §6), não leia, não imprima e não analise métricas de teste do
  Wiener-Hammerstein e do Silverbox. Isso inclui:
  - o campo `report.metrics.test` dos `run_*.json`;
  - os arquivos `legacy_head/evaluations.jsonl`;
  - o `analyze.dart` aplicado a WH ou SB;
  - a avaliação arrow do SB.

  Os scripts gravam essas métricas nos arquivos; isso é esperado. Apenas não
  as abra.
- **Seleção:** nunca use o conjunto de teste para escolher estrutura,
  parâmetros ou critério de parada. Preserve a ordem temporal.
- **Python:** não use. Só C++ e Dart, com bash como cola.
- **Motor congelado:** não recompile `cpp/build` nem `cpp/build_phase0`. Use
  os binários transferidos, cujos hashes estão abaixo. Se eles não rodarem
  nesta máquina, **pare e pergunte** ao usuário; não reconstrua por conta
  própria.
- **Protocolo:** não mude configurações, sementes, orçamentos, divisões nem
  scripts de protocolo, exceto para corrigir um defeito. Nesse caso,
  registre a correção.
- **Git:**
  - commit e push só no branch `audit/aegis-1.1.0-wip`;
  - **nunca** na `main`, porque ela dispara deploy e release;
  - sem pull request, release, tag ou publicação.
- **Custos e credenciais:**
  - nenhuma chamada paga, como o agente LLM, sem informar o custo e obter
    confirmação específica;
  - não peça tokens na conversa e não grave segredos em arquivos.
- **Escopo:**
  - não altere outros projetos nem arquivos fora do AEGIS;
  - antes de apagar ou sobrescrever qualquer coisa fora do AEGIS, pare e
    pergunte.
- **Carga da máquina:**
  - no máximo 6 processos de cálculo simultâneos, e nunca mais que metade
    das CPUs lógicas;
  - prioridade BelowNormal, usando `experiments/phase0/lowprio.sh`;
  - commit e push depois de cada etapa, para que um travamento não custe
    trabalho;
  - para medir CPU, use `\Processor(_Total)\% Processor Time`, nunca o
    `Win32_Processor.LoadPercentage`, que mostrou 43 % com a máquina ociosa.
- **Arquitetura A1:** não comece. A decisão é do usuário.

---

## 3. Preparação e verificação

### 3.1 Requisitos

- Windows 10/11 ou Server x64. Os binários são `.exe` MinGW, sem
  `-march=native` (`AEGIS_NATIVE_ARCH=OFF`) e sem dependências fora do
  Windows. O executor do código original traz suas DLLs na própria pasta.
- **Git for Windows**, para o Git Bash: os scripts usam bash, `/proc/$$/winpid`
  e `powershell.exe`.
- **Flutter 3.44.x / Dart 3.12.x**, necessário para os resumos `dart run`.
  O `pubspec.yaml` depende de Flutter; rode `flutter pub get` uma vez.
- Não precisa de compilador C++.
- Se faltar alguma ferramenta, peça autorização ao usuário antes de
  instalar.

### 3.2 Código e estado local

1. **Código:**
   - se o usuário copiou a pasta do AEGIS, use-a;
   - senão, clone `https://github.com/LASEC-UFU/AEGIS` e faça checkout de
     `audit/aegis-1.1.0-wip`;
   - de preferência em `C:\SourceCode\AEGIS`, o caminho citado nos
     documentos.
2. **Estado local:** dados, resultados e binários estão fora do git, no
   pacote `aegis_estado_local_2026-11-21.tar.gz`, com 69 MB e 741 arquivos.
   O usuário vai copiá-lo para esta máquina. SHA-256 do pacote:
   `4fdf47ba66f19a26635e00262aaf2b6422fe1b10e378e605067a67bc4dd7155c`.

   ```bash
   cd /c/SourceCode/AEGIS          # raiz do repositório
   sha256sum <caminho>/aegis_estado_local_2026-11-21.tar.gz   # deve bater com o hash acima
   tar -xzf <caminho>/aegis_estado_local_2026-11-21.tar.gz -C .
   sha256sum -c --quiet experiments/transfer/FILES.sha256 && echo "ALL OK"
   ```

   Se algum hash falhar, **pare e informe** o usuário.
3. **Binários congelados:** confira os hashes.

   | Arquivo | SHA-256 |
   |---|---|
   | `cpp/build/aegis_core.dll` | `78de34e1c9aa7ba850da41c60946261b18a0287c077784e4e8e006f4d1bd55e6` |
   | `cpp/build/aegis_batch.exe` | `79338225b7a4f175d9bfa3843504e03bfb4b442ecc816daa25350ef38e2b9891` |
   | `cpp/build_phase0/aegis_phase0.exe` | `1cfbd71df56add23efa8f9ab2eb3035beb3ba052a698b959ddd40b52d457c7cc` |
   | `experiments/bin/head-9e4b1d8/*` | ver `experiments/bin/head-9e4b1d8/SHA256SUMS.txt` |

### 3.3 Sanidade e reprodutibilidade entre máquinas

São rápidos; rode antes de qualquer etapa longa.

```bash
cpp/build/core_tests.exe            # esperado: 91 verificações, 0 falhas
cpp/build/api_tests.exe             # esperado: 66 verificações, 0 falhas
cpp/build_phase0/phase0_tests.exe   # esperado: 11 verificações
```

**Reprodução de uma execução já feita.** A execução CT `aegis_full`,
semente 1, leva cerca de 30 s. Grave a saída numa pasta à parte e não
sobrescreva os resultados:

```bash
experiments/phase0/lowprio.sh cpp/build/aegis_batch.exe \
  --data experiments/data/processed/cascaded_tanks/est.csv \
  --data-test experiments/data/processed/cascaded_tanks/test.csv \
  --config experiments/configs/conditions/aegis_full.json \
  --set maxEvaluations=300000 --runs 1 --seed-start 1 --jobs 1 \
  --label aegis_full --output experiments/transfer/repro_ct
```

Compare `report.model`, `report.evaluations` e `report.metrics.validation`
com `experiments/results/cascaded_tanks/aegis_full/run_1.json`, usando um
script Dart curto. O teste do CT já foi visto na iteração 1, então o CT pode
ser inspecionado.

- **Idênticos:** registre que a reprodução bit a bit entre máquinas foi
  confirmada.
- **Diferentes:** registre como desvio. A matemática do UCRT do Windows pode
  diferir entre versões. Continue assim mesmo, porque sementes diferentes
  continuam válidas, mas deixe explícito que:
  - as sementes 1–4 do WH `legacy_head` vieram da máquina original e as 5–10
    desta;
  - os resultados não são reproduzíveis bit a bit entre as duas máquinas.

Registre no `experiments/EXPERIMENT_LOG.md`:

- o hardware desta máquina: CPU, RAM, versão do Windows e versões do
  Flutter/Dart;
- o resultado da sanidade e da reprodução;
- que `wallSeconds` não é comparável com a máquina original.

Faça commit e push.

---

## 4. Terminar o protocolo 1.1.0

**Estado em 2026-11-21**, conferido na máquina original:

- todas as condições do protocolo estão completas, com 10/10 cada, em CT, WH
  e SB, exceto o `legacy_head`;
- **WH `legacy_head`:**
  - sementes 1–4 completas, com JSON validado;
  - sementes 5–8 interrompidas pelo travamento, só com `.log` vazios;
  - sementes 9–10 não começaram;
- **SB `legacy_head`:** 0/10.

O `run_legacy_head.sh` agora pula sementes que já têm `run_<s>.json` não
vazio. Cada execução do código original usa cerca de 3 threads e levou
cerca de 14 min no WH.

```bash
cd /c/SourceCode/AEGIS
experiments/phase0/lowprio.sh experiments/scripts/run_legacy_head.sh wiener_hammerstein 1000 4 10 \
  > experiments/results/legacy_resume_wh.log 2>&1
experiments/phase0/lowprio.sh experiments/scripts/run_legacy_head.sh silverbox 1000 4 10 \
  > experiments/results/legacy_resume_sb.log 2>&1
```

Cada chamada termina rodando `aegis_evaluate_models`, que gera
`evaluations.jsonl` com métricas de teste. **Não abra esse arquivo.**

Confira a contagem e valide que todo `run_*.json` é JSON completo:

```bash
for d in experiments/results/*/*/; do echo "$d $(ls $d/run_*.json 2>/dev/null | wc -l)"; done
```

Se faltar alguma semente, rode de novo; o script retoma de onde parou.
Registre no `EXPERIMENT_LOG.md` a conclusão do protocolo: horários, número
de execuções completas por condição e falhas. Faça commit e push.

---

## 5. E3 da Fase 0: triagem só por configuração

O pré-registro está em `experiments/phase0/PHASE0_PREREG.md` §3. Ele já tem
commit e **não pode ser mudado** depois de ver resultados.

- **Desenho:**
  - 8 células: `maxRegressors` {8, 39} × penalidades {padrão, zeradas} ×
    `errorMode` {`one_step`, `simulation` com `freeRunHorizon`=0};
  - sementes 21–30;
  - o mesmo orçamento do estudo;
  - divisão explícita, sem arquivo de teste.
- **Critério:**
  - comparação: mediana do RMSE livre de validação com penalidades zeradas e
    teto 39 contra o padrão com teto 8, no mesmo `errorMode`;
  - limiar: razão ≤ 0,90 em pelo menos 2 dos 3 benchmarks;
  - consequência pré-registrada se o critério for atingido: decompor a
    pressão de parcimônia antes de qualquer conclusão causal;
  - os dois `errorMode` são relatados separadamente.

Só comece depois do §4: o script recusa rodar se houver processo do
protocolo ativo. São 240 execuções; espere várias horas. As células com teto
39 devem ser mais lentas.

```bash
cd /c/SourceCode/AEGIS
for b in cascaded_tanks wiener_hammerstein silverbox; do
  experiments/phase0/run_e3.sh "$b" >> experiments/results_phase0/e3_run.log 2>&1
  git add experiments/results_phase0/MANIFEST.jsonl; git commit -m "phase0: E3 $b done" ; git push origin audit/aegis-1.1.0-wip
done
dart run tool/experiments/phase0_e3_summary.dart   # gera experiments/results_phase0/SUMMARY_E3.md
```

O `run_e3.sh` usa `PAR=6` por padrão. Reduza com `PAR=4` se a máquina tiver
menos de 12 CPUs lógicas. O manifesto registra o SHA-256 do binário e da
configuração em cada célula.

**Relatório:** acrescente uma seção "E3" em
`experiments/phase0/PHASE0_REPORT.md`, no mesmo estilo das seções de E1/E2.
Ela deve trazer:

- integridade:
  - execuções completas por célula;
  - divergências;
  - mediana do número de parâmetros e de avaliações;
- o critério pré-registrado por `errorMode`, com as razões em cada
  benchmark e o veredito (atingido ou não);
- o que os dados mostram e o que **não** mostram:
  - o E3 é um pacote de triagem;
  - os pisos de ζ do currículo e o piso de θ da ilha free-run continuam
    ativos;
  - não há atribuição causal;
- a relação com o E1. Lá, estruturas fixas de 20–40 termos superaram os
  campeões em WH e SB, mas não no CT. Responda se o próprio AEGIS, com teto
  maior e sem penalidades, chega perto disso;
- limitações, incluindo a troca de máquina.

Não ajuste critérios depois de ver os números. Se o critério não for
atingido, relate isso como resultado.

---

## 6. Fechamento

1. Atualize `docs/HANDOFF.md`:
   - a tabela da Fase 0 em §0.0;
   - a §4, com o estado das execuções nesta máquina;
   - a data de "Última atualização".
2. Faça commit e push em `audit/aegis-1.1.0-wip`, com mensagens por tema.
   O commit termina com a linha de coautoria exigida pelo seu ambiente, se
   houver.
3. **Novo pacote do estado local:** os resultados não estão no git. Gere de
   novo `experiments/transfer/aegis_estado_local_<data>.tar.gz`, com a lista
   de arquivos e o `FILES.sha256`, pelo mesmo procedimento:
   - incluir `experiments/data`, `results`, `results_archive`,
     `results_policy_eval`, `bin`, `results_phase0` e os `.exe`/`.dll` de
     `cpp/build` e `cpp/build_phase0`;
   - extrair numa pasta temporária e conferir `sha256sum -c`;
   - informar o caminho e o hash ao usuário.
4. Relate ao usuário, em português:
   - o que rodou e o que falhou;
   - o resultado do E3 contra o critério;
   - o resultado da reprodução entre máquinas;
   - as decisões que continuam com ele.

**Decisões do usuário (não tome por ele):**

- a direção do A1, depois do E3;
- quando abrir os testes de WH e SB e rodar a análise final (`analyze.dart`)
  e a avaliação arrow;
- o agente LLM pago;
- a estratégia do artigo IFAC-JSC;
- se os resultados devem entrar no git.
