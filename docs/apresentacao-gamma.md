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

## Arquitetura em GCP — aplicada e pública hoje

- **Cloud Run** hospeda as duas aplicações + o próprio `cache-reverse-proxy`, como um terceiro serviço
- Sem domínio próprio ainda, então o Nginx no Cloud Run é o entrypoint público (em vez do Load Balancer + Cloud CDN)
- Projeto GCP dedicado: `desafio-devops-globo-2026`, com Artifact Registry guardando as 3 imagens
- O desenho "produção" com **Global Load Balancer + Cloud CDN** (backend service por app, TTL nativo) já está em `terraform/network_lb_cdn.tf`, validado, pronto pra aplicar assim que houver um domínio

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

## Acesso público (ao vivo, no GCP)

- Entrypoint público com cache: **cache-reverse-proxy-202002732722.southamerica-east1.run.app**
- `/python-api/fixed` e `/python-api/time` — app Python, cache 10s
- `/go-api/fixed` e `/go-api/time` — app Go, cache 60s
- Provisionado via Terraform, projeto GCP dedicado `desafio-devops-globo-2026`
- Sem Load Balancer/domínio próprio hoje — o proxy de cache roda ele mesmo como um terceiro serviço no Cloud Run, preservando o TTL

---

## Entrega

- Repositório público: **github.com/Soulmatchapp/desafio-devops-globo-2026**
- Código-fonte das duas aplicações + infraestrutura completa
- Configuração de cache documentada e testada
- Infraestrutura automatizada (`docker compose up` local, Terraform aplicado no GCP)
- Diagramas de arquitetura e fluxo de atualização, com pontos de melhoria
- Histórico de commits organizado, `.gitignore` cuidando de segredos e artefatos de build

---

## Obrigado

Repositório: github.com/Soulmatchapp/desafio-devops-globo-2026
Demo pública: cache-reverse-proxy-202002732722.southamerica-east1.run.app
