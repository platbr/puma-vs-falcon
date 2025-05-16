# Slide 1: Título

## Falcon: Um Servidor HTTP Assíncrono para Ruby on Rails
### Maximizando Performance e Escalabilidade com Concorrência Eficiente
![falcon image](https://socketry.github.io/falcon/assets/logo.webp)

---

# Slide 2: O Desafio: Paralelismo no Ruby

* **Paralelismo no Interpretador Ruby Padrão (MRI/CRuby)**
    * Em resumo: **Não temos paralelismo real de threads executando código Ruby simultaneamente em múltiplos núcleos de CPU dentro de um mesmo processo.**

* **A Culpa é do GIL (Global Interpreter Lock)**
    * Uma trava no interpretador MRI que permite que **apenas uma thread execute código Ruby por vez** dentro de um processo.

---

# Slide 3: Entendendo o GIL

* **Por que o GIL existe?**
    * **Simplifica o design do interpretador:** Protege as estruturas de dados internas do Ruby contra acessos concorrentes, evitando corrupção e facilitando a manutenção.
* **O que o GIL NÃO faz:**
    * **Não torna o *seu* código Ruby automaticamente thread-safe.** Apenas as estruturas internas do interpretador são protegidas por ele.
* **Quando o GIL é liberado?**
    * Durante operações de **I/O (Entrada/Saída)**, como:
        * Acesso à rede (chamadas HTTP, APIs externas)
        * Operações de disco (leitura/escrita de arquivos)
        * Comunicação com banco de dados
    * Essa liberação permite que *outras threads Ruby* executem enquanto a original aguarda o I/O.
* **O Trade-off:**
    * Trocamos um paralelismo real (em CPU-bound tasks) por maior segurança e simplicidade no desenvolvimento do core do Ruby.
    * Muitos bugs de segurança são causados por *race conditions*. **Safety first!**

---

# Slide 4: Conceitos Essenciais: Processos

* **Processos**
    * **Definição:** A instância de um programa em execução. O sistema operacional (SO) gerencia cada processo como uma unidade de alocação de recursos e de escalonamento.
    * **Características Principais:**
        * **Isolamento total:** Cada processo tem seu próprio espaço de memória, garantindo que um não interfira diretamente no outro.
        * **Paralelismo real entre CPUs:** Processos diferentes podem executar simultaneamente em diferentes núcleos de CPU.
        * **Custo elevado:** A criação de processos e a troca de contexto (context-switch) entre eles são operações relativamente custosas para o SO.

---

# Slide 5: Conceitos Essenciais: Threads

* **Threads**
    * **Definição:** Uma unidade de execução *dentro* de um processo.
    * **Características Principais:**
        * **Compartilhamento de Recursos:** Threads de um mesmo processo compartilham o espaço de memória e outros recursos (arquivos abertos, sockets).
        * **Recursos Próprios:** Cada thread possui sua própria *stack* (pilha de execução) e recursos como registradores (CPU).
        * **Escalonamento:** Controlado pelo SO, interpretador ou VM.
        * **Leveza (Relativa):** Mais leves que processos, podem oferecer paralelismo real entre CPUs.
        * **Custo do Context-Switch:** Ainda considerável, embora menor que o de processos.
        * **Impacto do GIL no Ruby:** O GIL impede paralelismo real de threads Ruby em tarefas *CPU-bound*, limitando ganhos de performance com múltiplas threads nessas situações.

---

# Slide 6: Conceitos Essenciais: Fibers (O Futuro da Concorrência em Ruby?)

* **Fibers**
    * **Definição:** Uma unidade de execução **leve e cooperativa**, gerenciada totalmente no espaço do usuário (user-space).
    * **Características Principais:**
        * **Escalonamento Cooperativo:** Ao invés do escalonamento ser "preemptivo" (forçado pelo SO/VM), o desenvolvedor controla explicitamente quando uma Fiber suspende (`Fiber.yield`) e retoma (`fiber.resume`) sua execução.
        * **Overhead Mínimo:** Troca de contexto entre Fibers é extremamente rápida.
        * **Ideal para Padrões Reactor/Event-Loop:** Perfeitas para I/O assíncrono.
        * **Sem Preempção (Cuidado!):** Uma Fiber que não cede o controle voluntariamente pode bloquear todo o sistema assíncrono dentro daquele processo/thread (modelo cooperativo exige bom comportamento).
        * **Avanços no Ruby 3.0+:**
            * Adicionado suporte para **interceptação automática de chamadas de I/O bloqueantes**.
            * Isso permite que o scheduler de Fibers troque para outra Fiber enquanto uma aguarda o I/O, criando um modelo *async/await* fluido, **sem necessidade de alteração de código em gems existentes**.

---

# Slide 7: Cenário Tradicional: Puma e Unicorn (I/O Bloqueante)

### 1. Cada Requisição em uma Thread ou Processo

* **Puma (modelo baseado em Threads)**
    * Iniciado com um número configurável de threads.
    * Quando uma requisição HTTP chega, o Puma aloca uma das threads livres do seu pool.
    * Essa thread executa todo o ciclo da requisição Rails: middleware → controller → view → resposta.
    * Ao terminar, a thread volta para o pool, pronta para outra requisição.

* **Unicorn (modelo baseado em Processos)**
    * Faz *pre-fork* de N processos Ruby no início. Cada processo filho é uma VM Ruby completa com sua própria heap (memória).
    * Cada processo filho aceita e processa **uma requisição por vez**.
    * Executa todo o stack Rails e, ao terminar, fica pronto para a próxima.
    * Ao terminar, a processo volta pronto para outra requisição.

---

# Slide 8: O Gargalo Tradicional: Bloqueios em I/O

### 2. Bloqueios em I/O Limitam a Escala

* **Chamadas de I/O Bloqueantes são a Norma:**
    * A maioria das gems e drivers do ecossistema Rails (ActiveRecord, `net/http`, leitura de arquivos, Redis, etc.) realiza operações de I/O de forma **bloqueante** por padrão.
    * **O que isso significa?** Enquanto o Ruby está esperando pela resposta do banco de dados, do Redis, ou de uma API externa, a thread (no Puma) ou o processo (no Unicorn) fica **completamente parada, ociosa, sem fazer trabalho útil.**

* **Consequência Prática:**
    * Se uma query ao banco de dados demora 100 ms, aquela thread/processo permanece inativa por 100 ms.
    * Para manter uma alta taxa de requisições por segundo (RPS), é necessário aumentar o número de threads (Puma) ou processos (Unicorn).
    * **Limite do GIL:** No Puma, devido ao GIL, aumentar o número de threads além de um certo ponto traz retornos decrescentes ou até negativos para a performance geral, devido à contenção do GIL e overhead de troca de contexto.
    * É dificil encontrar um balanço adequado da quantidade correta de threads em um sistema que possua rotas com diferentes características (CPU bound x I/O Bound).

---

# Slide 9: Impactos do I/O Bloqueante na Arquitetura e Infra

### 3. Consequências para Arquitetura e Infraestrutura

* **Delegação frequente para Background Jobs:**
    * Operações demoradas (chamadas a serviços externos, e-mails, processamento pesado) são frequentemente movidas para *background jobs* (Sidekiq, GoodJob, etc).
    * **Objetivo:** Evitar que as threads/processos do servidor web fiquem bloqueadas, mantendo a capacidade de resposta para novas requisições.
    * **Desvantagem:** Introduz complexidade extra em orquestração, monitoramento e gerenciamento de falhas.

* **Escalabilidade "Invisível" para Métricas de CPU:**
    * Chamadas de I/O bloqueantes **não consomem CPU significativamente** enquanto estão esperando pela resposta.
    * Isso faz com que métricas de uso de CPU permaneçam baixas, mesmo que o sistema esteja sobrecarregado.
    * **Consequência:** O autoscaling baseado puramente em CPU falha em reagir ao verdadeiro volume de trabalho. É preciso adotar métricas de backlog de requisições, latência ou tamanho de fila para escalar de forma eficaz.

---

# Slide 10: Benchmarks: Falcon vs Puma

* **Objetivo:** Comparar o desempenho do Falcon (assíncrono com Fibers) com o Puma (síncrono bloqueante com Threads) sob diferentes cargas de I/O.
* **Ferramenta de Teste:** k6
* **Carga:** 30 VUs (Virtual Users) concorrentes
* **Duração:** 30 segundos por cenário de teste
* **Métricas Chave:**
    * Requests completadas em 30s (Throughput)
    * `http_req_duration` (Latência: avg, p95)

---

# Slide 11: Benchmark: Sem Bloqueio de I/O (k6-non-block.js - 30VU)

| Servidor | Threads | Reqs Completadas (30s) | `http_req_duration` (avg) | `http_req_duration` (p95) |
| :------- | :------ | :----------------------- | :------------------------ | :-------------------------- |
| **Falcon** | **1** | **11349**                | **79.36ms**               | **81.67ms**                 |
| Puma     | 1       | 12265                    | 80.91ms                   | 708.22ms                    |
| Puma     | 2       | 10969                    | 86.14ms                   | 775.12ms                    |
| Puma     | 3       | 10328                    | 89.75ms                   | 799.49ms                    |
| Puma     | 4       | 10059                    | 91.42ms                   | 797.09ms                    |
| Puma     | 5       | 9944                     | 92.15ms                   | 771.54ms                    |
| Puma     | 10      | 9600                     | 94.4ms                    | 656.56ms                    |
| Puma     | 30      | 8986                     | 100.21ms                  | 108.08ms                    |
| Puma     | 50      | 8910                     | 101.08ms                  | 107.44ms                    |

* *Observação: Falcon usa 1 processo/thread, mas múltiplas Fibers internamente.*
* *Neste cenário sem I/O, Puma com 1 thread tem um throughput ligeiramente maior, mas observe a latência p95, Ela só fica aceitável quando há pelo menos 1 thread por VU, e ainda assim com um tempo de resposta superior ao Falcon.*

---

# Slide 12: Benchmark: Com Bloqueio de I/O Leve (30ms I/O) (k6-block.js - 30VU)

| Servidor | Threads | Reqs Completadas (30s) | `http_req_duration` (avg) | `http_req_duration` (p95) |
| :------- | :------ | :----------------------- | :------------------------ | :-------------------------- |
| **Falcon** | **1** | **11535**                | **78.07ms**               | **94.71ms**                 |
| Puma     | 1       | 729                      | 1.37s                     | 12.42s                      |
| Puma     | 2       | 1343                     | 709.18ms                  | 6.42s                       |
| Puma     | 3       | 2107                     | 443.6ms                   | 3.91s                       |
| Puma     | 4       | 2661                     | 347.6ms                   | 2.98s                       |
| Puma     | 5       | 3113                     | 295.21ms                  | 2.51s                       |
| Puma     | 10      | 4954                     | 183.53ms                  | 1.29s                       |
| Puma     | 30      | 7712                     | 117.01ms                  | 122.35ms                    |
| Puma     | 50      | 7844                     | 114.94ms                  | 120.05ms                    |

* *Com apenas 30ms de I/O, a vantagem do Falcon começa a aparecer drasticamente.*

---

# Slide 13: Benchmark: Com Bloqueio de I/O Moderado (150ms I/O) (k6-block.js - 30VU)

| Servidor | Threads | Reqs Completadas (30s) | `http_req_duration` (avg) | `http_req_duration` (p95) |
| :------- | :------ | :----------------------- | :------------------------ | :-------------------------- |
| **Falcon** | **1** | **5815**                 | **155.17ms**              | **157.71ms**                |
| Puma     | 1       | 211                      | 5.04s                     | 31.01s                      |
| Puma     | 2       | 391                      | 2.5s                      | 19.09s                      |
| Puma     | 3       | 561                      | 1.69s                     | 15.01s                      |
| Puma     | 4       | 722                      | 1.3s                      | 10.88s                      |
| Puma     | 5       | 880                      | 1.05s                     | 9.01s                       |
| Puma     | 10      | 1601                     | 571.37ms                  | 4.07s                       |
| Puma     | 30      | 3758                     | 240.81ms                  | 268.24ms                    |
| Puma     | 50      | 3739                     | 240.7ms                   | 258.16ms                    |

---

# Slide 14: Benchmark: Com Bloqueio de I/O Pesado (1s I/O) (k6-block.js - 30VU)

| Servidor | Threads | Reqs Completadas (30s) | `http_req_duration` (avg) | `http_req_duration` (p95) |
| :------- | :------ | :----------------------- | :------------------------ | :-------------------------- |
| **Falcon** | **1** | **900**                  | **1.02s**                 | **1.04s**                   |
| Puma     | 1       | 54                       | 21.49s                    | 56.72s                      |
| Puma     | 2       | 88                       | 13.33s                    | 42.8s                       |
| Puma     | 3       | 114                      | 9.36s                     | 36.63s                      |
| Puma     | 4       | 146                      | 7.09s                     | 34.24s                      |
| Puma     | 5       | 175                      | 5.79s                     | 33.09s                      |
| Puma     | 10      | 312                      | 3.03s                     | 21.01s                      |
| Puma     | 30      | 840                      | 1.08s                     | 1.1s                        |
| Puma     | 50      | 840                      | 1.09s                     | 1.13s                       |

---

# Slide 15: Análise do Benchmark (1/4): Latência e Consistência (Long-Tail)

* **Falcon: Latências Quase Constantes e Previsíveis**
    * Non-blocking (0 ms I/O): `p(95)` ≈ 81 ms
    * 30 ms I/O: `p(95)` ≈ 95 ms
    * 150 ms I/O: `p(95)` ≈ 158 ms
    * 1 s I/O: `p(95)` ≈ 1.04 s
    * **A latência do Falcon escala linearmente com o tempo de I/O, e o `p(95)` fica muito próximo da média.**

* **Puma: Enormes p95 com Bloqueio**
    * Non-blocking (1 thread): `p(95)` ≈ 708 ms vs Falcon ≈ 81 ms (mesmo sem I/O externo, a variabilidade é maior)
    * Com 30 ms I/O e 1 thread Puma: `p(95)` ≈ **12.4 segundos (!)**
    * Mesmo com 10 threads Puma (30ms I/O): `p(95)` ≈ 1.29 s vs Falcon ≈ 95 ms.
    * **Puma sofre com latências extremas para uma porcentagem das requisições sempre que existe I/O bloqueante e poucas threads para absorver.**

* **Conclusão Parcial:** Falcon, usando Fibers + reactor, **evita o efeito de "caudas longas"** de latência, proporcionando uma experiência de usuário muito mais consistente.

---

# Slide 16: Análise do Benchmark (2/4): Throughput (Reqs Completadas em 30s)

| Cenário de I/O | Falcon (1 thread) | Puma (melhor config.) | Razão Falcon/Puma (Throughput) |
| :------------- | :---------------- | :-------------------- | :----------------------------- |
| 0 ms (Non-Block) | 11.349            | 12.265 (1 thread)     | Puma +8%¹                      |
| **30 ms** | **11.535** | **7.844 (50 threads)**| **Falcon +47%** |
| **150 ms** | **5.815** | **3.758 (30 threads)**| **Falcon +55%** |
| **1 s** | **900** | **840 (30/50 threads)**| **Falcon +7%** |

* ¹No caso non-blocking puro, Puma com 1 thread entrega um pouco mais de requisições. Isso deve ser pelo overhead do escalonamento das Fibers do Falcon (muito pequeno) em comparação a nenhum escalonamento no Puma.
* **Em todos os cenários com I/O, o Falcon supera significativamente o Puma, mesmo quando Puma utiliza dezenas de threads.**

---

# Slide 17: Análise do Benchmark (3/4): Escalabilidade de Threads (Puma)

* **Puma Precisa de Muitas Threads:**
    * Para sequer *chegar perto* do throughput do Falcon em cenários com I/O, Puma precisa escalar para dezenas de threads (30–50 nos testes).
* **Retornos Decrescentes:**
    * No Puma, a partir de ~30 threads (nos testes), o ganho de requisições adicionais por thread adicionada é marginal — ou até decrescente.
    * Isso ocorre devido ao **overhead de troca de contexto** entre muitas threads e à **contenção do GIL**.
* **Escalar Puma Verticalmente (mais threads) Implica:**
    * **Mais memória:** Cada thread consome recursos (stack, etc., tipicamente ~1-2MB por thread ou mais).
    * **Mais overhead do scheduler** do sistema operacional.
    * **Menor eficiência global** por worker/processo.
* **Falcon:** Com 1 worker (processo/thread principal) e múltiplas Fibers, evita grande parte desse overhead.

---

# Slide 18: Análise do Benchmark (4/4): Trade-off CPU vs I/O

* **Puma (I/O Bloqueante):**
    * Métricas de **CPU ficam enganosamente baixas** mesmo com um backlog enorme de requisições.
    * As threads simplesmente "dormem" (ficam ociosas, estado `IO-wait`) aguardando o I/O, sem consumir CPU.
    * Isso torna o **autoscaling baseado em CPU ineficaz** para detectar a real carga da aplicação.

* **Falcon (I/O Assíncrono com Fibers):**
    * Aproveita um **único loop de evento (reactor)** por processo/thread.
    * Uma Fiber **cede imediatamente o controle ao reactor** quando realiza uma operação de I/O.
    * O reactor monitora os descritores de arquivo. Enquanto isso, a CPU fica livre para que **outras Fibers processem novas requisições ou continuem seu trabalho.**
    * **Uso mais eficiente da CPU:** A CPU está sempre trabalhando em tarefas ativas, não esperando por I/O.

---

# Slide 19: Conclusão Geral dos Benchmarks

* **Falcon Demonstra Superioridade em Workloads I/O-Bound:**
    * ✅ **Latências drasticamente mais baixas e estáveis** (p95 quase igual à média), resultando em melhor experiência do usuário.
    * ✅ **Throughput significativamente mais elevado** sem a necessidade de múltiplas threads/processos custosos.
    * ✅ **Uso de memória e overhead de contexto potencialmente muito menores** (embora não medido diretamente, é uma característica do modelo de Fibers vs Threads/Processos).

* **Puma com I/O Bloqueante Sofre:**
    * ⚠️ Latências com "caudas longas" (long-tail) muito elevadas e imprevisíveis.
    * ⚠️ Throughput limitado, a menos que se utilizem dezenas de threads, o que aumenta o consumo de recursos e o overhead.
    * ⚠️ Escalabilidade vertical (mais threads) é cara e tem retornos decrescentes rapidamente.

* **Implicação Clara:**
    * Para aplicações Ruby on Rails com **operações de I/O frequentes ou demoradas** (a maioria das aplicações web!), um servidor event-driven como o **Falcon (Fibers + reactor) é mais estável, eficiente e economicamente escalável.**

---

# Slide 20: Por que Falcon é uma Mudança de Paradigma para Rails?

* **Menos Recursos, Mais Performance:** Lida com mais conexões concorrentes com menos processos/threads, economizando memória e CPU que seriam gastos com o overhead das Threads.
* **Latência Previsível:** Reduz picos de latência, crucial para a experiência do usuário.
* **Escalabilidade Simplificada:** Menos necessidade de ajustar pools de threads complexos; escala melhor com a natureza assíncrona do I/O.
* **Pronto para o Futuro:** Alinhado com as melhorias de concorrência do Ruby 3+

---

# Slide 21: Perguntas e Discussão
Estamos contratando!!

Assunto: Vaga Desenvolvedor Ruby
vagas@baladapp.com.br


Obrigado!

Wagner Caixeta / BALADAPP