# Remote Server — агент для удалённых серверов

Пакет нужен на **других Linux-серверах**, которые должны отправлять метрики в центральную VictoriaMetrics.

На самом центральном сервере запускать `remote/` больше не обязательно: `central/` уже включает node_exporter и cAdvisor для мониторинга самого себя.

## Что входит

| Компонент | Метрики |
|-----------|---------|
| **node_exporter** | Нагрузка сервера: CPU, RAM, диск, load average, сетевые интерфейсы |
| **cAdvisor** | Docker-контейнеры: CPU, память, трафик на каждый контейнер |
| **vmagent** | Скрейпит оба экспортера и отправляет на central |

Все метрики помечены label `host` — в Grafana можно фильтровать по серверу.

## Как связать с центральным сервером

### Шаг 1: Скопируйте .env

```bash
cp .env.example .env
```

### Шаг 2: Впишите настройки

Откройте `.env` и укажите:

```
CENTRAL_URL=http://192.168.1.100:8428
HOSTNAME=server1
```

- **CENTRAL_URL** — только базовый адрес VictoriaMetrics (`http://IP:8428`), **без** суффикса `/api/v1/write` (его подставляет `docker-compose.yml` у vmagent)
- **HOSTNAME** — уникальное имя этого сервера (server1, server2, db-prod и т.п.). Нужно для разделения метрик в Grafana
- `remote` использует отдельные локальные порты, чтобы не конфликтовать с `central`, если их случайно запустить на одной машине:
  - node_exporter: **19100**
  - cAdvisor: **18080**
  - vmagent: **18429**

### Шаг 3: Запустите

```bash
docker compose up -d
```

## Проверка

На удалённом сервере:

```bash
docker compose ps
docker compose logs vmagent --tail 50
```

В логах vmagent не должно быть `fatal`, а в central VMUI/Grafana должны появиться:

- `up{job="node_exporter",host="server1"}`
- `up{job="cadvisor",host="server1"}`
- `node_cpu_seconds_total{host="server1"}`
- `container_cpu_usage_seconds_total{host="server1"}`

Замените `server1` на значение `HOSTNAME` из `.env`.

## Firewall

**Удалённый сервер:** должен иметь **исходящий** доступ к central:8428 (обычно уже есть).

**Центральный сервер:** нужно **открыть входящий** TCP 8428 для IP удалённых серверов. Без этого VictoriaMetrics не сможет принять метрики.

```bash
# На центральном сервере (ufw)
ufw allow from IP_УДАЛЁННОГО to any port 8428 proto tcp
ufw reload
```

## Структура

```
remote/
├── docker-compose.yml
├── prometheus.yml      # Скрейпинг node_exporter и cAdvisor
├── .env.example
└── README.md
```
