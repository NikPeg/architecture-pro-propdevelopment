# Задание 4. Защита доступа к кластеру Kubernetes

## Описание

Организация ролевого доступа (RBAC) к Kubernetes кластеру PropDevelopment с учетом:
- Организационной структуры компании (4 домена)
- Принципа наименьших привилегий (Least Privilege)
- Разделения обязанностей (Separation of Duties)
- Требований безопасности из предыдущих заданий

## Цели задания

1. ✅ Защитить кластер от несанкционированного доступа
2. ✅ Ограничить привилегированные действия (просмотр секретов) определенными группами
3. ✅ Создать минимум две дополнительные группы (просмотр + настройка)
4. ✅ Разграничить доступ по организационной структуре (домены)

## Структура решения

### 1. Таблица ролей: `roles_table.md`

Детальная таблица со следующими ролями:

#### Основные ClusterRoles (cluster-wide):
- **cluster-admin** - CTO (emergency access, минимальное количество)
- **security-admin** - Команда безопасности (6 человек из Task3)
- **devops-engineer** - DevOps команда (настройка кластера)
- **developer** - Разработчики (просмотр + отладка)
- **viewer** - Бизнес-пользователи (только чтение)
- **monitoring-reader** - Системы мониторинга
- **logs-reader** - Системы логирования
- **ci-cd-deployer** - CI/CD автоматизация

#### Доменные Roles (namespace-specific):
- **domain-admin** - Полное управление своим доменом (Sales, Tenant, Finance, Data)
- **smart-home-operator** - Управление сервисами Умного дома (новая роль из Task3)

**Итого:** 5 основных ролей + 5 доменных = **10 ролей**

### 2. Скрипт создания пользователей: `1-create-users.sh`

Создает **8 пользователей** с сертификатами для доступа к кластеру:

| Пользователь | Роль | Домен/Область |
|--------------|------|---------------|
| olga.cto | cluster-admin | Весь кластер (emergency) |
| ivan.security | security-admin | Весь кластер |
| anna.devops | devops-engineer | Весь кластер |
| dmitry.dev | developer | sales-domain |
| elena.viewer | viewer | Весь кластер (read-only) |
| sergey.sales | domain-admin | sales-domain |
| maria.tenant | domain-admin | tenant-domain |
| alexey.smarthome | smart-home-operator | tenant-domain |

**Технология:** Client certificates (X.509) подписанные CA кластера

**Вывод:**
- Приватные ключи пользователей
- Сертификаты (365 дней)
- Kubeconfig файлы для каждого пользователя
- Добавление в kubectl config

### 3. Скрипт создания ролей: `2-create-roles.sh`

Создает роли в Kubernetes кластере:

**Создаваемые ресурсы:**
- 7 ClusterRoles (cluster-wide доступ)
- 5 Roles в namespace (domain-admin × 4 + smart-home-operator)
- 6 Namespaces для доменов:
  - `sales-domain`
  - `tenant-domain`
  - `finance-domain`
  - `data-domain`
  - `monitoring`
  - `logging`

**Ключевые особенности ролей:**
- **security-admin**: Read-only на все ресурсы + управление NetworkPolicies
- **devops-engineer**: Управление deployments/services + read-only на Secrets (НЕТ изменения!)
- **developer**: Просмотр + port-forward + логи (НЕТ exec, НЕТ Secrets)
- **viewer**: Только чтение (НЕТ Secrets, НЕТ изменений)

### 4. Скрипт привязки пользователей: `3-bind-users-to-roles.sh`

Создает RoleBindings и ClusterRoleBindings:

**Индивидуальные привязки:**
- 4 ClusterRoleBindings (для cluster-wide ролей)
- 4 RoleBindings (для domain-specific ролей)

**Групповые привязки:**
- `security-team` → security-admin
- `devops-team` → devops-engineer
- `viewers` → viewer

**Дополнительно создает:**
- Документацию `RBAC_SUMMARY.md` с примерами команд
- Тестовые команды для проверки прав

## Использование

### Предварительные требования

```bash
# 1. Установить и запустить Minikube
minikube start

# 2. Проверить kubectl
kubectl cluster-info

# 3. Убедиться, что openssl установлен
openssl version
```

### Последовательность выполнения

#### Шаг 1: Создание пользователей

```bash
cd Task4
./1-create-users.sh
```

**Результат:**
- Создано 8 пользователей
- Сертификаты сохранены в `./k8s-users-certs/`
- Пользователи добавлены в kubectl config

#### Шаг 2: Создание ролей

```bash
./2-create-roles.sh
```

**Результат:**
- Создано 7 ClusterRoles
- Создано 5 Roles в domain namespaces
- Создано 6 namespaces
- Манифесты сохранены в `./k8s-rbac-manifests/`

#### Шаг 3: Привязка пользователей к ролям

```bash
./3-bind-users-to-roles.sh
```

**Результат:**
- Создано 8 индивидуальных привязок
- Создано 3 групповых привязок
- Создана документация `RBAC_SUMMARY.md`

