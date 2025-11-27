# Задание 5. Управление трафиком внутри кластера Kubernetes

## Описание

Реализация изоляции трафика между сервисами с использованием **NetworkPolicies** в Kubernetes.

Цель: Разграничить трафик между обычными клиентскими сервисами и административными сервисами PropDevelopment, обеспечив security-by-design архитектуру.

## Бизнес-контекст (PropDevelopment)

В компании PropDevelopment есть два типа сервисов:

### 1. Клиентские сервисы (обычные пользователи)
- **front-end-app** - Витрина продаж, мобильное приложение для собственников
- **back-end-api-app** - API для клиентов (client-mart-app, tenant-core-app)

**Пользователи:** Потенциальные покупатели, собственники жилья

### 2. Административные сервисы (внутренние пользователи)
- **admin-front-end-app** - Административная панель
- **admin-back-end-api-app** - Admin API (CRM, управление пользователями, настройки)

**Пользователи:** Менеджеры, охрана, администраторы системы

### Требования безопасности

🔒 **Критично:** Клиентские сервисы НЕ должны иметь доступ к административному API
- Защита от компрометации клиентских сервисов
- Изоляция конфиденциальных административных функций
- Соответствие принципу Defense in Depth (из Task2, Task3)

## Архитектура решения

```
┌─────────────────┐          ┌──────────────────┐
│  front-end-app  │ ◄──✓──► │  back-end-api    │
│  (Клиенты)      │          │  (Client API)    │
└─────────────────┘          └──────────────────┘
        │                              │
        │                              │
        ✗ BLOCKED                      ✗ BLOCKED
        │                              │
        ▼                              ▼
┌─────────────────┐          ┌──────────────────┐
│admin-front-end  │ ◄──✓──► │admin-back-end-api│
│(Администраторы) │          │  (Admin API)     │
└─────────────────┘          └──────────────────┘

Легенда:
  ✓ = Трафик разрешен (NetworkPolicy)
  ✗ = Трафик заблокирован (NetworkPolicy)
```

## Структура решения

### 1. Скрипт развертывания: `1-deploy-services.sh`

Развертывает 4 пода с метками (labels):

| Pod | Label | Роль | Порт |
|-----|-------|------|------|
| front-end-app | role=front-end | Клиентский UI | 80 |
| back-end-api-app | role=back-end-api | Клиентский API | 80 |
| admin-front-end-app | role=admin-front-end | Админский UI | 80 |
| admin-back-end-api-app | role=admin-back-end-api | Админский API | 80 |

**Технология:** Nginx (для демонстрации, в реальности - реальные приложения)

### 2. NetworkPolicy файлы

#### `non-admin-api-allow.yaml` ⭐ (основной файл для задания)

Разрешает трафик между клиентскими сервисами:
- **Ingress** к back-end-api: только от front-end
- **Egress** от front-end: только к back-end-api
- **Deny** от front-end к admin-back-end-api (явный запрет)

#### `admin-api-allow.yaml`

Разрешает трафик между административными сервисами:
- **Ingress** к admin-back-end-api: только от admin-front-end
- **Egress** от admin-front-end: только к admin-back-end-api
- **Deny** от back-end-api к admin-back-end-api (защита)

#### `default-deny-all.yaml` (опционально)

Запрещает весь трафик по умолчанию (zero-trust подход):
- **Ingress**: запрет всего входящего трафика
- **Egress**: запрет всего исходящего трафика

Разрешения задаются явно в других политиках.

### 3. Скрипт тестирования: `2-test-network-policies.sh`

Автоматически проверяет работу NetworkPolicies:

| Тест | Ожидаемый результат |
|------|---------------------|
| front-end → back-end-api | ✓ Разрешено |
| front-end → admin-back-end-api | ✗ Заблокировано |
| admin-front-end → admin-back-end-api | ✓ Разрешено |
| admin-front-end → back-end-api | ✗ Заблокировано |
| back-end-api → admin-back-end-api | ✗ Заблокировано |

## Использование

### Предварительные требования

```bash
# 1. Minikube с поддержкой NetworkPolicy
minikube start --cni=calico

# Или для Minikube 1.33+:
minikube start --network-plugin=cni --cni=calico

# 2. Проверка kubectl
kubectl cluster-info
```

**Важно:** NetworkPolicy требует CNI plugin (Calico, Cilium, Weave Net). Стандартный Minikube (без CNI) **не поддерживает** NetworkPolicy!

### Шаг 1: Развертывание сервисов

```bash
cd Task5
chmod +x *.sh
./1-deploy-services.sh
```

**Результат:**
- Создано 4 пода с метками
- Создано 4 Service для доступа
- Проверена связность (все поды могут общаться)

**Проверка:**
```bash
kubectl get pods -l app=propdevelopment
kubectl get services -l app=propdevelopment
kubectl get pods --show-labels
```

