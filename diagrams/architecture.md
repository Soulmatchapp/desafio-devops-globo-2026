# Arquitetura

## Ambiente local (docker-compose)

Usado para desenvolvimento e demonstração rápida — sobe tudo com `docker compose up`.

```mermaid
flowchart LR
    Client([Cliente]) --> Nginx["Nginx<br/>reverse proxy + cache"]
    Nginx -- "/py/* (cache 10s)" --> Py["py-service (FastAPI)<br/>/fixed /time /metrics"]
    Nginx -- "/go/* (cache 60s)" --> Go["go-service (Go)<br/>/fixed /time /metrics"]
    Prometheus["Prometheus"] -- scrape --> Py
    Prometheus -- scrape --> Go
    Grafana["Grafana"] --> Prometheus
```

- **Nginx** é a camada de cache local: duas `proxy_cache_path` distintas (`py_cache`, `go_cache`), cada uma com `proxy_cache_valid` diferente (10s / 60s), satisfazendo o requisito de expiração por aplicação.
- **Prometheus** faz scrape do endpoint `/metrics` de cada app (contadores de requests e latência).
- **Grafana** já vem provisionado com datasource e dashboard (`overview.json`).

## Ambiente GCP (Terraform, referência — não aplicado)

Mesmo desenho, só que com componentes gerenciados do Google Cloud, provisionados via `terraform/`.

```mermaid
flowchart LR
    Client([Cliente]) --> LB["Global External HTTPS<br/>Load Balancer"]
    LB --> CDN["Cloud CDN"]
    CDN -- "/py/* (TTL 10s)" --> PyBackend["Backend service py<br/>cdn_policy TTL=10s"]
    CDN -- "/go/* (TTL 60s)" --> GoBackend["Backend service go<br/>cdn_policy TTL=60s"]
    PyBackend --> PyNeg["Serverless NEG"] --> PyRun["Cloud Run: py-service"]
    GoBackend --> GoNeg["Serverless NEG"] --> GoRun["Cloud Run: go-service"]
    AR["Artifact Registry<br/>desafio-devops repo"] -. imagens .-> PyRun
    AR -. imagens .-> GoRun
    PyRun --> Mon["Cloud Monitoring<br/>+ Cloud Logging + Cloud Trace"]
    GoRun --> Mon
```

- **Cloud CDN**, ligado a cada **backend service** (um por app), com `cdn_policy.default_ttl` diferente por app — é o equivalente gerenciado do Nginx local, sem precisar operar cache manualmente.
- **Cloud Run** roda os dois containers (linguagens diferentes, mesma plataforma de execução), com autoscaling 0→3 instâncias.
- **Artifact Registry** guarda as imagens versionadas por commit SHA (ver `diagrams/update-flow.md`).
- **Cloud Monitoring/Logging/Trace** dão observabilidade nativa sem operar Prometheus/Grafana em produção — métricas de requests, latência, cache hit ratio do CDN e logs estruturados de cada revisão.

## Pontos de melhoria identificados

1. **Cloud Run hoje é público (`allUsers`)** para o LB alcançar via NEG. Melhor prática: manter o Cloud Run com ingress `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` e usar Cloud Armor / IAP na borda para controle de acesso, em vez de depender só do LB estar na frente.
2. **Sem WAF/proteção DDoS**: adicionar **Cloud Armor** no backend service (rate limiting, geo-blocking, regras OWASP).
3. **Certificado gerenciado aponta pra domínio fictício** (`desafio-devops.example.com`) — em produção, usar domínio real + Cloud DNS gerenciado via Terraform também.
4. **Cache "tudo ou nada" por rota** (`FORCE_CACHE_ALL`): hoje cacheia `/fixed` e `/time` igual. Uma evolução seria diferenciar cache por rota (ex: não cachear `/time` ou cachear com TTL menor), usando `Cache-Control` vindo da própria aplicação em vez de forçar no LB.
5. **Sem VPC Service Controls / rede privada**: Cloud Run hoje sobe sem VPC connector. Se precisar falar com bancos/Redis privados no futuro, adicionar Serverless VPC Access.
6. **Observabilidade local (Prometheus/Grafana) não é a mesma da produção (Cloud Monitoring)** — considerar exportar métricas das apps também para Cloud Monitoring via OpenTelemetry Collector, mantendo paridade dev/prod.
7. **Secrets/variáveis de ambiente**: nenhuma app usa segredos hoje, mas o padrão para o futuro é Secret Manager + `google_secret_manager_secret_version`, nunca variável de ambiente em texto plano no Terraform.
