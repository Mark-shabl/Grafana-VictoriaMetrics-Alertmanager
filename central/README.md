# Central Server — полный стек мониторинга

Разворачивается на **центральном сервере** и сразу собирает:

- метрики самого стека мониторинга: VictoriaMetrics, vmagent, vmalert;
- метрики центрального сервера: CPU, RAM, disk, network через node_exporter;
- метрики Docker-контейнеров центрального сервера через cAdvisor;
- метрики MikroTik / RouterOS: **SNMP** (snmp_exporter) и **API** (MKTXP, профиль **`full`** по умолчанию);
- метрики удалённых серверов, если они отправляются из пакета `remote/`.

## Развёртывание

Файл **`.env`** в каталоге `central/` задаёт секреты для MikroTik: SNMP community (`MIKROTIK_SNMP_COMMUNITY`) и учётные данные RouterOS API для MKTXP (`MIKROTIK_API_USER`, `MIKROTIK_API_PASSWORD`; опционально `MKTXP_PROFILE`, `MKTXP_POE` — см. `.env.example`). Скопируйте `.env.example` → `.env` и заполните значения.

```bash
cd central
cp -n .env.example .env   # затем MIKROTIK_SNMP_COMMUNITY и MIKROTIK_API_*
docker compose up -d
```

После запуска откройте:

- Grafana: `http://SERVER_IP:3000` (`admin` / `admin`)
- VictoriaMetrics VMUI: `http://SERVER_IP:8428/vmui`

## Быстрая проверка

На центральном сервере:

```bash
bash scripts/check-monitoring.sh
```

Скрипт проверит, что VictoriaMetrics доступна и в ней есть базовые метрики:

- `up`
- `up{job="node_exporter"}`
- `up{job="cadvisor"}`
- `node_cpu_seconds_total`
- `container_cpu_usage_seconds_total`

Если проверка проходит, Grafana уже должна видеть метрики центрального сервера и контейнеров.

## Важно: приём метрик с удалённых серверов

Удалённые vmagent **отправляют** (push) метрики на VictoriaMetrics по порту **8428**. VictoriaMetrics принимает их без дополнительной настройки.

**Безопасность:** VictoriaMetrics не проверяет аутентификацию. Открывайте порт 8428 **только для IP ваших удалённых серверов**, иначе любой сможет отправлять метрики.

```bash
# ufw (Ubuntu/Debian) — только подсеть ваших серверов
ufw allow from 192.168.1.0/24 to any port 8428 proto tcp
ufw reload

# firewalld (CentOS/RHEL)
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.1.0/24" port port="8428" protocol="tcp" accept'
firewall-cmd --reload
```

Замените `192.168.1.0/24` на подсеть или конкретные IP удалённых серверов. **Не открывайте порт для всех** (`ufw allow 8428/tcp` без `from`).

URL для remote write: `http://ВАШ_IP:8428/api/v1/write`

## Точки доступа

| Сервис | URL | Учётные данные |
|--------|-----|----------------|
| Grafana | http://localhost:3000 | admin / admin |
| VictoriaMetrics VMUI | http://localhost:8428/vmui | — |
| vmalert | http://localhost:8880 | — |
| Alertmanager | http://localhost:9093 | — |
| vmagent | http://localhost:8429 | — |
| node_exporter | http://localhost:9100 | — |
| cAdvisor | http://localhost:8080 | — |
| snmp_exporter | http://127.0.0.1:9116 | только локально |
| MKTXP | http://127.0.0.1:49090/metrics | только локально |

`vmagent`, `node_exporter` и cAdvisor в central используют host network, поэтому локальные метрики собираются через `127.0.0.1` без отдельного запуска `remote/`.

## Дашборды

Используемые дашборды:

| ID | Название | Для чего |
|----|----------|----------|
| 10229 | VictoriaMetrics | Состояние VictoriaMetrics |
| 12683 | VictoriaMetrics - vmagent | Состояние vmagent |
| 14950 | VictoriaMetrics - vmalert | Состояние vmalert |
| 1860 | Node Exporter Full | CPU, RAM, disks, network хостов |
| 14857 | MikroTik | Интерфейсы, трафик и состояние RouterOS через SNMP |
| 13679 | MikroTik MKTXP | RouterOS через API (MKTXP): коммутаторы, `switch_port`, health и др. |
| 14282 | Docker/cAdvisor | Docker-контейнеры |

Скачать предустановленные дашборды на Linux-сервере:

```bash
bash scripts/download-dashboards.sh
docker compose restart grafana
```

Если будет **Permission denied** при записи в `central/dashboards/`, каталог принадлежит **root** (часто после `sudo git clone/pull`): выполните `sudo bash scripts/download-dashboards.sh` или один раз **`sudo chown -R "$(whoami)":"$(whoami)" dashboards/`**.

Или на Windows PowerShell:

```powershell
.\scripts\download-dashboards.ps1
```

Затем перезапустить Grafana, если ещё не сделали:

```bash
docker compose restart grafana
```

Dashboard **MikroTik** читает метрики, которые уже в VictoriaMetrics (**snmp_exporter** опрашивает роутер, **vmagent** скрейпит exporter на `127.0.0.1:9116`).

1. На MikroTik: SNMP вкл., community только для центра, файрвол **UDP/161**.
2. В `central/.env`: `MIKROTIK_SNMP_COMMUNITY=<вашcommunity>`.
3. В `central/vmagent/prometheus.yml` в job `snmp_mikrotik` укажите IP роутера в `targets:` (по умолчанию пример **192.168.88.1**).
4. `docker compose up -d snmp_exporter vmagent`.

Проверка с центра: Explore / VMUI — `up{job="snmp_mikrotik"} == 1`, `up{job="snmp_if_mib"} == 1`, затем **`ifHCInOctets{job="snmp_if_mib"}`** (трафик по интерфейсам задаёт модуль **`if_mib`**, модуль **`mikrotik`** даёт **`mtxr*`** без `ifHCInOctets`). **instance** на дашборде — IP из `targets`.

### MKTXP (RouterOS API)

Конфиг в контейнере пишется в **`/etc/mktxp`**; старт идёт как пользователь **`mktxp`** с **`mktxp --cfg-dir /etc/mktxp export`** (иначе MKTXP ищет `~/mktxp` и подставляет шаблон **Sample-Router**).

Переменная **`MKTXP_PROFILE`** задаёт объём собираемых метрик:

- **`full`** (значение по умолчанию) — включаются **все** коллекторы из шаблона MKTXP, в том числе DHCP и leases, IPv6, туннели (EoIP/GRE/IP-IP/IPsec), BGP/BFD/routing-stats, контейнеры, Kid Control, W60G, CAPsMAN, Wi‑Fi, **`switch_port`**, **`check_for_updates`**. Если на устройстве **нет PoE** в API, в **`.env`** задайте **`MKTXP_POE=False`**, чтобы убрать ошибки вида `no such command prefix` по PoE.
- **`crs`**, **`minimal`**, **`switch`** — прежний «лёгкий» профиль под коммутатор: Wi‑Fi/CAPsMAN и лишнее выключены, **`MKTXP_DHCP`**, **`MKTXP_DHCP_LEASE`**, **`MKTXP_POE`** читаются из `.env` (по умолчанию выкл., кроме `switch_port`).

Остальное в **`.env`**: `MIKROTIK_API_USER`, `MIKROTIK_API_PASSWORD`, при необходимости `MIKROTIK_API_HOST`, `MKTXP_ROUTER_SECTION` и т.д. — см. **`.env.example`**.

LTE-метрики в документации MikroTik для старых ROS иногда требуют доп. политики **`test`** у пользователя API; если в логах будут ошибки по LTE — добавьте политику группе или отключите профиль **`crs`** на устройствах без соответствующих сервисов (для **`full`** это уже «собираем всё возможное» через MKTXP; отдельные неудачные API-вызовы смотрите в **`docker compose logs mktxp`**).

На устройстве RouterOS 7:

- Включите API: `/ip service print` — **`api`** должна быть активна (`/ip service enable api` или задайте `disabled=no`, адрес ограничьте вашей центральной подсетью).
- Создайте пользователя только с чтением и API (достаточно для MKTXP):

```
/user group add name=mktxp_group policy=api,read
/user add name=mktxp_user group=mktxp_group password=YOUR_STRONG_PASSWORD
```

- Разрешите с центрального сервера подключение к порту API (по умолчанию **TCP 8728**; если используете **API SSL**, см. переменную `MKTXP_USE_SSL` и порт 8729 в документации MikroTik).

Поднять экспортёр и vmagent:

`docker compose up -d mktxp vmagent`

Проверка: `curl -sf http://127.0.0.1:49090/metrics | head`; в Explore / VMUI — **`up{job="mktxp"} == 1`**. Дашборд по метрикам MKTXP: Grafana ID **13679** (после `scripts/download-dashboards.*` файл `central/dashboards/mktxp.json`).

**Не используете MKTXP:** удалите сервис `mktxp` из `docker-compose.yml`, job `mktxp` из `vmagent/prometheus.yml` и уберите строку **`mktxp`** из **`depends_on`** у `vmagent`.

### Если MikroTik нет вообще

**Без роутера MikroTik:** удалите блоки `job_name: snmp_mikrotik` и `job_name: snmp_if_mib`, job `mktxp` из `vmagent/prometheus.yml` и строку **`mktxp`** из `depends_on` у `vmagent`; из `docker-compose.yml` удалите сервисы `snmp_exporter` и **`mktxp`**, чтобы не было ошибок scrape.

Если `Node Exporter Full` или Docker/cAdvisor показывают `No data`, сначала проверьте:

```promql
up{job="node_exporter"} == 1
up{job="cadvisor"} == 1
node_uname_info
container_cpu_usage_seconds_total
```

Если эти запросы дают данные в Grafana Explore, перекачайте дашборды скриптом выше: он берёт актуальные ревизии с grafana.com.

## Alertmanager

По умолчанию алерты идут в `blackhole`. Для Slack, Email и др. настройте `alertmanager/alertmanager.yml`.

## Частые сообщения в логах

- Grafana `public-dashboards status=404` — не ошибка, Grafana проверяет публичную версию дашборда.
- Grafana `POST /api/ds/query status=400` — обычно проблема переменной дашборда (`All`/пустое значение). Проверьте запрос в Explore.
- VictoriaMetrics `unsupported path requested` для `/.env`, `/.git/config`, `/swagger` — внешние сканеры. Закройте порт 8428 firewall-ом для всех, кроме своих remote-серверов.
- VictoriaMetrics `unsupported path requested` для `"/api/v1/write/api/v1/write"` — путь `/api/v1/write` указали дважды. У **remote** в `.env` в `CENTRAL_URL` должно быть только `http://хост:8428`. У **vmalert** `-remoteWrite.url` без суффикса `/api/v1/write`; после правки на central: `docker compose up -d`.
- VictoriaMetrics `ignoring series with … labels` для `container_*` и `maxLabelsPerTimeseries` — у метрики слишком много лейблов (часто тяжёлый Docker-образ как NPM MySQL + cAdvisor). В `central/docker-compose.yml` задано `-maxLabelsPerTimeseries=64`; при необходимости поднимите осторожно или урежьте лейблы через relabel на vmagent.
- VictoriaMetrics `unsupported path requested` для `/._ignition/` и прочих странных URL — сканеры уязвимостей, не часть мониторинга.

## Структура

```
central/
├── docker-compose.yml
├── alertmanager/alertmanager.yml
├── vmagent/prometheus.yml
├── mktxp/                    # Шаблон: entrypoint + render-config под MKTXP (секреты только в .env)
├── rules/                    # Правила алертинга
├── grafana/provisioning/
├── dashboards/
└── scripts/
    ├── download-dashboards.ps1
    ├── download-dashboards.sh
    └── check-monitoring.sh
```
