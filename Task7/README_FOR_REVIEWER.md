# Task7: Аудит и обеспечение соответствия политике безопасности контейнеров

## Описание задания

Настройка и валидация политик безопасности контейнеров в Kubernetes с использованием:
- **Pod Security Standards (PSS)** - встроенный механизм с уровнем `restricted`
- **OPA Gatekeeper** - динамическая валидация с custom политиками

## Структура проекта

```
Task7/
├── 01-create-namespace.yaml           # Namespace с Pod Security labels
├── insecure-manifests/                # Манифесты с нарушениями
│   ├── 01-privileged-pod.yaml         # privileged: true
│   ├── 02-hostpath-pod.yaml           # hostPath volume
│   └── 03-root-user-pod.yaml          # runAsUser: 0
├── secure-manifests/                  # Исправленные манифесты
│   ├── 01-secure.yaml                 # Secure nginx
│   ├── 02-secure.yaml                 # Secure alpine
│   └── 03-secure.yaml                 # Secure busybox + deployment
├── gatekeeper/                        # OPA Gatekeeper политики
│   ├── constraint-templates/          # Rego правила
│   │   ├── privileged.yaml
│   │   ├── hostpath.yaml
│   │   ├── runasnonroot.yaml
│   │   └── readonly-root-fs.yaml
│   └── constraints/                   # Применение правил
│       ├── privileged.yaml
│       ├── hostpath.yaml
│       ├── runasnonroot.yaml
│       └── readonly-root-fs.yaml
├── verify/                            # Скрипты проверки
│   ├── verify-admission.sh            # Тест admission control
│   └── validate-security.sh           # Валидация конфигурации
├── audit-policy.yaml                  # Политика аудита
└── README_FOR_REVIEWER.md             # Этот файл
```

---

## Быстрый старт для проверяющего

### Предусловия

```bash
# 1. Kubernetes кластер (minikube, kind, или production)
minikube start --kubernetes-version=v1.28.0

# 2. kubectl
kubectl version --client

# 3. jq (опционально, для детального анализа)
brew install jq  # macOS
apt install jq   # Ubuntu
```

### Шаг 1: Создание namespace с Pod Security

```bash
cd Task7

# Создать namespace audit-zone с уровнем restricted
kubectl apply -f 01-create-namespace.yaml

# Проверить Pod Security labels
kubectl get namespace audit-zone -o yaml | grep pod-security
```

**Ожидаемый результат:**
```yaml
pod-security.kubernetes.io/enforce: restricted
pod-security.kubernetes.io/audit: restricted
pod-security.kubernetes.io/warn: restricted
```

---

### Шаг 2: Проверка блокировки небезопасных подов

```bash
# Тест 1: Privileged Pod (должен быть ЗАБЛОКИРОВАН)
kubectl apply -f insecure-manifests/01-privileged-pod.yaml
# Ожидается: Error... violates PodSecurity "restricted:latest"

# Тест 2: HostPath Pod (должен быть ЗАБЛОКИРОВАН)
kubectl apply -f insecure-manifests/02-hostpath-pod.yaml
# Ожидается: Error... spec.volumes[0].hostPath

# Тест 3: Root User Pod (должен быть ЗАБЛОКИРОВАН)
kubectl apply -f insecure-manifests/03-root-user-pod.yaml
# Ожидается: Error... runAsNonRoot != true
```

**✅ Критерий успеха:** Все 3 манифеста заблокированы Pod Security Admission

---

### Шаг 3: Проверка безопасных подов

```bash
# Secure поды ДОЛЖНЫ быть разрешены
kubectl apply -f secure-manifests/01-secure.yaml
kubectl apply -f secure-manifests/02-secure.yaml
kubectl apply -f secure-manifests/03-secure.yaml

# Проверить статус
kubectl get pods -n audit-zone
```

**Ожидаемый результат:**
```
NAME                  READY   STATUS    RESTARTS   AGE
pod-secure-nginx      1/1     Running   0          10s
pod-secure-alpine     1/1     Running   0          8s
pod-secure-busybox    1/1     Running   0          5s
secure-deployment-... 1/1     Running   0          5s
secure-deployment-... 1/1     Running   0          5s
```

**✅ Критерий успеха:** Все secure поды запущены успешно

---

### Шаг 4: Установка OPA Gatekeeper

```bash
# Установить Gatekeeper
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/release-3.15/deploy/gatekeeper.yaml

# Дождаться готовности
kubectl wait --for=condition=available --timeout=300s deployment/gatekeeper-controller-manager -n gatekeeper-system
kubectl wait --for=condition=available --timeout=300s deployment/gatekeeper-audit -n gatekeeper-system

# Проверить
kubectl get pods -n gatekeeper-system
```

---

### Шаг 5: Применение Gatekeeper политик

