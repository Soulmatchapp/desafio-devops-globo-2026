# Desafio DevOps 2026

Duas aplicações em linguagens diferentes, cada uma com uma rota de texto fixo e uma rota de horário do servidor, atrás de uma camada de cache com expiração diferente por aplicação, infra fácil de subir e observabilidade básica.

## Acesso público (GCP Cloud Run)

As três peças estão publicadas e acessíveis agora, no projeto GCP `desafio-devops-globo-2026`. Cada uma abre no navegador como uma pequena página web (símbolo, nome do autor e um botão que chama a própria API e mostra o resultado) — não é só JSON cru:

| Endpoint | URL | O que você vê |
|---|---|---|
| **Entrypoint público com cache** (use este pra apresentar) | https://cache-reverse-proxy-202002732722.southamerica-east1.run.app | Página com botão que testa as duas apps de uma vez e mostra o `X-Cache-Status` |
| App Python direto | https://python-fixed-time-api-202002732722.southamerica-east1.run.app | Página própria da app Python, com botão |
| App Go direto | https://go-fixed-time-api-202002732722.southamerica-east1.run.app | Página própria da app Go, com botão |

Rotas de API (JSON) continuam disponíveis em todas: `/fixed`, `/time`, `/metrics`, `/healthz` (direto em cada app) ou `/python-api/*` e `/go-api/*` (através do proxy com cache).

```bash
curl -i https://cache-reverse-proxy-202002732722.southamerica-east1.run.app/python-api/time
# repita em menos de 10s: header x-cache-status vai de MISS pra HIT
```

Isso foi provisionado com o mesmo Terraform de `terraform/` (Artifact Registry + Cloud Run), só que sem o Load Balancer/Cloud CDN completo (esse exige domínio próprio) — o `cache-reverse-proxy` (Nginx) roda como um terceiro serviço no Cloud Run e cumpre o mesmo papel: cache de 10s/60s na frente das duas apps, só que num único entrypoint público. Ver `nginx/nginx-cloud.conf` e `diagrams/architecture.md`.

> O símbolo usado é um globo genérico (🌐), não a marca registrada da Globo — evitei reproduzir a logo oficial numa página pública.

## Proteção contra abuso

As três peças têm **rate limiting por IP** (5 req/s, com burst curto pra não travar o uso normal do botão): no `cache-reverse-proxy` via `limit_req` do Nginx, e diretamente em cada app (middleware no FastAPI, wrapper de handler no Go), já que `python-fixed-time-api` e `go-fixed-time-api` também são públicas. Acima do limite, a resposta é `429 Too Many Requests`. Testado com carga paralela local e em produção. É um limite em memória por instância do Cloud Run — suficiente pra barrar um robô simples clicando/batendo repetido, mas a versão "de verdade" (compartilhada entre instâncias, com regras WAF) é Cloud Armor num Load Balancer — ver `diagrams/architecture.md`.

## Componentes

| Componente | O que é |
|---|---|
| [`apps/python-fixed-time-api`](apps/python-fixed-time-api) | API em **Python (FastAPI)**. Rotas `/fixed`, `/time`, `/metrics`, `/healthz` + página web em `/`. Cache de **10s**. |
| [`apps/go-fixed-time-api`](apps/go-fixed-time-api) | API em **Go** (stdlib, sem dependências externas). Rotas `/fixed`, `/time`, `/metrics`, `/healthz` + página web em `/`. Cache de **60s**. |
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
| **Página do proxy com cache** (abra no navegador) | http://localhost:8080/ |
| App Python via cache (10s) | http://localhost:8080/python-api/fixed e http://localhost:8080/python-api/time |
| App Go via cache (60s) | http://localhost:8080/go-api/fixed e http://localhost:8080/go-api/time |
| Página própria da app Python (sem cache) | http://localhost:8000/ |
| Página própria da app Go (sem cache) | http://localhost:8081/ |
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

O diretório [`terraform/`](terraform) provisiona: Artifact Registry, os três serviços no Cloud Run (`python_fixed_time_api`, `go_fixed_time_api`, `cache_reverse_proxy`) — **já aplicados**, ver seção "Acesso público" acima — e um Load Balancer global com Cloud CDN configurado com TTL diferente por app (`network_lb_cdn.tf`) — **não aplicado**, pois exige um domínio real para o certificado gerenciado (hoje aponta pro domínio fictício `desafio-devops.example.com`).

```bash
cd terraform
terraform init
terraform apply \
  -var "project_id=SEU_PROJECT_ID" \
  -var "python_api_container_image=southamerica-east1-docker.pkg.dev/SEU_PROJECT_ID/desafio-devops/python-fixed-time-api:latest" \
  -var "go_api_container_image=southamerica-east1-docker.pkg.dev/SEU_PROJECT_ID/desafio-devops/go-fixed-time-api:latest" \
  -var "cache_reverse_proxy_container_image=southamerica-east1-docker.pkg.dev/SEU_PROJECT_ID/desafio-devops/cache-reverse-proxy:latest"
```

(As imagens precisam existir no Artifact Registry antes do apply — buildar e dar `docker push` localmente, ou deixar o pipeline do GitHub Actions cuidar disso a cada push. O `cache-reverse-proxy` usa uma imagem diferente da local: `nginx/Dockerfile.cloud` + `nginx/nginx-cloud.conf`, que aponta pros URLs públicos do Cloud Run em vez dos nomes de serviço do docker-compose.)

## Diagramas e análise

- [`diagrams/architecture.md`](diagrams/architecture.md) — arquitetura local e em GCP, com pontos de melhoria.
- [`diagrams/update-flow.md`](diagrams/update-flow.md) — fluxo de atualização de código e infraestrutura, com pontos de melhoria.

## Estrutura do repositório

```
.
├── apps/
│   ├── python-fixed-time-api/  # FastAPI: /fixed /time /metrics /healthz + página web em /, cache 10s
│   │   └── static/index.html   # página própria da app (símbolo + nome + botão)
│   └── go-fixed-time-api/      # Go stdlib: /fixed /time /metrics /healthz + página web em /, cache 60s
│       └── static/index.html   # página própria da app (embutida no binário via go:embed)
├── nginx/                      # cache-reverse-proxy: cache (python_api_cache_10s / go_api_cache_60s)
│   ├── nginx.conf / Dockerfile         # variante local (docker-compose)
│   ├── nginx-cloud.conf / Dockerfile.cloud  # variante Cloud Run (aponta pros URLs públicos)
│   └── site/index.html         # página do proxy: testa as duas apps com um botão
├── observability/               # metrics-collector (Prometheus) + metrics-dashboard (Grafana)
├── terraform/                   # IaC de referência para GCP (Cloud Run + LB/CDN)
├── diagrams/                    # arquitetura + fluxo de atualização + melhorias
├── .github/workflows/           # pipeline de build/deploy
└── docker-compose.yml           # sobe tudo localmente com um comando
```
