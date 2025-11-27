# Задание 6. Аудит активности пользователей и обнаружение инцидентов

## Описание

Настройка аудита активности пользователей в Kubernetes для своевременного обнаружения аномалий, попыток несанкционированного доступа и других угроз безопасности.

## Цели задания

1. ✅ Настроить Kubernetes Audit Log с политикой аудита
2. ✅ Симулировать различные типы инцидентов безопасности
3. ✅ Разработать скрипт для автоматического анализа audit.log
4. ✅ Выявить подозрительные события и классифицировать их
5. ✅ Подготовить детальный отчет по инцидентам

## Структура решения

### 1. `audit-policy.yaml` - Политика аудита Kubernetes

**Назначение:** Конфигурация Kubernetes API Server для логирования событий

**Уровни логирования:**
- `RequestResponse` - Полное логирование (request + response) для критичных ресурсов
- `Metadata` - Только метаданные для остальных ресурсов

**Логируемые ресурсы:**
```yaml
rules:
  - level: RequestResponse
    verbs: ["create", "delete", "update", "patch", "get", "list"]
    resources:
      - group: ""
        resources: ["pods", "secrets", "configmaps", "serviceaccounts"]
      - group: "rbac.authorization.k8s.io"
        resources: ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
  - level: Metadata
    resources:
      - group: "*"
        resources: ["*"]
```

### 2. `simulate-incident.sh` - Скрипт симуляции инцидентов

**Назначение:** Генерация различных типов подозрительных событий для тестирования системы аудита

**Симулируемые инциденты:**

| № | Инцидент | Тип угрозы | Severity |
|---|----------|------------|----------|
| 1 | Доступ к secrets от ServiceAccount `monitoring` | Unauthorized Access | 🟠 HIGH |
| 2 | Создание привилегированного пода (`privileged: true`) | Privilege Escalation | 🔴 CRITICAL |
| 3 | kubectl exec в системном поде (CoreDNS в kube-system) | Lateral Movement | 🔴 CRITICAL |
| 4 | Попытка удаления audit-policy.yaml | Defense Evasion | 🔴 CRITICAL |
| 5 | Создание RoleBinding с правами cluster-admin | Privilege Escalation | 🔴 CRITICAL |

**Использование:**
```bash
./simulate-incident.sh
```

### 3. `analyze-audit.sh` ⭐ - Скрипт анализа audit.log

**Назначение:** Автоматическая фильтрация и анализ audit.log для выявления инцидентов безопасности

**Функции:**
- ✅ Поиск доступа к секретам (secrets)
- ✅ Выявление привилегированных подов
- ✅ Детектирование kubectl exec в чужих подах
- ✅ Мониторинг изменений RBAC (RoleBindings/ClusterRoleBindings)
- ✅ Обнаружение попыток удаления критичных ресурсов
- ✅ Создание JSON выжимки подозрительных событий

**Требования:**
- jq (JSON processor)
- Доступ к audit.log файлу

**Использование:**
```bash
# С указанием пути к audit.log
./analyze-audit.sh /var/log/kubernetes/audit.log

# Без параметров (использует /var/log/audit.log или создает demo)
./analyze-audit.sh
```

**Выход:**
- `audit-extract.json` - JSON выжимка подозрительных событий
- Консольный отчет с цветовой индикацией
- Статистика по типам инцидентов
- Рекомендации по устранению

### 4. `audit-extract.json` - Выжимка подозрительных событий

**Формат:**
```json
{
  "audit_summary": {
    "analyzed_file": "/var/log/audit.log",
    "analysis_timestamp": "2025-11-27T15:30:00Z",
    "total_suspicious_events": 5,
    "severity_breakdown": {
      "critical": 3,
      "high": 2,
      "medium": 0
    }
  },
  "incidents": {
    "secret_access": [...],
    "privileged_pods": [...],
    "kubectl_exec": [...],
    "rbac_changes": [...],
    "resource_deletion": [...]
  }
}
```

### 5. `analysis.md` ⭐ - Детальный отчет по инцидентам

**Содержание:**
1. **Подозрительные события** - детальный разбор каждого инцидента
2. **Анализ RBAC ошибок** - выявленные проблемы в политиках доступа
3. **Компрометация кластера** - оценка степени компрометации
4. **Timeline инцидента** - хронология событий
5. **Индикаторы компрометации (IoC)** - признаки атаки
6. **Рекомендации по устранению** - план действий
7. **Выводы и уроки** - что пошло не так и как исправить

