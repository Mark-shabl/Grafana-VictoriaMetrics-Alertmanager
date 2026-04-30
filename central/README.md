# Central Server — полный стек мониторинга

Разворачивается на **центральном сервере** и сразу собирает:

- метрики самого стека мониторинга: VictoriaMetrics, vmagent, vmalert;
- метрики центрального сервера: CPU, RAM, disk, network через node_exporter;
- метрики Docker-контейнеров центрального сервера через cAdvisor;
- метрики MikroTik / RouterOS: **SNMP** (snmp_exporter) и **API** (MKTXP, профиль **`full`** по умолчанию);
- метрики удалённых серверов, если они отправляются из пакета `remote/`.

## Развёртывание

Файл **`.env`** в каталоге `central/` задаёт секреты и опции для MikroTik: SNMP community (`MIKROTIK_SNMP_COMMUNITY`), учётные данные RouterOS API для MKTXP (`MIKROTIK_API_USER`, `MIKROTIK_API_PASSWORD`), профиль **`MKTXP_PROFILE`** и при необходимости **`MKTXP_POE`**, **`MKTXP_W60G`**, **`MKTXP_DHCP`** / **`MKTXP_DHCP_LEASE`** (для профиля `crs`) — полный список см. **`.env.example`**. Скопируйте `.env.example` → `.env` и заполните значения.

```bash
cd central
cp -n .env.example .env   # затем MIKROTIK_SNMP_COMMUNITY, MIKROTIK_API_*, при необходимости MKTXP_*
docker compose pull        # при обновлении репозитория — подтянуть образы
docker compose up -d
```

Если пользователь не в группе **`docker`**, используйте **`sudo docker compose …`**. После смены **`render-config.py`**, **`.env`** (MKTXP) или **`MKTXP_PROFILE`** пересоздайте экспортёр: **`docker compose up -d mktxp --force-recreate`**.

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
- наличие скрейпа MKTXP: `process_virtual_memory_bytes{job="mktxp"}` (см. `scripts/check-monitoring.sh`)

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

**MKTXP и snmp_exporter** публикуют HTTP только на **127.0.0.1** центрального хоста; до **MikroTik** с этого хоста должны быть открыты **UDP/161** (SNMP) и **TCP/8728** (или порт API-SSL при `MKTXP_USE_SSL`), см. раздел MKTXP ниже.

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

Конфиг в контейнере пишется в **`/etc/mktxp`**; процесс запускается как пользователь **`mktxp`** с **`mktxp --cfg-dir /etc/mktxp export`**. Без **`--cfg-dir`** MKTXP читает конфиг из **`~/mktxp`** внутри образа и подставляет шаблон **Sample-Router** вместо вашего устройства (**`CRS326`** и т.д.).

Переменная **`MKTXP_PROFILE`** задаёт объём метрик:

- **`full`** (по умолчанию в `docker-compose`) — максимум коллекторов MKTXP: DHCP и leases, IPv6, DNS, туннели, BGP/BFD, Kid Control, контейнеры RouterOS, **`switch_port`**, **`check_for_updates`** и др. Коллекторы **`poe`** и **`w60g`** по умолчанию **выключены**: на CRS без PoE/W60G в API MKTXP будет сыпать **`no such command prefix`**. Включите только при наличии железа: **`MKTXP_POE=True`**, **`MKTXP_W60G=True`** в **`.env`**.
- **`crs`**, **`minimal`**, **`switch`** — урезанный профиль для коммутатора: Wi‑Fi/CAPsMAN и «тяжёлое» выключены; **`MKTXP_DHCP`**, **`MKTXP_DHCP_LEASE`**, **`MKTXP_POE`** задаются в **`.env`** (по умолчанию выкл.), **`switch_port`** остаётся включённым.

| Переменная | Назначение |
|------------|------------|
| `MKTXP_PROFILE` | **`full`** (по умолчанию) или **`crs`** / **`minimal`** / **`switch`** — см. список выше. |
| `MIKROTIK_API_USER`, `MIKROTIK_API_PASSWORD` | Учётка RouterOS с политикой **`api`**, **`read`** (обязательно). |
| `MIKROTIK_API_HOST`, `MIKROTIK_API_PORT` | Цель API (часто **`192.168.88.1`**, порт **8728**). |
| `MKTXP_ROUTER_SECTION` | Имя секции в конфиге MKTXP (отображается в логах/лейблах), например **`CRS326`**. |
| `MKTXP_USE_SSL`, `MKTXP_PLAINTEXT_LOGIN` | TLS и режим логина (см. MKTXP README / RouterOS). |
| `MKTXP_POE`, `MKTXP_W60G` | При **`True`** — сбор PoE / W60g (если API есть на устройстве). В **`crs`** отдельно задайте **`MKTXP_DHCP`**, **`MKTXP_DHCP_LEASE`**. |

Полный перечень см. **`central/.env.example`**.

На устройстве RouterOS 7:

- Включите сервис **`api`**: `/ip service enable api`, при необходимости ограничьте **`address`** подсетью центра; на **input**‑файрволе разрешите **TCP с центра** на порт API (**8728** или **8729** для API-SSL).

```
/user group add name=mktxp_group policy=api,read
/user add name=mktxp_user group=mktxp_group password=YOUR_STRONG_PASSWORD
```

Запуск на central: **`docker compose up -d mktxp vmagent`**. После правок **`.env`** или **`mktxp/render-config.py`**: **`docker compose up -d mktxp --force-recreate`**.

Проверка: с хоста central **`curl -sf http://127.0.0.1:49090/metrics | head`**; в Explore / VMUI — **`process_virtual_memory_bytes{job="mktxp"}`** или **`up{job="mktxp"}`** (см. **`scripts/check-monitoring.sh`**).

Дашборд: Grafana **ID 13679** (после **`scripts/download-dashboards.*`** файл **`central/dashboards/mktxp.json`**).

LTE и отдельные редкие подсистемы: при ошибках в **`docker compose logs mktxp`** проверьте, что сервис есть на устройстве; для старых версий ROS часть метрик может требовать политику **`test`** у группы пользователя.

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
- **MKTXP** в логах: `no such command prefix` для **PoE** или **w60g** — на устройстве нет этого API (часто CRS без PoE / без W60G). Не включайте **`MKTXP_POE`** / **`MKTXP_W60G`**, если железо не поддерживает.
- MKTXP `Fetching available ROS releases` — включён **`check_for_updates`** (профиль **`full`**); это обращение к RSS MikroTik, не ошибка.
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
├── snmp_exporter/
├── mktxp/                    # entrypoint + render-config под MKTXP (секреты только в .env)
├── rules/                    # Правила алертинга
├── grafana/provisioning/
├── dashboards/
└── scripts/
    ├── download-dashboards.ps1
    ├── download-dashboards.sh
    └── check-monitoring.sh
```
