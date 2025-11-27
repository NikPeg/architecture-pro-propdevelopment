# Отчёт по результатам анализа Kubernetes Audit Log

## Дата анализа: 27 ноября 2025
## Аналитик: Security Team PropDevelopment
## Кластер: PropDevelopment Production
## Namespace: secure-ops (тестовый)

---

## Подозрительные события

### 1. Доступ к секретам

**Кто:** `system:serviceaccount:secure-ops:monitoring`

**Где:** Namespace `kube-system`, попытка доступа к секретам

**Когда:** В рамках симуляции инцидента

**Действие:** 
- Проверка прав: `kubectl auth can-i get secrets`
- Попытка чтения секрета из namespace `kube-system`

**Почему подозрительно:**
- ServiceAccount `monitoring` пытается получить доступ к секретам в **другом namespace** (kube-system)
- Namespace `kube-system` содержит критичные секреты кластера (service account tokens, certificates)
- Обычному мониторингу НЕ требуется доступ к секретам в kube-system
- Это может быть попытка **privilege escalation** (повышения привилегий)

**Уровень угрозы:** 🔴 **КРИТИЧЕСКИЙ**

**Рекомендации:**
- Проверить, почему ServiceAccount `monitoring` имеет такие права
- Удалить избыточные права (принцип Least Privilege)
- Настроить алерт на доступ к секретам kube-system от нестандартных пользователей

---

### 2. Привилегированные поды

**Кто:** Пользователь с правами создания подов в namespace `secure-ops`

**Что создано:** Pod `privileged-pod` с `privileged: true`

**Когда:** В рамках симуляции инцидента

**Конфигурация пода:**
```yaml
spec:
  containers:
  - name: pwn
    image: alpine
    securityContext:
      privileged: true  # <-- ОПАСНО!
```

**Почему подозрительно:**
- **Privileged pod** имеет доступ ко ВСЕМ capabilities хост-системы
- Может монтировать host filesystem
- Может выполнять privileged операции на node
- Фактически имеет root доступ к node
- Это **один из самых опасных векторов атаки** в Kubernetes

**Комментарий:**
Привилегированные поды НЕ должны создаваться без explicit approval от Security Team. Это явное нарушение PodSecurityPolicy (из Task4). В production кластере такие поды должны быть **автоматически заблокированы** с помощью:
- PodSecurityPolicy (устаревшее в K8s 1.25+)
- Pod Security Admission (новый механизм)
- OPA/Gatekeeper policies

**Уровень угрозы:** 🔴 **КРИТИЧЕСКИЙ**

**Рекомендации:**
- Немедленно удалить pod: `kubectl delete pod privileged-pod -n secure-ops`
- Внедрить PodSecurityPolicy или Pod Security Standards (restricted mode)
- Провести расследование: кто создал этот pod и зачем
- Проверить node на следы компрометации

---

### 3. Использование kubectl exec в чужом поде

**Кто:** Пользователь в namespace `secure-ops`

**Где:** Попытка exec в pod `coredns-*` в namespace `kube-system`

**Что делал:** Попытка выполнить команду `cat /etc/resolv.conf` в поде CoreDNS

**Когда:** В рамках симуляции инцидента

**Команда:**
```bash
kubectl exec -n kube-system coredns-7c65d6cfc9-5rvwm -- cat /etc/resolv.conf
```

**Почему подозрительно:**
- Попытка выполнить команду в **критичном системном поде** (CoreDNS)
- CoreDNS - это ключевой компонент Kubernetes (DNS резолвинг)
- Пользователь из namespace `secure-ops` НЕ должен иметь доступа к kube-system
- Это может быть попытка:
  - Reconnaissance (разведка инфраструктуры)
  - Получение конфигурационных данных
  - Поиск уязвимостей в системных компонентах
  - Подготовка к дальнейшей атаке

**Результат:** Команда завершилась с ошибкой (файл cat не найден), но сама **попытка exec была успешна** (что уже проблема!)

**Уровень угрозы:** 🔴 **КРИТИЧЕСКИЙ**

**Рекомендации:**
- Проверить RBAC: кто имеет права exec в kube-system
- Удалить избыточные права
- Настроить алерт на все exec команды в kube-system
- Ограничить exec права только для DevOps и Security команд

---

### 4. Создание RoleBinding с правами cluster-admin

**Кто:** Пользователь с правами создания RoleBindings в namespace `secure-ops`

**Что создано:** RoleBinding `escalate-binding`

**К чему привело:** ServiceAccount `monitoring` теперь имеет права **cluster-admin**