## Использование

### Шаг 1: Настройка Minikube с audit logging

```bash
# Создать директорию для audit logs
mkdir -p ~/minikube-audit

# Скопировать audit-policy.yaml
cp audit-policy.yaml ~/minikube-audit/

# Запустить Minikube с audit logging
minikube start \
  --extra-config=apiserver.audit-policy-file=/etc/kubernetes/audit-policy.yaml \
  --extra-config=apiserver.audit-log-path=/var/log/audit.log \
  --extra-config=apiserver.audit-log-format=json \
  --extra-config=apiserver.audit-log-maxage=7 \
  --extra-config=apiserver.audit-log-maxbackup=3 \
  --extra-config=apiserver.audit-log-maxsize=100 \
  --mount=true \
  --mount-string="$HOME/minikube-audit/audit-policy.yaml:/etc/kubernetes/audit-policy.yaml"
```

**Важно:** В новых версиях Minikube используйте флаги монтирования:
```bash
minikube start \
  --mount=true \
  --mount-string="$HOME/minikube-audit:/etc/kubernetes" \
  --extra-config=apiserver.audit-policy-file=/etc/kubernetes/audit-policy.yaml \
  --extra-config=apiserver.audit-log-path=/var/log/audit.log
```

### Шаг 2: Запуск симуляции инцидентов

```bash
cd Task6
chmod +x simulate-incident.sh
./simulate-incident.sh
```

**Ожидаемый результат:**
- Создан namespace `secure-ops`
- Выполнены 5 типов подозрительных действий
- События записаны в audit.log

### Шаг 3: Извлечение audit.log из Minikube

```bash
# Войти в Minikube node
minikube ssh

# Проверить audit.log
sudo cat /var/log/audit.log | head -20

# Скопировать audit.log на хост
minikube ssh "sudo cat /var/log/audit.log" > audit.log

# Или через docker (если Minikube использует Docker driver)
docker exec minikube cat /var/log/audit.log > audit.log
```

### Шаг 4: Анализ audit.log

```bash
cd Task6
chmod +x analyze-audit.sh
./analyze-audit.sh ./audit.log
```

**Вывод скрипта:**
```
========================================
Анализ Kubernetes Audit Log
PropDevelopment Security Audit
========================================

[INFO] Анализируемый файл: ./audit.log
[OK] jq установлен

========================================
[1/5] Анализ: Доступ к секретам
========================================
[!] Найдено событий доступа к секретам: 1
  User: system:serviceaccount:secure-ops:monitoring | Namespace: kube-system | ...

========================================
[2/5] Анализ: Привилегированные поды
========================================
[!] Найдено привилегированных подов: 1
  User: kubernetes-admin | Pod: privileged-pod | ...

========================================
[3/5] Анализ: kubectl exec
========================================
[!] Найдено kubectl exec событий: 1
  User: john.attacker | Pod: coredns-abc123 | ...

========================================
[4/5] Анализ: Изменения RBAC
========================================
[!] Найдено изменений RBAC: 1
  User: suspicious.user | Resource: rolebindings | ...
  [!!!] КРИТИЧНО: Обнаружена привязка к cluster-admin!

========================================
[5/5] Анализ: Удаление критичных ресурсов
========================================
[!] Найдено попыток удаления критичных ресурсов: 1
  User: admin | Resource: configmaps | Name: audit-policy | ...

========================================
СТАТИСТИКА
========================================
Доступ к секретам:              1 событий
Привилегированные поды:         1 событий
kubectl exec:                   1 событий
Изменения RBAC:                 1 событий
Удаление критичных ресурсов:    1 событий

ВСЕГО подозрительных событий:   5

[!] Обнаружены подозрительные события!
```

### Шаг 5: Проверка результатов

```bash
# Просмотр выжимки
jq . audit-extract.json

# Конкретные инциденты
jq '.incidents.secret_access' audit-extract.json
jq '.incidents.privileged_pods' audit-extract.json
jq '.incidents.rbac_changes' audit-extract.json

# Статистика
jq '.audit_summary' audit-extract.json

# Чтение отчета
cat analysis.md
```

## Ручная проверка событий (из задания)

### Проверка доступа к secrets
```bash
jq 'select(.objectRef.resource=="secrets" and .verb=="get")' audit.log
```

### Проверка kubectl exec
```bash
jq 'select(.verb=="create" and .objectRef.subresource=="exec")' audit.log
```

