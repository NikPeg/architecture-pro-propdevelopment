# Таблица ролей и полномочий для Kubernetes кластера PropDevelopment

## Обзор ролевой модели

Ролевая модель разработана с учетом:
- Организационной структуры компании (4 домена: Продажи, ЖКУ, Финансы, Дата)
- Принципа наименьших привилегий (Least Privilege)
- Разделения обязанностей (Separation of Duties)
- Требований безопасности из Task2 и Task3

## Основные роли (ClusterRoles)

| Роль | Права роли | Группы пользователей |
| --- | --- | --- |
| **cluster-admin** | **Полный доступ ко всем ресурсам кластера:**<br>- Все операции (get, list, create, update, patch, delete) на всех ресурсах<br>- Управление RBAC (roles, rolebindings, clusterroles, clusterrolebindings)<br>- Доступ к Secrets во всех namespace<br>- Управление Namespaces<br>- Управление Nodes<br>- Управление PersistentVolumes<br>- Доступ к метрикам и логам<br>- Выполнение команд в Pods (exec, port-forward) | **CTO** (Chief Technology Officer)<br>**Head of Infrastructure**<br>**Principal DevOps Engineer** (emergency access only)<br><br>*Минимальное количество пользователей с этой ролью!* |
| **security-admin** | **Специализированные права для команды безопасности:**<br>- **get, list** на все ресурсы во всех namespace (read-only на ресурсы)<br>- **get, list, watch** на Secrets (для аудита)<br>- **get, list, watch** на RBAC ресурсы (для проверки прав)<br>- **get, list** на Events (для анализа инцидентов)<br>- **get, list** на Logs (для расследования)<br>- **get, list** на Metrics (для мониторинга)<br>- **create, update, delete** на NetworkPolicies (для изоляции при инцидентах)<br>- **create, update, delete** на PodSecurityPolicies<br>- **НЕТ прав на delete/update** критичных ресурсов (защита от случайного удаления) | **Security Architect**<br>**Security Engineers** (2 чел.)<br>**SOC Analysts** (2 чел.)<br>**Incident Response Lead**<br><br>*Расширенная команда ИБ (6 человек из Task3)* |
| **devops-engineer** | **Управление deployment'ами и инфраструктурой:**<br>- **Все операции** на: Deployments, StatefulSets, DaemonSets, ReplicaSets<br>- **Все операции** на: Services, Ingresses, ConfigMaps<br>- **Все операции** на: Jobs, CronJobs<br>- **Все операции** на: PersistentVolumeClaims<br>- **get, list, watch** на Pods (без exec!)<br>- **get, list, watch** на Events<br>- **get, list, watch** на Logs<br>- **get, list** на Secrets (НЕТ прав на create/update/delete!)<br>- **get, list, watch** на Nodes, Metrics<br>- **create, update, delete** на HorizontalPodAutoscalers | **DevOps Team** (все DevOps инженеры)<br>**Site Reliability Engineers (SRE)**<br>**Infrastructure Engineers**<br><br>*Основная команда для управления кластером* |
| **developer** | **Разработка и отладка приложений в своем namespace:**<br>- **get, list, watch** на Pods, Deployments, Services<br>- **get, list, watch, create, delete** на Pods/log (доступ к логам)<br>- **get, list, watch** на ConfigMaps (read-only)<br>- **get, list, watch** на Events<br>- **create, delete** на Pods (для отладки, но не update!)<br>- **port-forward** на Pods (для локальной отладки)<br>- **НЕТ доступа** к Secrets<br>- **НЕТ exec** в Pods (безопасность)<br>- Ограничение на **свой namespace** | **Разработчики** всех доменов:<br>- Sales Team Developers<br>- Tenant Services Developers<br>- Finance Team Developers<br>- Data Team Developers<br><br>*Доступ только к namespace своей команды* |
| **viewer** | **Только чтение всех ресурсов (кроме секретов):**<br>- **get, list, watch** на: Pods, Deployments, Services, ConfigMaps<br>- **get, list, watch** на: Events, Logs<br>- **get, list, watch** на: Ingresses, PVCs<br>- **get, list, watch** на: HPA, Jobs, CronJobs<br>- **get, list, watch** на: Namespaces (список)<br>- **get** на: Metrics (для мониторинга)<br>- **НЕТ доступа** к Secrets<br>- **НЕТ прав** на изменение ресурсов<br>- **НЕТ exec, port-forward** | **Product Owners**<br>**Business Analysts**<br>**QA Engineers** (тестировщики)<br>**Technical Support**<br>**Managers** (для мониторинга статуса)<br>**Audience BI** (аналитики)<br><br>*Пользователи, которым нужен обзор, но не управление* |