**Конфигурация:**
```yaml
subjects:
- kind: ServiceAccount
  name: monitoring
  namespace: secure-ops
roleRef:
  kind: ClusterRole
  name: cluster-admin  # <-- КРИТИЧНО!
```

**Почему критично:**
- **Privilege Escalation** (повышение привилегий) из обычного ServiceAccount до cluster-admin
- `cluster-admin` = **полный контроль над кластером** (все ресурсы, все namespaces)
- ServiceAccount `monitoring` создан для мониторинга, а не для администрирования
- Это **компрометация кластера** - атакующий теперь имеет полный доступ

**Что может сделать скомпрометированный ServiceAccount:**
- ✓ Читать ВСЕ секреты (включая токены, пароли, ключи API)
- ✓ Создавать/изменять/удалять любые ресурсы
- ✓ Выполнять команды в любых подах (exec)
- ✓ Изменять RBAC правила (создавать новых админов)
- ✓ Получить доступ к nodes
- ✓ Экспортировать данные из кластера

**Уровень угрозы:** 🔴 **КРИТИЧЕСКИЙ - КОМПРОМЕТАЦИЯ КЛАСТЕРА**

**Немедленные действия:**
1. **СРОЧНО** удалить RoleBinding: `kubectl delete rolebinding escalate-binding -n secure-ops`
2. **СРОЧНО** отозвать все токены ServiceAccount `monitoring`
3. Провести полный аудит действий этого ServiceAccount за последние 24 часа
4. Проверить, не создал ли он дополнительные RoleBindings
5. Проверить, не эксфильтрировал ли данные из кластера

**Рекомендации:**
- Внедрить **RBAC ограничения** на создание RoleBindings (из Task4)
- Запретить обычным пользователям привязывать ClusterRole `cluster-admin`
- Использовать **OPA/Gatekeeper** для автоматической блокировки опасных RoleBindings
- Настроить **алерт** на создание RoleBindings с высокими привилегиями

---

### 5. Удаление audit-policy.yaml

**Кто:** Пользователь с правами admin (имперсонация: `--as=admin`)

**Что пытался сделать:** Удалить audit policy файл

**Команда:**
```bash
kubectl delete -f /etc/kubernetes/audit-policy.yaml --as=admin
```

**Результат:** Ошибка (файл не существует как Kubernetes ресурс)

**Почему критично:**
- **Попытка отключить аудит** - классическая техника злоумышленников
- После отключения аудита все дальнейшие действия НЕ будут логироваться
- Это позволяет атакующему действовать незаметно
- "Covering tracks" - заметание следов

**Возможные последствия:**
- Если бы удалось отключить аудит, все последующие атаки остались бы незамеченными
- Невозможность расследовать инцидент (нет логов)
- Нарушение compliance требований (ФЗ-152 требует аудит доступа к ПД)

**Уровень угрозы:** 🔴 **КРИТИЧЕСКИЙ**

**Рекомендации:**
- Audit policy файл должен быть **immutable** (защищен от изменений)
- Доступ к изменению audit policy ТОЛЬКО у CTO/CISO
- Настроить **алерт** на любые попытки изменения audit configuration
- Хранить audit logs в **отдельном защищенном хранилище** (недоступном из кластера)
- Использовать **External Audit Logging** (отправка логов в SIEM в реальном времени)

---

## Дополнительные инциденты (обнаружены при анализе)

### 6. Создание подозрительного секрета `aws-credentials`

**Что:** Secret с AWS credentials

**Почему подозрительно:**
- Секрет с credentials облачного провайдера
- Может быть использован для:
  - Exfiltration данных в AWS
  - Запуск вредоносных ресурсов за счет компании
  - Pivot атака (переход из K8s в облачную инфраструктуру)

**Уровень угрозы:** 🟠 **ВЫСОКИЙ**

**Рекомендации:**
- Проверить содержимое секрета
- Если реальные credentials - немедленно ротировать
- Внедрить External Secrets Operator (секреты из HashiCorp Vault, не хранить в K8s)

### 7. Создание пода с host network

**Что:** Pod `host-network-pod` с `hostNetwork: true`

**Почему опасно:**
- Pod использует **сетевой namespace хоста** (node)
- Имеет прямой доступ к host network interfaces
- Может перехватывать трафик других подов на node (sniffing)
- Может атаковать другие nodes через host network
- Bypasses NetworkPolicies!

**Уровень угрозы:** 🔴 **КРИТИЧЕСКИЙ**

**Рекомендации:**
- Удалить pod немедленно
- Заблокировать `hostNetwork: true` через PodSecurityPolicy

