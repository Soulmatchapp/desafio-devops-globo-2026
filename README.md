# Desafio DevOps 2026

Duas aplicações em linguagens diferentes, cada uma com uma rota de texto fixo e uma rota de horário do servidor, atrás de uma camada de cache com expiração diferente por aplicação, infra fácil de subir e observabilidade básica.

## Componentes

| Componente | O que é |
|---|---|
| [`apps/python-fixed-time-api`](apps/python-fixed-time-api) | API em **Python (FastAPI)**. Rotas `/fixed`, `/time`, `/metrics`, `/healthz`. Cache de **10s**. |
| [`apps/go-fixed-time-api`](apps/go-fixed-time-api) | API em **Go** (stdlib, sem dependências externas). Rotas `/fixed`, `/time`, `/metrics`, `/healthz`. Cache de **60s**. |
| [`nginx/`](nginx) | `cache-reverse-proxy` — reverse proxy local com `proxy_cache`. Zona `python_api_cache_10s` (10s) e `go_api_cache_60s` (60s). |
| [`observability/`](observability) | `metrics-collector` (Prometheus, faz scrape das apps) + `metrics-dashboard` (Grafana, dashboard pré-provisionado). |
| [`terraform/`](terraform) | IaC de referência para rodar a mesma arquitetura no **Google Cloud** (Cloud Run + Load Balancer/Cloud CDN). Não aplicada — ver seção GCP abaixo. |
| [`diagrams/`](diagrams) | Diagrama de arquitetura (local + GCP) e do fluxo de atualização, com pontos de melhoria. |
| [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml) | Pipeline de build + deploy para o cenário GCP. |

## Como rodar (local)

Único pré-requisito: Docker + Docker Compose.

```bash
docker compose up --build
```

Isso sobe, com um comando só: `python-fixed-time-api`, `go-fixed-time-api`, `cache-reverse-proxy` (Nginx), `metrics-collector` (Prometheus) e `metrics-dashboard` (Grafana).

| Serviço | URL |
|---|---|
| App Python via cache (10s) | http://localhost:8080/python-api/fixed e http://localhost:8080/python-api/time |
| App Go via cache (60s) | http://localhost:8080/go-api/fixed e http://localhost:8080/go-api/time |
| Prometheus (`metrics-collector`) | http://localhost:9090 |
| Grafana (`metrics-dashboard`, login admin/admin, ou anônimo como viewer) | http://localhost:3000 |

### Verificando o cache

```bash
curl -i http://localhost:8080/python-api/time   # repita em menos de 10s: X-Cache-Status vai de MISS pra HIT
curl -i http://localhost:8080/go-api/time       # repita em menos de 60s: mesmo comportamento
```

O header `X-Cache-Status` (`MISS`/`HIT`/`EXPIRED`) exposto pelo `cache-reverse-proxy` mostra o cache funcionando na prática — já testado ponta a ponta durante o desenvolvimento.

## Configuração de cache

| App | Camada (local) | Camada (GCP) | TTL |
|---|---|---|---|
| python-fixed-time-api | Nginx `proxy_cache`, zona `python_api_cache_10s` | Cloud CDN, `python-fixed-time-api-backend` (`python_api_cache_ttl_seconds`) | **10 segundos** |
| go-fixed-time-api | Nginx `proxy_cache`, zona `go_api_cache_60s` | Cloud CDN, `go-fixed-time-api-backend` (`go_api_cache_ttl_seconds`) | **60 segundos (1 minuto)** |

## Observabilidade

- Cada app expõe `/metrics` em formato Prometheus (contagem de requests e latência por rota).
- `metrics-collector` (Prometheus) faz scrape das duas apps a cada 5s.
- `metrics-dashboard` (Grafana) já sobe com datasource e dashboard `Desafio DevOps - Overview` provisionados (nada pra configurar manualmente).
- Em GCP, a mesma observabilidade é coberta nativamente por **Cloud Monitoring + Cloud Logging + Cloud Trace** no Cloud Run, sem precisar operar Prometheus/Grafana em produção.

## Rodando em GCP (Terraform)

O diretório [`terraform/`](terraform) provisiona a arquitetura completa: Artifact Registry, os dois serviços no Cloud Run (`python_fixed_time_api`, `go_fixed_time_api`), e um Load Balancer global com Cloud CDN configurado com TTL diferente por app. **Não foi aplicado** — fica pronto pra rodar quando houver um projeto GCP com billing:

```bash
cd terraform
terraform init
terraform apply \
  -var "project_id=SEU_PROJECT_ID" \
  -var "python_api_container_image=southamerica-east1-docker.pkg.dev/SEU_PROJECT_ID/desafio-devops/python-fixed-time-api:latest" \
  -var "go_api_container_image=southamerica-east1-docker.pkg.dev/SEU_PROJECT_ID/desafio-devops/go-fixed-time-api:latest"
```

(As imagens precisam existir no Artifact Registry antes do apply — buildar e dar `docker push` localmente, ou deixar o pipeline do GitHub Actions cuidar disso a cada push.)

## Diagramas e análise

- [`diagrams/architecture.md`](diagrams/architecture.md) — arquitetura local e em GCP, com pontos de melhoria.
- [`diagrams/update-flow.md`](diagrams/update-flow.md) — fluxo de atualização de código e infraestrutura, com pontos de melhoria.

## Estrutura do repositório

```
.
├── apps/
│   ├── python-fixed-time-api/  # FastAPI: /fixed /time /metrics /healthz, cache 10s
│   └── go-fixed-time-api/      # Go stdlib: /fixed /time /metrics /healthz, cache 60s
├── nginx/                      # cache-reverse-proxy: cache local (python_api_cache_10s / go_api_cache_60s)
├── observability/               # metrics-collector (Prometheus) + metrics-dashboard (Grafana)
├── terraform/                   # IaC de referência para GCP (Cloud Run + LB/CDN)
├── diagrams/                    # arquitetura + fluxo de atualização + melhorias
├── .github/workflows/           # pipeline de build/deploy
└── docker-compose.yml           # sobe tudo localmente com um comando
```
