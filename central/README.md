# Central Server — Grafana + VictoriaMetrics + Alertmanager

Полный стек мониторинга: хранение метрик, визуализация, алертинг. Разворачивается на **центральном сервере**.

## Развёртывание

```bash
cd central
docker compose up -d
```

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

## Дашборды

Скачать предустановленные дашборды (VictoriaMetrics, vmagent, vmalert, Node Exporter, Docker):

```powershell
# Windows PowerShell
.\scripts\download-dashboards.ps1
```

Затем перезапустить Grafana:

```bash
docker compose restart grafana
```

## Alertmanager

По умолчанию алерты идут в `blackhole`. Для Slack, Email и др. настройте `alertmanager/alertmanager.yml`.

## Структура

```
central/
├── docker-compose.yml
├── alertmanager/alertmanager.yml
├── vmagent/prometheus.yml
├── rules/                    # Правила алертинга
├── grafana/provisioning/
├── dashboards/
└── scripts/download-dashboards.ps1
```
