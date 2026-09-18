# Desafio DevOps 2026

Duas aplicações em linguagens diferentes, cada uma com uma rota de texto fixo e uma rota de horário do servidor, atrás de uma camada de cache com expiração diferente por aplicação, infra fácil de subir e observabilidade básica.

## Componentes

| Componente | O que é |
|---|---|
| [`apps/py-service`](apps/py-service) | API em **Python (FastAPI)**. Rotas `/fixed`, `/time`, `/metrics`, `/healthz`. |
| [`apps/go-service`](apps/go-service) | API em **Go** (stdlib, sem dependências externas). Rotas `/fixed`, `/time`, `/metrics`, `/healthz`. |
| [`nginx/`](nginx) | Reverse proxy local com `proxy_cache` — cache de **10s** para `py-service`, **60s** para `go-service`. |
| [`observability/`](observability) | Prometheus (scrape das apps) + Grafana (dashboard pré-provisionado). |
| [`terraform/`](terraform) | IaC de referência para rodar a mesma arquitetura no **Google Cloud** (Cloud Run + Load Balancer/Cloud CDN). Não aplicada — ver seção GCP abaixo. |
| [`diagrams/`](diagrams) | Diagrama de arquitetura (local + GCP) e do fluxo de atualização, com pontos de melhoria. |
| [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml) | Pipeline de build + deploy para o cenário GCP. |

## Como rodar (local)

Único pré-requisito: Docker + Docker Compose.

```bash
docker compose up --build
```

Isso sobe: `py-service`, `go-service`, `nginx` (cache), `prometheus` e `grafana` — um comando só.

| Serviço | URL |
|---|---|
| App Python via cache (10s) | http://localhost:8080/py/fixed e http://localhost:8080/py/time |
| App Go via cache (60s) | http://localhost:8080/go/fixed e http://localhost:8080/go/time |
| Prometheus | http://localhost:9090 |
| Grafana (login admin/admin, ou anônimo como viewer) | http://localhost:3000 |

### Verificando o cache

```bash
curl -i http://localhost:8080/py/time   # repita em menos de 10s: X-Cache-Status vai de MISS pra HIT
curl -i http://localhost:8080/go/time   # repita em menos de 60s: mesmo comportamento
```

O header `X-Cache-Status` (`MISS`/`HIT`/`EXPIRED`) exposto pelo Nginx mostra o cache funcionando na prática.

## Configuração de cache

| App | Camada (local) | Camada (GCP) | TTL |
|---|---|---|---|
| py-service | Nginx `proxy_cache` (`py_cache`) | Cloud CDN, backend service `py-service-backend` | **10 segundos** |
| go-service | Nginx `proxy_cache` (`go_cache`) | Cloud CDN, backend service `go-service-backend` | **60 segundos (1 minuto)** |

## Observabilidade

- Cada app expõe `/metrics` em formato Prometheus (contagem de requests e latência por rota).
- Prometheus faz scrape das duas apps a cada 5s.
- Grafana já sobe com datasource e dashboard `Desafio DevOps - Overview` provisionados (nada pra configurar manualmente).
- Em GCP, a mesma observabilidade é coberta nativamente por **Cloud Monitoring + Cloud Logging + Cloud Trace** no Cloud Run, sem precisar operar Prometheus/Grafana em produção.

## Rodando em GCP (Terraform)

O diretório [`terraform/`](terraform) provisiona a arquitetura completa: Artifact Registry, os dois serviços no Cloud Run, e um Load Balancer global com Cloud CDN configurado com TTL diferente por app. **Não foi aplicado** — fica pronto pra rodar quando houver um projeto GCP com billing:

```bash
cd terraform
terraform init
terraform apply \
  -var "project_id=SEU_PROJECT_ID" \
  -var "py_image=southamerica-east1-docker.pkg.dev/SEU_PROJECT_ID/desafio-devops/py-service:latest" \
  -var "go_image=southamerica-east1-docker.pkg.dev/SEU_PROJECT_ID/desafio-devops/go-service:latest"
```

(As imagens precisam existir no Artifact Registry antes do apply — buildar e dar `docker push` localmente, ou deixar o pipeline do GitHub Actions cuidar disso a cada push.)

## Diagramas e análise

- [`diagrams/architecture.md`](diagrams/architecture.md) — arquitetura local e em GCP, com pontos de melhoria.
- [`diagrams/update-flow.md`](diagrams/update-flow.md) — fluxo de atualização de código e infraestrutura, com pontos de melhoria.

## Estrutura do repositório

```
.
├── apps/
│   ├── py-service/   # FastAPI: /fixed /time /metrics /healthz
│   └── go-service/   # Go stdlib: /fixed /time /metrics /healthz
├── nginx/            # reverse proxy + cache (10s / 60s)
├── observability/     # Prometheus + Grafana provisioning
├── terraform/         # IaC de referência para GCP (Cloud Run + LB/CDN)
├── diagrams/          # arquitetura + fluxo de atualização + melhorias
├── .github/workflows/ # pipeline de build/deploy
└── docker-compose.yml # sobe tudo localmente com um comando
```