```bash
# Применить ConstraintTemplates (Rego правила)
kubectl apply -f gatekeeper/constraint-templates/

# Дождаться создания CRD
sleep 10

# Применить Constraints (активация правил)
kubectl apply -f gatekeeper/constraints/

# Проверить
kubectl get constrainttemplates
kubectl get constraints -A
```

**Ожидаемый результат:**
```
NAME                                    AGE
k8spsphostpath                          30s
k8spspprivileged                        30s
k8spspreadonlyrootfs                    30s
k8spsprunasnonroot                      30s
```

---

### Шаг 6: Автоматическая проверка

```bash
cd verify

# Запустить комплексную проверку
./verify-admission.sh

# Детальная валидация security context
./validate-security.sh audit-zone
```

**✅ Критерий успеха:** 
- Все небезопасные манифесты заблокированы
- Все secure манифесты разрешены
- Gatekeeper constraint violations = 0

---

## Детальное описание компонентов

### 1. Pod Security Standards (PSS)

#### Уровни безопасности:

| Уровень | Описание | Использование |
|---------|----------|---------------|
| **privileged** | Без ограничений | Системные компоненты |
| **baseline** | Минимальные ограничения | Общие приложения |
| **restricted** | Строгие ограничения | Production workloads |

#### Режимы работы:

- `enforce` - **блокирует** создание нарушающих подов
- `audit` - **логирует** нарушения
- `warn` - **предупреждает** при создании

**В Task7 используется: `restricted` + `enforce`**

### 2. OPA Gatekeeper

#### Архитектура:

```
kubectl apply pod.yaml
       ↓
Admission Controller
       ↓
OPA Gatekeeper (ValidatingWebhook)
       ↓
Evaluate Constraints (Rego)
       ↓
Allow / Deny
```

#### Constraint Templates (Task7):

1. **K8sPSPPrivileged** - запрет `privileged: true`
2. **K8sPSPHostPath** - запрет `hostPath` volumes
3. **K8sPSPRunAsNonRoot** - требование `runAsNonRoot: true`
4. **K8sPSPReadOnlyRootFS** - требование `readOnlyRootFilesystem: true`

---

## Примеры нарушений и исправлений

### Нарушение 1: Privileged Container

❌ **Небезопасно:**
```yaml
spec:
  containers:
  - name: nginx
    securityContext:
      privileged: true  # ❌ Полный доступ к хосту
```

✅ **Безопасно:**
```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
  containers:
  - name: nginx
    securityContext:
      privileged: false
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: [ALL]
```

### Нарушение 2: HostPath Volume

❌ **Небезопасно:**
```yaml
volumes:
- name: host-root
  hostPath:
    path: /  # ❌ Доступ к host filesystem
```

✅ **Безопасно:**
```yaml
volumes:
- name: data
  emptyDir: {}  # ✅ Изолированный volume
```

### Нарушение 3: Root User

❌ **Небезопасно:**
```yaml
securityContext:
  runAsUser: 0  # ❌ Root (UID 0)
```

✅ **Безопасно:**
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000  # ✅ Non-root user
```

---

## Проверка результатов

### Test Case 1: Pod Security Admission блокирует небезопасные поды

```bash
# Должен FAIL
kubectl apply -f insecure-manifests/01-privileged-pod.yaml 2>&1 | grep -i "violates PodSecurity"

# Ожидается: выход с ошибкой
```

### Test Case 2: Gatekeeper блокирует нарушения

```bash
# После установки Gatekeeper
kubectl apply -f insecure-manifests/02-hostpath-pod.yaml 2>&1 | grep -i "denied by"

# Ожидается: [denied by psp-hostpath-volume]
```

### Test Case 3: Secure поды работают

```bash
kubectl get pods -n audit-zone -o wide | grep Running | wc -l

# Ожидается: >= 4 (3 poda + 2 из deployment)
```

### Test Case 4: Security Context соответствует restricted

```bash
./verify/validate-security.sh audit-zone

# Проверяет:
# ✓ runAsNonRoot: true
# ✓ readOnlyRootFilesystem: true  
# ✓ allowPrivilegeEscalation: false
# ✓ No hostPath volumes
```

---

## Интеграция с Task6 (Audit)

### Связь с аудитом:

1. **Task6** - настроил audit logging для обнаружения инцидентов
2. **Task7** - **предотвращает** инциденты через admission control

### Комбинированная защита:

```
┌─────────────────────────────────────────────────┐
│  kubectl apply pod.yaml                         │
└─────────────┬───────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────┐
│  Admission Control (Task7)                      │
│  ├─ Pod Security Admission (PSS)                │
│  └─ OPA Gatekeeper                              │
│       → Блокирует небезопасные поды             │
└─────────────┬───────────────────────────────────┘
              │
              ▼ (если разрешено)
