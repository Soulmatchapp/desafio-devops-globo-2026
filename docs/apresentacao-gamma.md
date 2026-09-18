# Desafio DevOps 2026 — Globo

Cassio Henrique Silva

---

## O desafio

- Criar **duas aplicações em linguagens diferentes**, cada uma com uma rota de texto fixo e uma rota de horário do servidor
- Adicionar uma **camada de cache** com tempos de expiração diferentes por aplicação
- Deixar a infraestrutura **fácil de subir**, com o menor número de comandos possível
- Implementar **observabilidade**, se possível
- **Desenhar e analisar** a arquitetura, com pontos de melhoria
- Mostrar o **fluxo de atualização** de infra e código

---

## Stack escolhida

- **python-fixed-time-api** — Python (FastAPI), cache de **10 segundos**
- **go-fixed-time-api** — Go (stdlib, zero dependências externas), cache de **1 minuto**
- **cache-reverse-proxy** — Nginx com `proxy_cache`, uma zona de cache por app
- **metrics-collector** + **metrics-dashboard** — Prometheus + Grafana, provisionados automaticamente
- **Terraform** — IaC de referência para rodar a mesma arquitetura no Google Cloud
- Todos os nomes de containers, variáveis e recursos são **explícitos sobre o que fazem** (ex: `python_api_cache_10s`, não só `cache`)

---

## Arquitetura local (docker-compose)

- Um único comando sobe tudo: `docker compose up --build`
- `cache-reverse-proxy` recebe as requisições e decide: cachear ou repassar
- `/python-api/*` → cache de 10s → `python-fixed-time-api`
- `/go-api/*` → cache de 60s → `go-fixed-time-api`
- `metrics-collector` faz scrape de `/metrics` das duas apps a cada 5s
- `metrics-dashboard` já sobe com dashboard pronto, sem configuração manual

---

## Cache na prática

- Header `X-Cache-Status` exposto em toda resposta: `MISS` → `HIT` → `EXPIRED`
- Testado ponta a ponta: primeira chamada em `/python-api/time` = MISS, chamada seguinte (< 10s) = HIT, após 10s = EXPIRED
- Mesmo comportamento validado em `/go-api/time` com janela de 60s
- Cada zona de cache já carrega o TTL no nome: `python_api_cache_10s`, `go_api_cache_60s`

---

## Observabilidade

- Cada app expõe métricas Prometheus nativas: contagem de requests e latência por rota
- Dashboard "Desafio DevOps - Overview" já provisionado no Grafana
- Em produção (GCP), a mesma cobertura vem de graça via **Cloud Monitoring + Cloud Logging + Cloud Trace**, sem operar Prometheus/Grafana manualmente

---

## Arquitetura em GCP (Terraform, pronta pra aplicar)

- **Cloud Run** hospeda as duas aplicações (linguagem não importa pro Cloud Run)
- **Global Load Balancer + Cloud CDN** na frente, com um **backend service por app**
- Cada backend tem sua própria política de cache: `python_api_cache_ttl_seconds = 10`, `go_api_cache_ttl_seconds = 60`
- **Artifact Registry** guarda as imagens versionadas por commit
- Todo o Terraform já passa em `terraform validate` — só falta um projeto GCP com billing pra aplicar

---

## Fluxo de atualização (CI/CD)

1. Push na branch `main` (código ou infra)
2. GitHub Actions builda e publica a imagem no Artifact Registry, com a tag = SHA do commit
3. `terraform apply` atualiza a variável de imagem do Cloud Run correspondente
4. Cloud Run cria uma **nova revisão** e faz rollout gradual de tráfego
5. Cache expira sozinho (10s/60s) — não precisa invalidação manual na maioria dos casos

---

## Pontos de melhoria identificados

- Cloud Run está público hoje (`allUsers`) — trocar por ingress interno + Cloud Armor/IAP na borda
- Sem WAF — adicionar Cloud Armor nos backend services
- `terraform apply` roda direto na `main` sem aprovação — adicionar `plan` obrigatório em PR + aprovação humana
- Terraform state está local — mover para backend remoto (GCS) com locking
- Sem separação de ambientes (dev/staging/prod) — usar workspaces ou diretórios por ambiente
- Sem rollback automático — avaliar Cloud Deploy com canary baseado em métricas de erro

---

## Entrega

- Repositório público: **github.com/Soulmatchapp/desafio-devops-globo-2026**
- Código-fonte das duas aplicações + infraestrutura completa
- Configuração de cache documentada e testada
- Infraestrutura automatizada (`docker compose up` local, Terraform pronto pra GCP)
- Diagramas de arquitetura e fluxo de atualização, com pontos de melhoria
- Histórico de commits organizado, `.gitignore` cuidando de segredos e artefatos de build

---

## Obrigado

Repositório: github.com/Soulmatchapp/desafio-devops-globo-2026