### Шаг 2: Применение NetworkPolicies

```bash
# Основная политика (клиентские сервисы)
kubectl apply -f non-admin-api-allow.yaml

# Административная политика
kubectl apply -f admin-api-allow.yaml

# Опционально: Default Deny (применять В ПОСЛЕДНЮЮ ОЧЕРЕДЬ!)
# kubectl apply -f default-deny-all.yaml
```

**Проверка:**
```bash
kubectl get networkpolicies
kubectl describe networkpolicy non-admin-api-allow-ingress
```

### Шаг 3: Тестирование

```bash
./2-test-network-policies.sh
```

**Ожидаемый вывод:**
```
========================================
РЕЗУЛЬТАТЫ ТЕСТИРОВАНИЯ
========================================
Всего тестов: 5
Пройдено: 5
Провалено: 0

✓ ВСЕ ТЕСТЫ ПРОЙДЕНЫ УСПЕШНО!
========================================
```

### Шаг 4: Ручное тестирование (как в задании)

```bash
# Тест 1: Доступ к back-end-api (должен работать)
kubectl run test-$RANDOM --rm -i -t --image=alpine -- sh

# Внутри контейнера:
/ # wget -qO- --timeout=2 http://back-end-api-app
# Должен вернуть HTML страницу Nginx (✓)

/ # wget -qO- --timeout=2 http://admin-back-end-api-app
# Должен timeout (✗ заблокировано NetworkPolicy)

/ # exit
```

```bash
# Тест 2: Доступ из front-end к back-end-api
kubectl exec front-end-app -- wget -qO- --timeout=2 http://back-end-api-app
# Должен работать (✓)

# Тест 3: Доступ из front-end к admin-back-end-api (должен быть заблокирован)
kubectl exec front-end-app -- wget -qO- --timeout=2 http://admin-back-end-api-app
# Должен timeout (✗ заблокировано)
```

## Детали реализации

### NetworkPolicy: Ingress правила

**non-admin-api-allow.yaml:**
```yaml
spec:
  podSelector:
    matchLabels:
      role: back-end-api  # Применяется к back-end-api
  ingress:
    - from:
        - podSelector:
            matchLabels:
              role: front-end  # Только от front-end
      ports:
        - protocol: TCP
          port: 80
```

### NetworkPolicy: Egress правила

**non-admin-api-allow.yaml:**
```yaml
spec:
  podSelector:
    matchLabels:
      role: front-end  # Применяется к front-end
  egress:
    - to:
        - podSelector:
            matchLabels:
              role: back-end-api  # Только к back-end-api
      ports:
        - protocol: TCP
          port: 80
    - to:  # DNS разрешения
        - namespaceSelector:
            matchLabels:
              name: kube-system
      ports:
        - protocol: UDP
          port: 53
```

### Label Selectors

Ключевой механизм NetworkPolicy:

```bash
# Поды с метками
kubectl get pods -l role=front-end        # front-end-app
kubectl get pods -l role=back-end-api     # back-end-api-app
kubectl get pods -l role=admin-front-end  # admin-front-end-app
kubectl get pods -l role=admin-back-end-api  # admin-back-end-api-app

# Все поды приложения
kubectl get pods -l app=propdevelopment
```

## Принципы безопасности

### 1. Defense in Depth (Эшелонированная защита)

Несколько уровней защиты:
- **L1**: RBAC (Task4) - кто может деплоить сервисы
- **L2**: NetworkPolicy (Task5) - какой трафик разрешен
- **L3**: Application-level auth - аутентификация в приложении

### 2. Least Privilege (Минимальные привилегии)

Каждый сервис имеет доступ **только** к необходимым сервисам:
- front-end → только к back-end-api
- admin-front-end → только к admin-back-end-api

### 3. Explicit Allow (Явное разрешение)

С `default-deny-all.yaml`:
- Весь трафик запрещен по умолчанию
- Разрешения задаются явно в политиках

### 4. Separation of Concerns (Разделение ответственности)

- Клиентские сервисы изолированы от административных
- Защита от lateral movement при компрометации

## Troubleshooting

### Проблема: NetworkPolicy не работает

**Симптом:** Все тесты проходят, но трафик не блокируется

**Причина:** CNI plugin не поддерживает NetworkPolicy

**Решение:**
```bash
# Пересоздать Minikube с Calico
minikube delete
minikube start --cni=calico

# Проверить CNI
kubectl get pods -n kube-system | grep calico
```

### Проблема: Все поды недоступны после default-deny-all

**Симптом:** Даже разрешенный трафик не работает

**Причина:** Забыли применить allow policies или неправильный порядок