### Проверка работы

#### Проверка ролей

```bash
# Список всех ClusterRoles
kubectl get clusterroles | grep -E "(security-admin|devops-engineer|developer|viewer)"

# Список Roles в domain namespaces
kubectl get roles -A | grep -E "(domain-admin|smart-home-operator)"

# Детали роли
kubectl describe clusterrole security-admin
```

#### Проверка привязок

```bash
# Список ClusterRoleBindings
kubectl get clusterrolebindings | grep propdevelopment

# Список RoleBindings
kubectl get rolebindings -A
```

#### Тестирование прав пользователей

**Security Engineer (ivan.security):**
```bash
# Может просматривать секреты
kubectl --context=ivan.security-context get secrets --all-namespaces

# Может просматривать все ресурсы
kubectl --context=ivan.security-context get all --all-namespaces

# Может управлять NetworkPolicies
kubectl --context=ivan.security-context get networkpolicies -A
```

**DevOps Engineer (anna.devops):**
```bash
# Может создавать deployments
kubectl --context=anna.devops-context create deployment test --image=nginx

# Может просматривать секреты (read-only)
kubectl --context=anna.devops-context get secrets

# НЕ может изменять секреты
kubectl --context=anna.devops-context create secret generic test --from-literal=key=value
# Expected: Error (forbidden)

# НЕ может exec в pods
kubectl --context=anna.devops-context exec -it pod-name -- sh
# Expected: Error (forbidden)
```

**Developer (dmitry.dev):**
```bash
# Может просматривать pods в своем namespace
kubectl --context=dmitry.dev-context get pods -n sales-domain

# Может port-forward для отладки
kubectl --context=dmitry.dev-context port-forward pod-name 8080:80 -n sales-domain

# Может просматривать логи
kubectl --context=dmitry.dev-context logs pod-name -n sales-domain

# НЕ может просматривать секреты
kubectl --context=dmitry.dev-context get secrets -n sales-domain
# Expected: Error (forbidden)
```

**Viewer (elena.viewer):**
```bash
# Может просматривать deployments
kubectl --context=elena.viewer-context get deployments --all-namespaces

# НЕ может создавать ресурсы
kubectl --context=elena.viewer-context create deployment test --image=nginx
# Expected: Error (forbidden)

# НЕ может просматривать секреты
kubectl --context=elena.viewer-context get secrets
# Expected: Error (forbidden)
```

**Domain Admin Sales (sergey.sales):**
```bash
# Полное управление в sales-domain
kubectl --context=sergey.sales-context get all -n sales-domain
kubectl --context=sergey.sales-context create deployment app --image=myapp -n sales-domain

# Может управлять секретами в своем namespace
kubectl --context=sergey.sales-context get secrets -n sales-domain

# НЕ может управлять другими namespaces
kubectl --context=sergey.sales-context get pods -n tenant-domain
# Expected: Error (forbidden)
```

**Smart Home Operator (alexey.smarthome):**
```bash
# Может управлять smart-home приложениями
kubectl --context=alexey.smarthome-context get pods -n tenant-domain -l app=smart-home

# Может exec в smart-home pods для отладки
kubectl --context=alexey.smarthome-context exec -it smart-home-pod -- sh

# НЕ может управлять другими приложениями
kubectl --context=alexey.smarthome-context delete deployment tenant-core-app
# Expected: Error (forbidden)
```

## Принципы безопасности

### 1. Least Privilege (Минимальные привилегии)

Каждая роль имеет **минимально необходимые** права:
- DevOps не может изменять Secrets (только read)
- Developer не может exec в pods
- Viewer не может изменять ресурсы

### 2. Separation of Duties (Разделение обязанностей)

- **DevOps** управляет инфраструктурой
- **Security** аудитирует, но не может случайно удалить критичные ресурсы
- **Developers** отлаживают, но не имеют полного доступа
- **Domain Admins** управляют только своим доменом

### 3. Defense in Depth (Эшелонированная защита)

- RBAC на уровне Kubernetes
- NetworkPolicies для сетевой изоляции (планируется)
- PodSecurityPolicies для ограничения capabilities (планируется)
- Audit Logging для детектирования аномалий

### 4. Blast Radius Minimization

Доменные роли ограничены своим namespace, чтобы компрометация одного домена не затронула другие.

## Соответствие требованиям задания

| Требование | Реализация | Статус |
|------------|------------|--------|
| Ограничить доступ к управлению кластером | Созданы роли с разными уровнями доступа | ✅ |
| Привилегированные действия только для определенных групп | security-admin может просматривать Secrets | ✅ |
| Минимум 2 дополнительные группы | viewer (просмотр) + devops-engineer (настройка) | ✅ |
| Разграничение по организационной структуре | 4 domain-admin роли для 4 доменов | ✅ |
| Минимум 2 пользователя | Создано 8 пользователей | ✅ |

