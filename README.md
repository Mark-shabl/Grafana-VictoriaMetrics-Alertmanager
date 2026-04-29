# Grafana + VictoriaMetrics + Alertmanager

Стек мониторинга из двух пакетов:

- **central** — полный стек на центральном сервере: VictoriaMetrics, Grafana, vmalert, Alertmanager, vmagent, node_exporter, cAdvisor.
- **remote** — агент для остальных Linux-серверов: node_exporter, cAdvisor, vmagent.

## Схема

```
┌─────────────────────────────────────────────────────────────────┐
│  Центральный сервер (central/)                                  │
│  VictoriaMetrics · Grafana · vmalert · Alertmanager · vmagent   │
│  node_exporter · cAdvisor                                       │
│  Хранение метрик, дашборды, алерты, метрики самого central      │
└────────────────────────────▲────────────────────────────────────┘
                             │ remote write :8428
┌────────────────────────────┴────────────────────────────────────┐
│  Удалённый сервер (remote/)                                     │
│  node_exporter · cAdvisor · vmagent — сбор и отправка метрик     │
└─────────────────────────────────────────────────────────────────┘
```

## Быстрый старт

### 1. Центральный сервер

```bash
cd central
docker compose up -d
bash scripts/check-monitoring.sh
```

Подробнее: [central/README.md](central/README.md)

После этого Grafana уже должна показывать метрики самого центрального сервера и его Docker-контейнеров.

Чтобы скачать выбранные дашборды:

```bash
cd central
bash scripts/download-dashboards.sh
docker compose restart grafana
```

Набор дашбордов: `1860 Node Exporter Full`, `24458 Envoy / Downstream`, существующий Docker/cAdvisor, а также VictoriaMetrics/vmagent/vmalert.

### 2. Удалённый сервер

```bash
cd remote
cp .env.example .env
# Отредактируйте .env — впишите CENTRAL_URL и HOSTNAME
docker compose up -d
```

Подробнее: [remote/README.md](remote/README.md)

## Как связать — что куда вписать

| Где | Что вписать | Пример |
|-----|-------------|--------|
| **remote/.env** | `CENTRAL_URL` — адрес центрального сервера | `http://192.168.1.100:8428` |
| **remote/.env** | `HOSTNAME` — имя удалённого сервера в Grafana | `db-prod-1` |
| **Firewall центрального сервера** | Входящий TCP порт 8428 | Разрешить с IP удалённых серверов |
| **Firewall удалённого сервера** | Исходящий доступ на central:8428 | Обычно уже разрешён |

## Как центральный сервер принимает метрики

**Схема:** central vmagent собирает метрики самого central, а удалённый vmagent **отправляет** (push) метрики других серверов на центральный VictoriaMetrics.

1. **VictoriaMetrics** на central слушает порт **8428** и принимает данные на `/api/v1/write`. Дополнительная настройка не нужна.

2. **На центральном сервере** — открыть порт 8428 **только для IP ваших удалённых серверов** (см. раздел «Безопасность» ниже).

3. **На удалённом сервере** — в `remote/.env` указать `CENTRAL_URL=http://IP_CENTRAL:8428` и запустить `docker compose up -d`. vmagent сам начнёт отправлять метрики.

## Безопасность

**VictoriaMetrics** по умолчанию **не проверяет** аутентификацию на `/api/v1/write`. Любой, кто достучится до порта 8428, может отправить метрики.

**Обязательно:** ограничьте доступ по IP — разрешайте только известные IP удалённых серверов:

```bash
# ufw (Ubuntu/Debian) — только подсеть ваших серверов
ufw allow from 192.168.1.0/24 to any port 8428 proto tcp
ufw reload

# или один конкретный IP
ufw allow from 192.168.1.50 to any port 8428 proto tcp
ufw reload

# firewalld (CentOS/RHEL)
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.1.0/24" port port="8428" protocol="tcp" accept'
firewall-cmd --reload
```

**Не используйте** `ufw allow 8428/tcp` без ограничения по IP — это откроет порт для всех.

**Дополнительно:** для VPN или приватной сети можно использовать vmauth или nginx перед VictoriaMetrics с Basic Auth.

## Как в Grafana видеть и разделять метрики

Метрики различаются по **labels**. Label `host` — сервер, `job` — источник (node_exporter, cadvisor).

| Что смотреть | job | Пример метрик |
|--------------|-----|---------------|
| Нагрузка сервера | node_exporter | `node_cpu_seconds_total`, `node_memory_MemAvailable_bytes`, `node_load1` |
| Трафик сети | node_exporter | `node_network_receive_bytes_total`, `node_network_transmit_bytes_total` |
| Docker-контейнеры | cadvisor | `container_cpu_usage_seconds_total`, `container_memory_usage_bytes` |
| Трафик контейнеров | cadvisor | `container_network_receive_bytes_total`, `container_network_transmit_bytes_total` |
| Envoy downstream | envoy | `envoy_http_downstream_rq_total`, `envoy_http_downstream_cx_active` |

**Фильтр по серверу:** добавьте `host="server1"` к запросу. Дашборды Node Exporter и Docker — создайте переменную `host` (Label = `host`).

**Важно:** задайте разный `HOSTNAME` в remote/.env на каждом удалённом сервере.

## Быстрая диагностика

На central:

```bash
cd central
bash scripts/check-monitoring.sh
```

Если скрипт проходит, VictoriaMetrics уже содержит базовые метрики `up`, `node_cpu_seconds_total` и `container_cpu_usage_seconds_total`.

Для dashboard `Envoy / Downstream` в VictoriaMetrics должны быть метрики `envoy_*`. Если Envoy не скрейпится, этот дашборд будет пустым.

В Grafana:

- 404 на `/public-dashboards` в логах не мешает работе.
- Если панель пустая, сначала проверьте Explore с простым запросом: `node_cpu_seconds_total` или `container_cpu_usage_seconds_total`.
- Если Explore показывает данные, а дашборд нет, выберите конкретный `host`/`instance` вместо пустого значения или `All`.

## Пакеты

| Пакет | Назначение |
|-------|------------|
| [central/](central/) | Полный стек: VictoriaMetrics, Grafana, vmalert, Alertmanager, метрики самого central. |
| [remote/](remote/) | Агент для других Linux-серверов: node_exporter, cAdvisor, vmagent. |

## Требования

- Docker и Docker Compose
- **remote/** — Linux (node_exporter использует host paths)