## Доменные роли (Roles в namespace)

| Роль | Права роли | Группы пользователей |
| --- | --- | --- |
| **domain-admin-sales** | **Полное управление в namespace `sales-domain`:**<br>- **Все операции** на всех ресурсах в namespace<br>- **get, list, watch, create, update, delete** на Secrets в своем namespace<br>- **exec, port-forward, logs** на Pods<br>- **create, update, delete** на RBAC в своем namespace (RoleBindings)<br>- **НЕТ доступа** к другим namespace<br>- **НЕТ прав** на изменение лимитов namespace (ResourceQuota, LimitRange) | **Head of Sales IT**<br>**Lead DevOps Engineer (Sales Domain)**<br>**Senior Developers (Sales Domain)**<br><br>*Ответственные за домен Продаж* |
| **domain-admin-tenant** | **Полное управление в namespace `tenant-domain`:**<br>- **Все операции** на всех ресурсах в namespace<br>- **get, list, watch, create, update, delete** на Secrets в своем namespace<br>- **exec, port-forward, logs** на Pods<br>- **create, update, delete** на RBAC в своем namespace (RoleBindings)<br>- **НЕТ доступа** к другим namespace<br>- **НЕТ прав** на изменение лимитов namespace | **Head of Tenant Services IT**<br>**Lead DevOps Engineer (Tenant Domain)**<br>**Senior Developers (Tenant Domain)**<br>**Smart Home Integration Lead** (новая роль из Task3)<br><br>*Ответственные за домен ЖКУ и Умный дом* |
| **domain-admin-finance** | **Полное управление в namespace `finance-domain`:**<br>- **Все операции** на всех ресурсах в namespace<br>- **get, list, watch, create, update, delete** на Secrets в своем namespace<br>- **exec, port-forward, logs** на Pods<br>- **create, update, delete** на RBAC в своем namespace (RoleBindings)<br>- **НЕТ доступа** к другим namespace<br>- **Строгий аудит** всех действий (compliance)<br>- **НЕТ прав** на изменение лимитов namespace | **Head of Finance IT**<br>**Lead DevOps Engineer (Finance Domain)**<br>**Senior Developers (Finance Domain)**<br><br>*Ответственные за домен Финансов*<br>*Повышенные требования к аудиту!* |
| **domain-admin-data** | **Полное управление в namespace `data-domain`:**<br>- **Все операции** на всех ресурсов в namespace<br>- **get, list, watch, create, update, delete** на Secrets в своем namespace<br>- **exec, port-forward, logs** на Pods<br>- **create, update, delete** на RBAC в своем namespace (RoleBindings)<br>- **get, list** на PersistentVolumes (для DWH)<br>- **НЕТ доступа** к другим namespace<br>- **НЕТ прав** на изменение лимитов namespace | **Head of Data Engineering**<br>**Lead DevOps Engineer (Data Domain)**<br>**Data Engineers**<br>**ML Engineers** (для будущих ML/AI сервисов)<br><br>*Ответственные за домен обработки данных* |
| **smart-home-operator** | **Управление сервисами Умного дома в namespace `tenant-domain`:**<br>- **Все операции** на Deployments с label `app=smart-home`<br>- **get, list, watch** на Pods с label `app=smart-home`<br>- **get, list, watch, update** на ConfigMaps с label `app=smart-home`<br>- **get, list** на Secrets с label `app=smart-home` (read-only!)<br>- **get, list, watch** на Services, Ingresses для smart-home<br>- **exec, logs** на Pods (для отладки)<br>- **create, update** на HPA для smart-home<br>- **НЕТ прав** на другие приложения в namespace | **Smart Home Integration Team** (из Task3)<br>**Smart Home DevOps Engineers**<br>**Partner Integration Specialists**<br><br>*Новая специализированная роль для Task3*<br>*Доступ только к компонентам Умного дома* |

## Служебные роли