┌─────────────────────────────────────────────────┐
│  Audit Logging (Task6)                          │
│  └─ Логирует все действия                       │
└─────────────────────────────────────────────────┘
```

### Audit Policy для Task7:

```yaml
# Логирует ВСЕ попытки создания подов
- level: RequestResponse
  verbs: ["create", "update", "patch"]
  resources:
    - group: ""
      resources: ["pods"]
```

**Результат:** В `/var/log/audit.log` будут события:
- ✅ Успешные создания secure подов
- ❌ Заблокированные попытки создания небезопасных подов

---

## Troubleshooting

### Проблема: Pod Security не блокирует поды

**Причина:** Kubernetes < 1.23 или не включен PodSecurity admission plugin

**Решение:**
```bash
# Проверить версию
kubectl version --short

# Для minikube:
minikube start --kubernetes-version=v1.28.0 \
  --extra-config=apiserver.enable-admission-plugins=PodSecurity
```

### Проблема: Gatekeeper не блокирует

**Причина:** Constraints не применены или webhook не работает

**Решение:**
```bash
# Проверить webhook
kubectl get validatingwebhookconfiguration | grep gatekeeper

# Проверить constraints
kubectl get constraints -A

# Проверить логи
kubectl logs -n gatekeeper-system -l app=gatekeeper --tail=50
```

### Проблема: Secure поды не запускаются

**Причина:** Образ требует root или write access

**Решение:**
```yaml
# Добавить volumes для writable directories
volumeMounts:
- name: tmp
  mountPath: /tmp
volumes:
- name: tmp
  emptyDir: {}
```

---

## Критерии приемки (Checklist)

### Обязательные требования:

- [x] Namespace `audit-zone` с labels `pod-security.kubernetes.io/enforce: restricted`
- [x] 3 insecure манифеста блокируются Pod Security Admission
- [x] 3 secure манифеста успешно запускаются
- [x] OPA Gatekeeper установлен и работает
- [x] 4 ConstraintTemplates созданы
- [x] 4 Constraints применены к namespace
- [x] Скрипты проверки работают корректно

### Дополнительные требования:

- [x] Audit policy для логирования попыток
- [x] README с инструкциями
- [x] Комментарии в манифестах
- [x] Примеры исправлений нарушений

---

## Безопасность в PropDevelopment

### Применение в production:

1. **Namespace isolation:**
   - `propdevelopment-prod` → `pod-security: restricted`
   - `propdevelopment-staging` → `pod-security: baseline`
   - `propdevelopment-dev` → `pod-security: baseline` (с warnings)

2. **Gatekeeper политики:**
   - Запрет hostPath для всех namespaces кроме kube-system
   - Требование runAsNonRoot для всех приложений
   - Обязательный readOnlyRootFilesystem
   - Лимиты на resources (CPU/memory)

3. **CI/CD интеграция:**
   ```bash
   # Pre-commit hook
   kubectl apply --dry-run=server -f deployment.yaml
   
   # Если fail → блокировать merge
   ```

4. **Мониторинг:**
   - Алерты на Gatekeeper violations
   - Audit log → SIEM (ELK/Splunk)
   - Metrics: violation count, denial rate

---

## Полезные команды

```bash
# Проверить Pod Security labels всех namespaces
kubectl get namespaces -o custom-columns=NAME:.metadata.name,ENFORCE:.metadata.labels.pod-security\.kubernetes\.io/enforce

# Список всех ConstraintTemplates
kubectl get constrainttemplates

# Список всех Constraints
kubectl get constraints --all-namespaces

# Violations (если есть)
kubectl get k8spspprivileged psp-privileged-container -o yaml

# Проверить security context всех подов
kubectl get pods -n audit-zone -o json | jq '.items[] | {name: .metadata.name, securityContext: .spec.securityContext}'

# Audit log (если настроен)
kubectl logs -n kube-system kube-apiserver-* | grep audit-zone
```

---

## Дополнительные ресурсы

### Официальная документация:

- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/)
- [OPA Gatekeeper](https://open-policy-agent.github.io/gatekeeper/website/)
- [Rego Language](https://www.openpolicyagent.org/docs/latest/policy-language/)

### Best Practices:

- [NSA Kubernetes Hardening Guide](https://media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)

---

## Контакты

**Автор:** PropDevelopment Security Team  
**Задание:** Task7 - Container Security Policy  
**Дата:** Ноябрь 2025  
**Статус:** ✅ Готово к проверке

---

## Выводы

Task7 реализует **многоуровневую защиту** контейнеров:

1. **Pod Security Standards** - встроенная baseline защита
2. **OPA Gatekeeper** - кастомные политики для специфичных требований
3. **Audit Logging** (Task6) - обнаружение аномалий

Результат: **Defense in Depth** подход к безопасности контейнеров в Kubernetes.