**Решение:**
```bash
# Откатить default-deny
kubectl delete -f default-deny-all.yaml

# Применить в правильном порядке
kubectl apply -f non-admin-api-allow.yaml
kubectl apply -f admin-api-allow.yaml
kubectl apply -f default-deny-all.yaml  # В последнюю очередь!
```

### Проблема: DNS не работает

**Симптом:** wget: bad address 'back-end-api-app'

**Причина:** Egress правила блокируют DNS запросы

**Решение:** Убедитесь, что в Egress политиках есть правило для DNS:
```yaml
egress:
  - to:
      - namespaceSelector:
          matchLabels:
            name: kube-system
    ports:
      - protocol: UDP
        port: 53
```

### Проверка отладки

```bash
# 1. Проверить метки подов
kubectl get pods --show-labels

# 2. Проверить NetworkPolicies
kubectl get networkpolicies
kubectl describe networkpolicy non-admin-api-allow-ingress

# 3. Проверить IP адреса
kubectl get pods -o wide

# 4. Проверить Service endpoints
kubectl get endpoints

# 5. Логи пода
kubectl logs front-end-app
```

## Интеграция с предыдущими заданиями

### Из Task2 (Security Checklist):

**Проблема:** Отсутствие сетевой изоляции между сервисами

**Решение в Task5:** NetworkPolicies для изоляции доменов

### Из Task3 (Smart Home Integration):

**Проблема:** Необходимость изолировать smart-home сервисы от других

**Решение в Task5:** Можно создать политику для smart-home-operator:
```yaml
podSelector:
  matchLabels:
    role: smart-home-integration
```

### Из Task4 (RBAC):

**RBAC (Task4)** контролирует, **кто** может создавать NetworkPolicies

**NetworkPolicy (Task5)** контролирует, **какой трафик** разрешен между подами

**Вместе:** Полная защита кластера (access control + network isolation)

## Файлы в Task5

```
Task5/
├── README.md                      # Этот файл
├── 1-deploy-services.sh           # Скрипт развертывания подов
├── non-admin-api-allow.yaml       # NetworkPolicy (клиенты) ⭐
├── admin-api-allow.yaml           # NetworkPolicy (админы)
├── default-deny-all.yaml          # Default Deny (опционально)
├── 2-test-network-policies.sh     # Скрипт тестирования
└── service-ips.txt                # IP адреса (создается скриптом)
```

⭐ = Основной файл для сдачи задания

## Соответствие требованиям задания

| Требование | Реализация | Статус |
|------------|------------|--------|
| Развернуть 4 сервиса в одном namespace | 4 пода с метками | ✅ |
| Назначить метки | role=front-end, back-end-api, admin-front-end, admin-back-end-api | ✅ |
| Создать NetworkPolicies | non-admin-api-allow.yaml, admin-api-allow.yaml | ✅ |
| Разделить трафик между API и UI | Ingress/Egress правила | ✅ |
| Разрешить front-end ←→ back-end-api | Политика в non-admin-api-allow.yaml | ✅ |
| Разрешить admin-front-end ←→ admin-back-end-api | Политика в admin-api-allow.yaml | ✅ |
| Проверить трафик | Скрипт 2-test-network-policies.sh | ✅ |
| Сохранить в файл | non-admin-api-allow.yaml | ✅ |

## Дополнительные возможности

### Мониторинг NetworkPolicies

```bash
# События NetworkPolicy
kubectl get events --all-namespaces | grep NetworkPolicy

# Pods и их политики
kubectl get pods -o custom-columns=NAME:.metadata.name,LABELS:.metadata.labels
```

### Расширенные политики

Для production окружения можно добавить:
- **Port-specific rules** - разные порты для разных типов трафика
- **Namespace isolation** - изоляция между namespace (Task4 domains)
- **CIDR blocks** - разрешить трафик с определенных IP
- **Egress to external** - контроль доступа к внешним API

### Визуализация

Для понимания NetworkPolicies используйте:
- [Network Policy Editor](https://editor.networkpolicy.io/)
- [Cilium Network Policy Editor](https://networkpolicy.io/editor/)

## Метрики успеха

- ✅ Развернуто **4 сервиса** с метками
- ✅ Создано **3 NetworkPolicy** файла
- ✅ **5 тестов** проходят успешно
- ✅ Клиентские сервисы **изолированы** от административных
- ✅ Применен принцип **Defense in Depth**

## Следующие шаги (опционально)

1. **PodSecurityPolicies**: Ограничения на уровне пода (capabilities, privileged mode)
2. **Service Mesh (Istio)**: mTLS между всеми сервисами
3. **OPA/Gatekeeper**: Policy-as-Code для валидации NetworkPolicies
4. **Calico Advanced Policies**: Global network sets, tiered policies

---

**Дата:** Ноябрь 2025  
**Версия:** 1.0  
**Автор:** Security Architecture Team  
**Статус:** Готово к использованию

