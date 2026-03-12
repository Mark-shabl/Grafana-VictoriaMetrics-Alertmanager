# Grafana + VictoriaMetrics + Alertmanager

Стек мониторинга из двух пакетов: **central** (хранение и администрирование) и **remote** (агент для передачи метрик).

## Схема

```
┌─────────────────────────────────────────────────────────────────┐
│  Центральный сервер (central/)                                  │
│  VictoriaMetrics · Grafana · vmalert · Alertmanager · vmagent   │
│  Хранение метрик, дашборды, алерты                              │
└────────────────────────────▲────────────────────────────────────┘
                             │ remote write :8428
┌────────────────────────────┴────────────────────────────────────┐
│  Удалённый сервер (remote/)                                     │
│  node_exporter + vmagent — только сбор и отправка метрик         │
└─────────────────────────────────────────────────────────────────┘
```

## Быстрый старт

### 1. Центральный сервер

```bash
cd central
docker compose up -d
```

Подробнее: [central/README.md](central/README.md)

### 2. Удалённый сервер

```bash
cd remote
cp .env.example .env
# Отредактируйте .env — впишите CENTRAL_URL
docker compose up -d
```

Подробнее: [remote/README.md](remote/README.md)

## Как связать — что куда вписать

| Где | Что вписать | Пример |
|-----|-------------|--------|
| **remote/.env** | `CENTRAL_URL` — адрес центрального сервера | `http://192.168.1.100:8428` |
| **Firewall центрального сервера** | Входящий TCP порт 8428 | Разрешить с IP удалённых серверов |
| **Firewall удалённого сервера** | Исходящий доступ на central:8428 | Обычно уже разрешён |

## Как центральный сервер принимает метрики

**Схема:** удалённый vmagent **отправляет** (push) метрики на центральный VictoriaMetrics. Центральный сервер ничего не «подключает» — он только **принимает** входящие запросы.

1. **VictoriaMetrics** на central слушает порт **8428** и принимает данные на `/api/v1/write`. Дополнительная настройка не нужна.

2. **Что нужно сделать на центральном сервере** — открыть порт 8428 **только для IP ваших удалённых серверов** (см. раздел «Безопасность» ниже).

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

**Фильтр по серверу:** добавьте `host="server1"` к запросу. Дашборды Node Exporter и Docker — создайте переменную `host` (Label = `host`).

**Важно:** задайте разный `HOSTNAME` в remote/.env на каждом удалённом сервере.

## Пакеты

| Пакет | Назначение |
|-------|------------|
| [central/](central/) | Полный стек: VictoriaMetrics, Grafana, vmalert, Alertmanager. Всё хранение и администрирование. |
| [remote/](remote/) | Минимум: node_exporter + vmagent. Только сбор и отправка метрик на central. |

## Требования

- Docker и Docker Compose
- **remote/** — Linux (node_exporter использует host paths)