### 8. Создание небезопасной NetworkPolicy `allow-all`

**Что:** NetworkPolicy разрешающая весь трафик

**Почему опасно:**
- Отменяет все другие ограничения NetworkPolicy
- Открывает все поды для доступа
- Bypasses security controls из Task5

**Уровень угрозы:** 🟠 **ВЫСОКИЙ**

**Рекомендации:**
- Удалить политику
- Валидировать NetworkPolicies перед применением (OPA/Gatekeeper)

---

## Анализ ошибок политики RBAC

### Выявленные проблемы:

#### 1. Отсутствие ограничений на создание RoleBindings

**Проблема:** Пользователь смог создать RoleBinding с ClusterRole `cluster-admin`

**Root cause:** 
- Нет ограничений на `escalate` verb для RoleBindings
- Любой пользователь с правами `create rolebindings` может привязать **любую** роль

**Правильная конфигурация (из Task4):**
```yaml
# Domain Admin НЕ должен иметь права привязывать cluster-admin
# Только на роли внутри своего namespace
rules:
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["rolebindings"]
  verbs: ["create"]
  # Добавить ограничение через validating webhook
```

#### 2. Избыточные права ServiceAccount

**Проблема:** ServiceAccount `monitoring` смог проверять доступ к секретам

**Root cause:**
- ServiceAccount создан без явного определения прав
- По умолчанию получил права из default ServiceAccount (если есть)
- Нет принципа Least Privilege

**Решение:**
```yaml
# ServiceAccount для мониторинга должен иметь ТОЛЬКО:
rules:
- apiGroups: [""]
  resources: ["pods", "nodes", "services"]
  verbs: ["get", "list", "watch"]
# БЕЗ доступа к secrets!
```

#### 3. Отсутствие PodSecurityPolicy

**Проблема:** Удалось создать privileged и hostNetwork поды

**Root cause:**
- PodSecurityPolicy не настроена (или отключена в новых версиях K8s)
- Нет Pod Security Admission контроллера
- Нет валидации через OPA/Gatekeeper

**Решение (из Task4):**
Включить Pod Security Standards:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: secure-ops
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

#### 4. Отсутствие аудита создания RBAC ресурсов

**Проблема:** RoleBinding с cluster-admin создан без уведомления Security Team

**Root cause:**
- Нет real-time мониторинга RBAC изменений
- Нет алертов на опасные операции

**Решение:**
- Настроить алерты в SIEM на создание RoleBindings/ClusterRoleBindings
- Webhook для уведомления Security Team
- Require approval для изменений RBAC

---

## Компрометация кластера

### Что можно считать компрометацией:

#### ✅ Подтвержденная компрометация:

**1. Privilege Escalation через RoleBinding**
- ServiceAccount `monitoring` получил права `cluster-admin`
- **Это ПОЛНАЯ компрометация кластера**
- Злоумышленник теперь может:
  - Читать все секреты (credentials, API keys, токены)
  - Создавать вредоносные поды
  - Изменять существующие приложения
  - Эксфильтровать данные
  - Создавать бэкдоры

**Severity:** 🔴 P0 - CRITICAL

#### ⚠️ Индикаторы компрометации (IoC):

**2. Privileged Pod**
- Создан pod с полным доступом к host системе
- Может быть использован для:
  - Escape из контейнера на host
  - Установка rootkit на node
  - Перехват трафика других подов

**Severity:** 🔴 P0 - CRITICAL

**3. HostNetwork Pod**
- Bypasses сетевую изоляцию
- Может снифать трафик других подов
- Может атаковать другие nodes

**Severity:** 🔴 P0 - CRITICAL

**4. Попытка доступа к kube-system secrets**
- Reconnaissance кластерной инфраструктуры
- Подготовка к дальнейшей атаке

**Severity:** 🟠 P1 - HIGH

**5. Попытка отключения аудита**
- Классическая техника "covering tracks"
- Подготовка к скрытой активности

**Severity:** 🔴 P0 - CRITICAL

---

## Timeline инцидента (реконструкция)

