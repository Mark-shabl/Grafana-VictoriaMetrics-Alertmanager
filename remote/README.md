# Remote Server — Агент для передачи метрик

Пакет для **удалённого сервера**. Собирает метрики хоста, Docker-контейнеров и сети, отправляет на центральный VictoriaMetrics.

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

- **CENTRAL_URL** — IP или hostname центрального сервера, порт 8428
- **HOSTNAME** — уникальное имя этого сервера (server1, server2, db-prod и т.п.). Нужно для разделения метрик в Grafana

### Шаг 3: Запустите

```bash
docker compose up -d
```

## Проверка

1. На центральном сервере откройте Grafana
2. Explore → выполните запрос: `up{job="node_exporter"}`
3. Должны появиться метрики с label `host` = значение HOSTNAME из .env

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
├── prometheus.yml      # Скрейпинг node_exporter
├── .env.example
└── README.md
```
