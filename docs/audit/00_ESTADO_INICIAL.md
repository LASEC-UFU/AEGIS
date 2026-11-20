# AEGIS — Registro do estado inicial (antes de qualquer alteração)

Data do registro: 2026-11-20 (horário local da máquina).

## 1. Repositório

| Item | Valor |
|---|---|
| Pasta raiz | `C:\SourceCode\AEGIS` |
| Remoto | `origin = https://github.com/LASEC-UFU/AEGIS.git` |
| Branch | `main`, sincronizada com `origin/main` |
| Commit HEAD | `9e4b1d8 fix: remove cpp/build_win/ from git tracking to fix CI build` |
| Árvore de trabalho | **limpa** (`git status` sem alterações, sem stash) |
| Arquivos rastreados | 173 |
| Arquivos não rastreados/ignorados presentes | nenhum (`.dart_tool/`, `build/`, `cpp/build*` inexistentes) |

O único efeito colateral de `flutter pub get` (executado na auditoria) foi regenerar
`windows/flutter/generated_plugin_registrant.{cc,h}` e `generated_plugins.cmake` com
quebras de linha LF; o conteúdo é idêntico (`git diff --stat` vazio). Esses arquivos são
gerados automaticamente pelo Flutter.

## 2. Instância em execução

Não havia processo do aplicativo AEGIS em execução. Estavam ativos apenas os processos
da extensão Dart/Flutter do VS Code (`flutter daemon`, `dart language-server`,
`dart tooling-daemon`, `dart devtools`). Nenhum deles foi encerrado ou reiniciado.

## 3. Ambiente

| Item | Versão |
|---|---|
| SO | Windows Server 2025 Standard Evaluation 10.0.26100 |
| CPU | AMD Ryzen 9 5950X, 16 núcleos / 32 threads |
| RAM | 64 GB |
| Flutter | 3.44.2 (stable, rev c9a6c48423) |
| Dart | 3.12.2 |
| C++ | g++ 16.2.0 (MSYS2 UCRT64), CMake 4.4.3, Ninja (MSYS2) |
| MSVC / Visual Studio | **não instalado** → `flutter build windows` não é possível nesta máquina |
| Emscripten | **não instalado** → build WASM não é possível nesta máquina |
| Python | 3.12.5 com numpy 2.5.4 (sem scipy/pandas/matplotlib) |

## 4. Linha de base de verificação (código original, sem alterações)

| Verificação | Comando | Resultado |
|---|---|---|
| Análise estática Dart | `dart analyze lib test` | sem problemas |
| Testes Flutter/Dart | `flutter test` | **8 aprovados, 3 reprovados** |
| Build C++ (MinGW, Release) | `cmake -S cpp -B cpp/build -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build cpp/build` | compila (1 aviso: `#pragma comment` ignorado pelo GCC) |
| Testes C++ | `cpp/build/core_tests.exe` | aprovado (cobre normalizador e invariantes básicos do DE) |
| Runner em lote | `aegis_batch.exe --data Benchmarks/WH_estimation_uy.csv --runs 2 --max-gen 50` | **0/2 execuções** (`aegis_load_data() failed`) |
| Velocidade | `test_harness.exe` com WH (8192 amostras), 3 ilhas × 50 | ~17 gerações em 10 s (≈0,6 s/geração) |

Testes reprovados na linha de base:

1. `agent_mode_test.dart: engine supervisor defaults to local and can be disabled` — espera o nome
   `Agente local adaptativo`; o código retorna `Agente local (UCB1)` (teste desatualizado).
2. `local_adaptive_agent_test.dart: acts immediately on severe free-run divergence` — espera o
   prefixo `Agente local:`; o código usa `Agente local UCB1:` (teste desatualizado).
3. `local_adaptive_agent_test.dart: parameter cooldown prevents repeated changes every window` —
   espera 2 ações em 3 janelas; o código aplica 3. **Bug real**: sinais "severos" ignoram o
   cooldown por parâmetro.

## 5. Dados presentes

| Arquivo | Linhas | SHA-256 | Proveniência |
|---|---|---|---|
| `Benchmarks/WH_estimation_uy.csv` | 8192 amostras + cabeçalho (`u,y`) | `13925d266c85f46737c5d528b9813bb6c073d98f37bb59090020e76b9997c491` | **não documentada**; o benchmark Wiener–Hammerstein oficial tem 188 000 amostras |
| `results/aegis_WHmodel_2026-06-16T09-22-12.json` | — | — | exportação de 1 execução pela UI (sem semente, sem configuração, sem parâmetros de normalização) |

## 6. Sequência reversível adotada

Todas as alterações ficam na árvore de trabalho, sem commit. Como o HEAD estava limpo,
qualquer etapa pode ser desfeita com `git checkout -- <arquivo>` (arquivos alterados) ou
removendo os arquivos novos listados no relatório final. Os binários do código original
(HEAD) foram preservados em `experiments/bin/head-9e4b1d8/` para que a linha de base
possa ser reproduzida mesmo depois das correções.