## Интеграция с предыдущими заданиями

### Из Task2 (Security Checklist):

**Проблема:** Один специалист по ИБ недостаточно

**Решение в Task4:** Создана роль `security-admin` для команды из **6 специалистов** (из Task3):
- Security Architect
- 2 Security Engineers
- 2 SOC Analysts
- Incident Response Lead

### Из Task3 (Smart Home Integration):

**Новая роль:** `smart-home-operator` специально для управления сервисами Умного дома
- Доступ только к компонентам с label `app=smart-home`
- Ограниченный доступ в `tenant-domain`
- Поддержка интеграции с партнером

## Дополнительные возможности

### Аудит действий

Все действия пользователей логируются Kubernetes Audit Log:

```bash
# Просмотр недавних событий
kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# Действия конкретного пользователя
kubectl get events --all-namespaces --field-selector involvedObject.name=ivan.security
```

### Управление доступом

#### Добавление нового пользователя

1. Модифицируйте `1-create-users.sh` (добавьте вызов `create_user`)
2. Запустите скрипт
3. Модифицируйте `3-bind-users-to-roles.sh` (добавьте привязку)
4. Запустите скрипт

#### Отзыв доступа

```bash
# Удалить ClusterRoleBinding
kubectl delete clusterrolebinding username-binding

# Удалить RoleBinding
kubectl delete rolebinding username-binding -n namespace-name

# Удалить context из kubectl
kubectl config delete-context username-context
```

#### Регулярный Access Review

Рекомендуется **ежеквартально** проверять:
```bash
# Кто имеет какие роли?
kubectl get rolebindings,clusterrolebindings -A -o wide

# Неиспользуемые привязки
kubectl get clusterrolebindings -o json | jq '.items[] | select(.subjects[].name == "old-user")'
```

## Troubleshooting

### Пользователь не может выполнить команду

1. Проверьте контекст:
```bash
kubectl config get-contexts | grep username
kubectl config use-context username-context
```

2. Проверьте привязку роли:
```bash
kubectl get rolebindings,clusterrolebindings -A | grep username
```

3. Проверьте права роли:
```bash
kubectl describe clusterrole role-name
```

4. Проверьте, какие действия доступны:
```bash
kubectl auth can-i --list --as=username
```

### Скрипт завершился с ошибкой

1. **Minikube не запущен:**
```bash
minikube start
```

2. **Нет прав администратора:**
```bash
kubectl auth can-i create clusterroles
# Должно вернуть: yes
```

3. **Уже существующие ресурсы:**
```bash
# Удалите старые ресурсы
kubectl delete clusterrole security-admin
kubectl delete namespace sales-domain
# И запустите скрипты заново
```

## Файлы и директории

```
Task4/
├── README.md                          # Этот файл
├── roles_table.md                     # Таблица ролей (задание)
├── 1-create-users.sh                  # Скрипт создания пользователей ⭐
├── 2-create-roles.sh                  # Скрипт создания ролей ⭐
├── 3-bind-users-to-roles.sh           # Скрипт привязки пользователей ⭐
├── k8s-users-certs/                   # Сертификаты пользователей (создается)
│   ├── ivan.security/
│   │   ├── ivan.security.key
│   │   ├── ivan.security.crt
│   │   └── ivan.security-kubeconfig.yaml
│   └── ... (другие пользователи)
└── k8s-rbac-manifests/                # YAML манифесты (создается)
    ├── clusterrole-security-admin.yaml
    ├── clusterrole-devops-engineer.yaml
    ├── role-domain-admin-sales.yaml
    ├── role-smart-home-operator.yaml
    ├── RBAC_SUMMARY.md
    └── bindings/
        ├── crb-security-team-admin.yaml
        └── ... (другие bindings)
```

⭐ = Основные файлы для сдачи задания

## Метрики успеха

- ✅ Создано **10 ролей** (5 основных + 5 доменных)
- ✅ Создано **8 пользователей** (больше требуемых 2)
- ✅ Создано **11 привязок** (8 индивидуальных + 3 групповых)
- ✅ Применен принцип **Least Privilege**
- ✅ Реализовано **Separation of Duties**
- ✅ Разграничение по **4 доменам** организации

## Следующие шаги (опционально)

1. **NetworkPolicies**: Изоляция доменов на сетевом уровне
2. **PodSecurityPolicies**: Ограничение capabilities контейнеров
3. **OPA/Gatekeeper**: Policy-as-Code для дополнительных ограничений
4. **External Secrets Operator**: Интеграция с HashiCorp Vault
5. **Service Mesh (Istio)**: mTLS между сервисами

## Контакты и эскалация

- **Security Team**: security-team@propdevelopment.ru
- **DevOps Team**: devops-team@propdevelopment.ru
- **Incident Response**: incidents@propdevelopment.ru (24/7)

---

**Дата:** Ноябрь 2025  
**Версия:** 1.0  
**Автор:** Security Architecture Team  
**Статус:** Готово к использованию