### Проверка привилегированных подов
```bash
jq 'select(.objectRef.resource=="pods" and .requestObject.spec.containers[].securityContext.privileged==true)' audit.log
```

### Проверка изменений audit-policy
```bash
grep -i 'audit-policy' audit.log
```

## Выявленные инциденты

### 1. 🔴 Доступ к секретам в kube-system
- **Кто:** `system:serviceaccount:secure-ops:monitoring`
- **Где:** Namespace `kube-system`, секреты service account tokens
- **Почему подозрительно:** ServiceAccount для мониторинга не должен иметь доступа к секретам в системном namespace

### 2. 🔴 Создание привилегированного пода
- **Кто:** Пользователь с правами создания подов
- **Что:** Pod с `privileged: true` и `allowPrivilegeEscalation: true`
- **Почему критично:** Полный доступ к host системе, возможность escape из контейнера

### 3. 🔴 kubectl exec в системном поде
- **Кто:** Пользователь из namespace `secure-ops`
- **Где:** Pod CoreDNS в namespace `kube-system`
- **Почему критично:** Попытка выполнить команды в критичном системном компоненте

### 4. 🔴 Создание RoleBinding с cluster-admin
- **Кто:** Пользователь с правами создания RoleBindings
- **Что:** Привязка ServiceAccount `monitoring` к роли `cluster-admin`
- **Результат:** **ПОЛНАЯ КОМПРОМЕТАЦИЯ КЛАСТЕРА** - ServiceAccount получил неограниченные права

### 5. 🔴 Попытка удаления audit-policy
- **Кто:** Пользователь с имперсонацией `--as=admin`
- **Что:** Попытка удалить файл audit policy
- **Цель:** Отключение аудита для скрытия дальнейших действий (covering tracks)

## Анализ ошибок RBAC

### Выявленные проблемы:

1. **Отсутствие ограничений на создание RoleBindings**
   - Любой пользователь с правами `create rolebindings` может привязать cluster-admin
   - Нет контроля над `escalate` verb

2. **Избыточные права ServiceAccount**
   - ServiceAccount `monitoring` смог проверять доступ к секретам
   - Нарушен принцип Least Privilege

3. **Отсутствие PodSecurityPolicy**
   - Удалось создать privileged и hostNetwork поды
   - Нет валидации через Admission Controller

4. **Нет real-time мониторинга**
   - RBAC изменения не триггерят алерты
   - Отсутствует интеграция с SIEM

## Компрометация кластера

### ✅ Подтвержденная компрометация:

**Privilege Escalation через RoleBinding**
- ServiceAccount `monitoring` получил права `cluster-admin`
- Это дает **ПОЛНЫЙ КОНТРОЛЬ** над кластером:
  - ✓ Чтение всех секретов
  - ✓ Создание/изменение/удаление любых ресурсов
  - ✓ Выполнение команд в любых подах
  - ✓ Изменение RBAC правил
  - ✓ Доступ к nodes

**Severity:** 🔴 P0 - CRITICAL

## Рекомендации по устранению

### Немедленные действия (0-4 часа):

1. **Удалить скомпрометированные ресурсы**
   ```bash
   kubectl delete namespace secure-ops --grace-period=0 --force
   ```

2. **Проверить все RoleBindings**
   ```bash
   kubectl get rolebindings,clusterrolebindings -A | grep cluster-admin
   ```

3. **Ротировать секреты**
   - Service Account tokens
   - API keys в секретах

4. **Аудит за 24 часа**
   ```bash
   jq 'select(.timestamp > "2025-11-26")' /var/log/audit.log
   ```

### Краткосрочные (1-7 дней):

5. **Внедрить PodSecurityPolicy/Pod Security Admission**
   - Заблокировать privileged pods
   - Заблокировать hostNetwork/hostPID/hostIPC

6. **Ограничить RBAC**
   - Запретить привязку cluster-admin
   - Применить ролевую модель из Task4

7. **Настроить real-time алерты**
   - Privileged pods
   - Изменения RBAC
   - kubectl exec в kube-system
   - Доступ к секретам

8. **Внедрить OPA/Gatekeeper (Task7)**
   - Автоматическая валидация
   - Блокировка опасных конфигураций

### Среднесрочные (1-3 месяца):

9. **Security audit**
   - Penetration testing
   - RBAC review

10. **SIEM интеграция**
    - ELK/Splunk для audit logs
    - ML-based anomaly detection