| Роль | Права роли | Группы пользователей |
| --- | --- | --- |
| **monitoring-reader** | **Доступ к метрикам и мониторингу:**<br>- **get, list, watch** на Metrics API<br>- **get, list, watch** на Pods (для Prometheus)<br>- **get, list, watch** на Nodes (для Prometheus)<br>- **get, list, watch** на Services, Endpoints<br>- **get, list, watch** на Events<br>- **НЕТ доступа** к Secrets<br>- **НЕТ прав** на изменение ресурсов | **Prometheus Service Account**<br>**Grafana Service Account**<br>**Monitoring Team**<br>**SRE Team** (для дежурств)<br><br>*Для систем мониторинга* |
| **logs-reader** | **Доступ к логам приложений:**<br>- **get, list, watch** на Pods/log<br>- **get, list, watch** на Events<br>- **get, list, watch** на Pods (метаданные)<br>- **НЕТ exec, port-forward**<br>- **НЕТ доступа** к Secrets | **Fluentd/Fluent Bit Service Account**<br>**ELK Stack Service Account**<br>**Support Team** (для траблшутинга)<br>**QA Team** (для анализа багов)<br><br>*Для систем централизованного логирования* |
| **ci-cd-deployer** | **Автоматический деплой из CI/CD:**<br>- **get, list, watch, create, update, patch** на Deployments, Services<br>- **get, list, watch, create, update** на ConfigMaps<br>- **get, list** на Secrets (read-only, для validation)<br>- **create, update** на Jobs (для миграций БД)<br>- **get, list, watch** на Pods, Events<br>- **rollout** операции на Deployments<br>- **НЕТ delete** на Deployments (безопасность)<br>- **НЕТ exec, port-forward** | **GitLab CI Service Account**<br>**Jenkins Service Account**<br>**ArgoCD Service Account**<br>**GitHub Actions Service Account**<br><br>*Служебные аккаунты для автоматизации*<br>*НЕ для людей!* |

## Специальные ограничения и политики

### 1. NetworkPolicies (изоляция namespace)

Каждый домен должен быть изолирован на сетевом уровне:

```yaml
# Разрешен трафик только:
sales-domain     → api-gateway, auth-service, dwh
tenant-domain    → api-gateway, auth-service, smart-home-partner, dwh
finance-domain   → auth-service, dwh
data-domain      → (принимает от всех доменов)
smart-home       → api-gateway, tenant-core-app, partner-platform

# Запрещен прямой трафик между доменами (кроме через API Gateway)
```

### 2. PodSecurityPolicies (для критичных namespace)

**finance-domain** и **tenant-domain** (из-за биометрии):
- `allowPrivilegeEscalation: false`
- `runAsNonRoot: true`
- `readOnlyRootFilesystem: true`
- Запрет на `hostNetwork`, `hostPID`, `hostIPC`
- Ограничение capabilities (только NET_BIND_SERVICE)

### 3. ResourceQuotas (лимиты ресурсов)

Каждый namespace имеет квоты:
- **sales-domain**: 50 Pods, 100 GB RAM, 50 CPU cores
- **tenant-domain**: 70 Pods, 150 GB RAM, 70 CPU cores (больше для smart-home)
- **finance-domain**: 30 Pods, 80 GB RAM, 40 CPU cores
- **data-domain**: 40 Pods, 200 GB RAM, 100 CPU cores (для DWH)

### 4. Аудит (Audit Logging)

Логирование всех действий для ролей:
- **cluster-admin**: ВСЕ операции (RequestResponse level)
- **security-admin**: ВСЕ операции (RequestResponse level)
- **domain-admin-\***: Все операции в своем namespace (Metadata level)
- **devops-engineer**: Create/Update/Delete операции (Metadata level)
- **developer**: Create/Delete операции (Metadata level)

Логи должны храниться **1 год** (соответствие ФЗ-152).

## Матрица прав (сводная таблица)

