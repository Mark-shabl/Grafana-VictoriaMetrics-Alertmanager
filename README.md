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

Набор дашбордов: `1860 Node Exporter Full`, `14857 MikroTik`, существующий Docker/cAdvisor, а также VictoriaMetrics/vmagent/vmalert.

### 2. Удалённый сервер

```bash
cd remote
cp .env.example .env
# Отредактируйте .env — впишите CENTRAL_URL и REMOTE_NAME
docker compose up -d
```

Подробнее: [remote/README.md](remote/README.md)

## Как связать — что куда вписать

| Где | Что вписать | Пример |
|-----|-------------|--------|
| **remote/.env** | `CENTRAL_URL` — адрес центрального сервера | `http://192.168.1.100:8428` |
| **remote/.env** | `REMOTE_NAME` — имя сервера в Grafana, лейбл `host` и `instance` для scrape | `db-prod-1` |
| **Firewall центрального сервера** | Входящий TCP порт 8428 | Разрешить с IP удалённых серверов |
| **Firewall удалённого сервера** | Исходящий доступ на central:8428 | Обычно уже разрешён |

<a id="firewall-setup"></a>

## Настройка firewall

### Центральный сервер

Цель: **видеть UI** с доверенных адресов и **принимать remote write** только с IP удалённых агентов. VictoriaMetrics на `/api/v1/write` **без пароля** — порт **8428** нельзя оставлять открытым для всего интернета.

Порты, которые фактически слушает стек из `central/docker-compose.yml` (и типичные host-сервисы):

| Порт | Назначение | Рекомендация |
|------|------------|--------------|
| **8428** (TCP) | VictoriaMetrics: API, VMUI, **приём метрик** (`/api/v1/write`) | Входящий: **только** IP/подсеть ваших `remote` (и при необходимости вашей админской сети для VMUI). |
| **3000** (TCP) | Grafana | Только VPN, офисная подсеть или конкретные IP админов. |
| **8880** (TCP) | vmalert | По умолчанию лучше не публиковать наружу; при необходимости — та же политика, что и Grafana. |
| **9093** (TCP) | Alertmanager | Аналогично vmalert. |
| **8089** (TCP/UDP), **2003** (TCP/UDP), **4242** (TCP) | Influx / Graphite / OpenTSDB в VictoriaMetrics | Если протоколы не используются — **закройте** на периметре. |
| **9100**, **8080** (TCP) | node_exporter и cAdvisor в `central` работают в `network_mode: host` | Слушают на интерфейсах хоста; с внешней сети **входящие** на эти порты лучше запретить (достаточно доступа локальному vmagent на `127.0.0.1`). |

Дополнительно проверьте **правила облачного провайдера** (Security Groups, NSG и т.п.): там часто нужно явно разрешить тот же трафик, что и на `ufw`/`firewalld`.

**Примеры — только удалённые агенты на 8428 (ufw, Ubuntu/Debian):**

```bash
# подсеть серверов с remote/
sudo ufw allow from 192.168.1.0/24 to any port 8428 proto tcp

# или по одному IP
sudo ufw allow from 192.168.1.50 to any port 8428 proto tcp

sudo ufw reload
sudo ufw status
```

**Не используйте** `sudo ufw allow 8428/tcp` без `from …` — так порт станет доступен отовсюду.

**firewalld (CentOS, RHEL, Fedora):**

```bash
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.1.0/24" port port="8428" protocol="tcp" accept'
sudo firewall-cmd --reload
```

Замените `192.168.1.0/24` на свою подсеть или добавьте отдельные `rich-rule` для каждого IP.

После изменений с **удалённой** машины проверьте доступность порта, например: `curl -sf "http://IP_ЦЕНТРА:8428/api/v1/labels?limit=1"` (должен вернуть JSON) или `nc -zv IP_ЦЕНТРА 8428`. Окончательно — запуск `remote` и `docker compose logs vmagent`: не должно быть ошибок отправки на `remoteWrite.url`.

### Удалённый сервер

Нужен **исходящий** доступ к центру: TCP с хоста (или из контейнеров при вашей сетевой схеме) на `CENTRAL_HOST:8428`. Входящие порты для приёма метрик центром **не** открываются на remote.

Если на удалённой машине включён строгий исходящий firewall — добавьте разрешение на destination `IP_центра`, порт `8428`, протокол TCP.

Стандартный `docker compose` для `remote` в репозитории обычно не требует открывать **входящие** порты во внешний мир: node_exporter/cAdvisor слушают для локального vmagent (см. [remote/README.md](remote/README.md)).

## Как центральный сервер принимает метрики

**Схема:** central vmagent собирает метрики самого central, а удалённый vmagent **отправляет** (push) метрики других серверов на центральный VictoriaMetrics.

1. **VictoriaMetrics** на central слушает порт **8428** и принимает данные на `/api/v1/write`. Дополнительная настройка не нужна.

2. **На центральном сервере** — открыть порт 8428 **только для IP ваших удалённых серверов** (см. [«Настройка firewall»](#firewall-setup)).

3. **На удалённом сервере** — в `remote/.env` указать `CENTRAL_URL=http://IP_CENTRAL:8428` и запустить `docker compose up -d`. vmagent сам начнёт отправлять метрики.

## Безопасность

**VictoriaMetrics** по умолчанию **не проверяет** аутентификацию на `/api/v1/write`. Любой, кто достучится до порта 8428, может отправить метрики.

**Обязательно:** ограничьте входящий доступ к **8428** по IP удалённых агентов — готовые команды `ufw` и `firewalld` в разделе [«Настройка firewall»](#firewall-setup) выше.

**Дополнительно:** для выноса приёма метрик за VPN или перед VictoriaMetrics можно использовать **vmauth** или **nginx** с Basic Auth.

## Как в Grafana видеть и разделять метрики

Метрики различаются по **labels**. Label `host` — сервер, `job` — источник (node_exporter, cadvisor).

| Что смотреть | job | Пример метрик |
|--------------|-----|---------------|
| Нагрузка сервера | node_exporter | `node_cpu_seconds_total`, `node_memory_MemAvailable_bytes`, `node_load1` |
| Трафик сети | node_exporter | `node_network_receive_bytes_total`, `node_network_transmit_bytes_total` |
| Docker-контейнеры | cadvisor | `container_cpu_usage_seconds_total`, `container_memory_usage_bytes` |
| Трафик контейнеров | cadvisor | `container_network_receive_bytes_total`, `container_network_transmit_bytes_total` |
| MikroTik / RouterOS | snmp_exporter | interface traffic, packets, errors, CPU, memory |

**Фильтр по серверу:** добавьте `host="server1"` к запросу. Дашборды Node Exporter и Docker — создайте переменную `host` (Label = `host`).

**Важно:** на каждом удалённом сервере задаётте свой **`REMOTE_NAME`** в `remote/.env` (разные машины не должны совпадать).

## Быстрая диагностика

На central:

```bash
cd central
bash scripts/check-monitoring.sh
```

Если скрипт проходит, VictoriaMetrics уже содержит базовые метрики `up`, `node_cpu_seconds_total` и `container_cpu_usage_seconds_total`.

Для dashboard `MikroTik` в VictoriaMetrics должны быть метрики от `snmp_exporter`. Если MikroTik ещё не скрейпится по SNMP, этот дашборд будет пустым.

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