11. **Обучение команды**
    - Security awareness
    - Incident response drills

## Интеграция с предыдущими заданиями

### Task2 (Security Checklist):
- ✅ Логирование и мониторинг - реализовано через Audit Log
- ⚠️ Управление инцидентами - выявлена необходимость real-time detection

### Task4 (RBAC):
- ❌ Если бы была применена ролевая модель из Task4, инцидент был бы предотвращен
- ServiceAccount `monitoring` имел бы только права `monitoring-reader` (без секретов)

### Task5 (NetworkPolicies):
- ✅ NetworkPolicies ограничили бы lateral movement
- ⚠️ НО не защищают от privileged/hostNetwork подов

### Task7 (Gatekeeper):
- Политики из Task7 заблокировали бы:
  - ✅ Создание privileged подов
  - ✅ Использование hostNetwork
  - ✅ Запуск от root пользователя

## Файлы в Task6

```
Task6/
├── README.md                  # Этот файл (документация)
├── audit-policy.yaml          # Политика аудита для K8s API Server
├── simulate-incident.sh       # Скрипт симуляции инцидентов
├── analyze-audit.sh           # Скрипт анализа audit.log ⭐
├── audit-extract.json         # Выжимка подозрительных событий ⭐
├── analysis.md                # Детальный отчет по инцидентам ⭐
├── events.json                # Дополнительные события (опционально)
└── resources.json             # Метаданные ресурсов (опционально)
```

⭐ = Основные файлы для сдачи задания

## Соответствие требованиям задания

| Требование | Реализация | Статус |
|------------|------------|--------|
| Настроить audit-policy.yaml | audit-policy.yaml с RequestResponse уровнем | ✅ |
| Симуляция инцидентов | simulate-incident.sh (5 типов инцидентов) | ✅ |
| Анализ audit.log | analyze-audit.sh (Bash + jq) | ✅ |
| Выжимка JSON | audit-extract.json | ✅ |
| Отчет analysis.md | Детальный отчет с IoC и рекомендациями | ✅ |
| Идентификация инициаторов | User/ServiceAccount для каждого события | ✅ |
| Вредоносные действия | 5 типов угроз классифицированы | ✅ |
| Компрометация кластера | Privilege Escalation подтвержден | ✅ |
| Ошибки RBAC | 4 критичных проблемы выявлены | ✅ |

## Troubleshooting

### Проблема: audit.log пустой

**Причина:** API Server не настроен на аудит

**Решение:**
```bash
# Проверить конфигурацию API Server
minikube ssh
ps aux | grep kube-apiserver | grep audit

# Должны быть флаги:
# --audit-policy-file=/etc/kubernetes/audit-policy.yaml
# --audit-log-path=/var/log/audit.log
```

### Проблема: jq не установлен

**Решение:**
```bash
# macOS
brew install jq

# Linux
sudo apt-get install jq

# Windows (WSL)
sudo apt install jq
```

### Проблема: Cannot access /var/log/audit.log

**Решение:**
```bash
# Использовать minikube ssh для доступа
minikube ssh "sudo cat /var/log/audit.log" > audit.log
```

## Метрики успеха

- ✅ Создана политика аудита с логированием критичных ресурсов
- ✅ Симулировано 5 типов инцидентов безопасности
- ✅ Разработан автоматический скрипт анализа (336 строк Bash)
- ✅ Выявлено 5 подозрительных событий
- ✅ Подтверждена полная компрометация кластера (Privilege Escalation)
- ✅ Идентифицировано 4 ошибки в RBAC политиках
- ✅ Подготовлен детальный отчет (650+ строк) с рекомендациями

## Ключевые выводы

**Defense in Depth критически важен:**
- Один уровень защиты (только RBAC) недостаточен
- Нужны: RBAC + PodSecurityPolicy + NetworkPolicy + Audit + SIEM

**Privilege Escalation - главная угроза:**
- Большинство атак в K8s связаны с эскалацией привилегий
- Необходим строгий контроль над RoleBindings

**Audit logging - последняя линия защиты:**
- Даже если все защиты пройдены, audit logs позволяют:
  - Обнаружить атаку post-factum
  - Провести расследование
  - Минимизировать ущерб
  - Предотвратить будущие атаки

---

**Дата:** Ноябрь 2025  
**Версия:** 1.0  
**Автор:** Security Architecture Team  
**Статус:** Готово к использованию