| Роль | Namespaces | Deployments | Secrets | Pods/Exec | Logs | RBAC | Nodes |
|------|------------|-------------|---------|-----------|------|------|-------|
| cluster-admin | ✅ Все | ✅ CUD | ✅ CUD | ✅ Exec | ✅ All | ✅ CUD | ✅ View |
| security-admin | ✅ Все (RO) | ✅ View | ✅ View | ❌ No | ✅ View | ✅ View | ✅ View |
| devops-engineer | ✅ Все | ✅ CUD | ✅ View | ❌ No | ✅ View | ❌ No | ✅ View |
| developer | ⚠️ Свой | ✅ View | ❌ No | ⚠️ Port-fwd | ✅ View | ❌ No | ❌ No |
| viewer | ✅ Все (RO) | ✅ View | ❌ No | ❌ No | ✅ View | ❌ No | ❌ No |
| domain-admin-* | ⚠️ Один | ✅ CUD | ✅ CUD | ✅ Exec | ✅ All | ⚠️ Namespace | ❌ No |
| smart-home-operator | ⚠️ tenant | ⚠️ Smart-home | ✅ View | ⚠️ Smart-home | ✅ View | ❌ No | ❌ No |
| ci-cd-deployer | ⚠️ Свой | ✅ CU (no D) | ✅ View | ❌ No | ✅ View | ❌ No | ❌ No |

**Легенда:**
- ✅ = Полный доступ
- ✅ CUD = Create, Update, Delete
- ✅ CU = Create, Update (без Delete)
- ✅ View = Get, List, Watch (только чтение)
- ⚠️ = Ограниченный доступ (см. описание роли)
- ❌ = Нет доступа

## Принципы безопасности

### 1. Least Privilege (Минимальные привилегии)
Каждая роль имеет **минимально необходимые** права для выполнения своих функций.

### 2. Separation of Duties (Разделение обязанностей)
- **DevOps** управляет инфраструктурой, но не имеет полного доступа к секретам
- **Security** может аудитировать, но не может случайно удалить критичные ресурсы
- **Developers** могут отлаживать, но не имеют exec в продакшн подах

### 3. Defense in Depth (Эшелонированная защита)
- RBAC на уровне Kubernetes
- NetworkPolicies для сетевой изоляции
- PodSecurityPolicies для ограничения возможностей контейнеров
- Audit Logging для детектирования аномалий

### 4. Blast Radius Minimization (Минимизация радиуса поражения)
Доменные роли ограничены своим namespace, чтобы компрометация одного домена не затронула другие.

## Процесс управления доступом

### Onboarding нового сотрудника

1. **HR уведомляет Security Team** о новом сотруднике
2. **Security создает пользователя** (скрипт `1-create-users.sh`)
3. **Team Lead запрашивает роль** через Jira/ServiceNow
4. **Security Architect утверждает** роль
5. **DevOps применяет RoleBinding** (скрипт `3-bind-users-to-roles.sh`)
6. **Новый сотрудник получает kubeconfig** (с ограниченным сроком действия)
7. **Security проводит onboarding** по правилам работы с кластером

### Offboarding сотрудника

1. **HR уведомляет Security Team** об увольнении
2. **Security немедленно отзывает сертификат** (в течение 1 часа)
3. **DevOps удаляет RoleBindings** (в течение 4 часов)
4. **Security проводит аудит** действий пользователя за последние 30 дней

### Регулярный Access Review

**Ежеквартально** Security Team проводит пересмотр прав:
- Кто имеет какие роли?
- Используются ли права?
- Актуальны ли роли для текущих обязанностей?
- Есть ли пользователи с избыточными правами?

## Риски и митигация

| Риск | Вероятность | Влияние | Митигация |
|------|-------------|---------|-----------|
| Компрометация cluster-admin | Низкая | 🔴 Критическое | Минимальное количество админов, MFA, аудит всех действий |
| Утечка Secrets | Средняя | 🔴 Критическое | Ограниченный доступ, External Secrets Operator, шифрование etcd |
| Insider threat (инсайдер) | Низкая | 🟠 Высокое | Audit logging, anomaly detection, separation of duties |
| Случайное удаление ресурсов | Средняя | 🟠 Высокое | Запрет delete для некоторых ролей, backups, GitOps |
| Privilege escalation | Низкая | 🔴 Критическое | PodSecurityPolicies, регулярный пентест, мониторинг RBAC изменений |

## Compliance

Ролевая модель соответствует:
- ✅ **ISO/IEC 27001** - управление доступом
- ✅ **ФЗ-152** - разграничение доступа к персональным данным
- ✅ **PCI DSS** - для finance-domain (платежные данные)
- ✅ **CIS Kubernetes Benchmark** - лучшие практики безопасности

---

**Дата создания:** Ноябрь 2025  
**Версия:** 1.0  
**Владелец:** Security Architecture Team  
**Утверждено:** CTO, CISO  
**Следующий пересмотр:** Февраль 2026 (через 3 месяца)