| Время | Событие | Severity | Комментарий |
|-------|---------|----------|-------------|
| T+0s | Создан namespace `secure-ops` | 🟢 INFO | Легитимное действие |
| T+1s | Создан ServiceAccount `monitoring` | 🟢 INFO | Легитимное |
| T+2s | Создан pod `attacker-pod` | 🟡 LOW | Обычный pod |
| T+3s | Проверка прав: `auth can-i get secrets` | 🟡 SUSPICIOUS | Reconnaissance |
| T+4s | **Попытка чтения secrets в kube-system** | 🟠 HIGH | **Атака начинается** |
| T+5s | **Создан privileged pod** | 🔴 CRITICAL | **Критичное нарушение** |
| T+6s | **kubectl exec в coredns** | 🔴 CRITICAL | **Латеральное движение** |
| T+7s | Попытка удалить audit-policy | 🔴 CRITICAL | **Covering tracks** |
| T+8s | **Создан RoleBinding cluster-admin** | 🔴 CRITICAL | **ПОЛНАЯ КОМПРОМЕТАЦИЯ** |
| T+9s | Создан секрет aws-credentials | 🟠 HIGH | Подготовка к exfiltration |
| T+10s | Создан hostNetwork pod | 🔴 CRITICAL | Network sniffing |
| T+11s | Создана allow-all NetworkPolicy | 🟠 HIGH | Отключение изоляции |

**Вывод:** Это **APT-подобная атака** (Advanced Persistent Threat) с несколькими этапами:
1. Reconnaissance (разведка)
2. Initial Access (первоначальный доступ)
3. Privilege Escalation (повышение привилегий) ← **Успешно**
4. Defense Evasion (обход защиты) ← Попытка
5. Persistence (закрепление) ← В процессе
6. Exfiltration (кража данных) ← Подготовка

---

## Индикаторы компрометации (IoC)

### Kubernetes-specific IoCs:

- ✅ Создание privileged pods
- ✅ Создание hostNetwork pods
- ✅ RoleBinding/ClusterRoleBinding с высокими привилегиями
- ✅ Доступ к секретам в kube-system
- ✅ kubectl exec в системные поды
- ✅ Попытка удаления audit logs
- ✅ Создание allow-all NetworkPolicies
- ✅ Создание подозрительных секретов (AWS, SSH keys)

### Behavioral IoCs:

- Множественные suspicious действия за короткий период (11 секунд)
- Последовательность действий указывает на планирование (не случайность)
- Попытка covering tracks (удаление audit)
- Использование имперсонации (--as=admin)

---

## Рекомендации по устранению

### Немедленные действия (0-4 часа):

1. ✅ **Изолировать скомпрометированные ресурсы**
   ```bash
   kubectl delete namespace secure-ops --grace-period=0 --force
   ```

2. ✅ **Проверить все RoleBindings кластера**
   ```bash
   kubectl get rolebindings,clusterrolebindings -A | grep cluster-admin
   ```

3. ✅ **Ротировать все секреты**
   - Service Account tokens
   - API keys
   - Credentials в секретах

4. ✅ **Проверить audit logs на другие аномалии**
   ```bash
   # За последние 24 часа
   jq 'select(.timestamp > "2025-11-26")' /var/log/audit.log
   ```

5. ✅ **Уведомить Security Team и Management**

### Краткосрочные (1-7 дней):

6. ✅ **Внедрить PodSecurityPolicy/Pod Security Admission**
   - Заблокировать privileged pods
   - Заблокировать hostNetwork, hostPID, hostIPC

7. ✅ **Ограничить RBAC права**
   - Запретить привязку cluster-admin
   - Внедрить ролевую модель из Task4

8. ✅ **Настроить real-time алерты**
   - На создание privileged pods
   - На изменения RBAC
   - На exec в kube-system
   - На доступ к секретам

9. ✅ **Внедрить OPA/Gatekeeper**
   - Автоматическая валидация всех ресурсов
   - Блокировка опасных конфигураций

### Среднесрочные (1-3 месяца):

10. ✅ **Провести полный security audit**
    - Penetration testing
    - RBAC review
    - Network policies review

11. ✅ **Внедрить SIEM интеграцию**
    - Отправка audit logs в ELK/Splunk
    - ML-based anomaly detection

12. ✅ **Обучить команду**
    - Security awareness training
    - Incident response drills

---

## Выводы и уроки

### Что пошло не так:

1. ❌ **Отсутствие PodSecurityPolicy** - позволило создать опасные поды
2. ❌ **Слабая RBAC модель** - пользователь смог эскалировать привилегии
3. ❌ **Нет real-time мониторинга** - инцидент не был детектирован сразу
4. ❌ **Нет валидации ресурсов** - опасные конфигурации не блокируются

### Что сработало хорошо:

1. ✅ **Audit logging включен** - все действия записаны
2. ✅ **NetworkPolicies** (Task5) - ограничили бы lateral movement
3. ✅ **RBAC модель** (Task4) - если бы была применена, предотвратила бы escalation

### Ключевые выводы:

**Принцип Defense in Depth критически важен:**
- Один уровень защиты (только RBAC) недостаточен
- Нужны: RBAC + PodSecurityPolicy + NetworkPolicy + Audit + SIEM

**Privilege Escalation - главная угроза:**
- Большинство атак в Kubernetes связаны с эскалацией привилегий
- Необходим строгий контроль над RoleBindings

**Audit logging - последняя линия защиты:**
- Даже если все защиты пройдены, audit logs позволяют:
  - Обнаружить атаку post-factum
  - Провести расследование
  - Минимизировать ущерб
  - Предотвратить будущие атаки

---

## Соответствие требованиям из предыдущих заданий

### Task2 (Security Checklist):

| Требование из Task2 | Нарушение в Task6 | Решение |
|---------------------|-------------------|---------|
| Управление инцидентами ИБ | Инцидент не детектирован real-time | SIEM алерты |
| Логирование и мониторинг | Логи есть, но не анализируются | Автоматический анализ |
| RBAC ограничения | Слабая модель RBAC | Применить модель из Task4 |

### Task4 (RBAC):

Если бы была применена ролевая модель из Task4:
- ✅ ServiceAccount `monitoring` имел бы только `monitoring-reader` роль (без доступа к секретам)
- ✅ Создание RoleBindings было бы ограничено (только domain-admins)
- ✅ cluster-admin роль была бы только у CTO (emergency access)

### Task5 (NetworkPolicies):

NetworkPolicies из Task5 ограничили бы:
- ✅ Lateral movement между подами
- ✅ Доступ к admin-back-end-api от скомпрометированных сервисов
- ⚠️ НО не защищают от privileged/hostNetwork подов (они bypass NetworkPolicies!)

---

## Рекомендуемые политики для PropDevelopment

### 1. RBAC Policy (обновление Task4)

```yaml
# Запрет на привязку cluster-admin для всех, кроме CTO
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: restricted-rolebinding-creator
rules:
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["rolebindings"]
  verbs: ["create", "update"]
  # Без cluster-admin!
```

### 2. PodSecurityPolicy (критично!)

```yaml
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: restricted
spec:
  privileged: false  # Запретить privileged
  hostNetwork: false  # Запретить hostNetwork
  hostPID: false
  hostIPC: false
  runAsUser:
    rule: MustRunAsNonRoot  # Запретить root
  seLinux:
    rule: RunAsAny
  fsGroup:
    rule: RunAsAny
  volumes:
  - 'configMap'
  - 'emptyDir'
  - 'projected'
  - 'secret'
  # НЕТ hostPath!
```

### 3. Audit Policy (расширенная)

Текущая политика хорошая, но можно улучшить:
- Добавить уровень RequestResponse для RBAC ресурсов
- Логировать все exec команды (не только в metadata)
- Отдельные правила для kube-system namespace

---

## Метрики безопасности (KPI)

После внедрения рекомендаций отслеживать:

| Метрика | Текущее | Целевое |
|---------|---------|---------|
| Время детектирования инцидента (MTTD) | > 24 часа | < 5 минут |
| Время реагирования (MTTR) | Неизвестно | < 15 минут (P0) |
| Privileged pods в production | Неконтролируемо | 0 |
| RoleBindings с cluster-admin | Неконтролируемо | < 5 (только CTO) |
| Security incidents за месяц | Неизвестно | Target: 0 |

---

## Заключение

**Статус:** 🔴 **КРИТИЧЕСКИЙ ИНЦИДЕНТ ОБНАРУЖЕН**

**Тип:** Privilege Escalation + Multiple Security Violations

**Затронутые ресурсы:**
- Namespace: `secure-ops` (тестовый, можно удалить)
- ServiceAccount: `monitoring` (скомпрометирован)
- Pods: `privileged-pod`, `host-network-pod`, `attacker-pod` (вредоносные)

**Действия:**
1. ✅ Немедленно удалить namespace `secure-ops`
2. ✅ Проверить audit logs за последние 7 дней на похожие паттерны
3. ✅ Внедрить рекомендации из этого отчета
4. ✅ Провести incident response training с командой
5. ✅ Обновить Incident Response Plan

**Ответственные:**
- **Security Team** - анализ и расследование
- **DevOps Team** - внедрение технических мер защиты
- **Management** - утверждение бюджета на SIEM и security tools

---

**Подготовил:** Security Analyst, PropDevelopment  
**Дата:** 27 ноября 2025  
**Статус:** УТВЕРЖДЕНО Security Architect  
**Следующая проверка:** Через 1 неделю после внедрения мер защиты

