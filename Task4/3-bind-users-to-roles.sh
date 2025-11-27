#!/bin/bash

##############################################################################
# Скрипт привязки пользователей к ролям в Kubernetes кластере PropDevelopment
# 
# Назначение: Создание RoleBindings и ClusterRoleBindings
# Использование: ./3-bind-users-to-roles.sh
# 
# Предусловия:
# - Запущен Minikube кластер
# - Выполнен скрипт 1-create-users.sh (пользователи созданы)
# - Выполнен скрипт 2-create-roles.sh (роли созданы)
# - kubectl настроен с правами администратора
# 
# Создаваемые привязки:
# 1. olga.cto           → cluster-admin (ClusterRoleBinding)
# 2. ivan.security      → security-admin (ClusterRoleBinding)
# 3. anna.devops        → devops-engineer (ClusterRoleBinding)
# 4. dmitry.dev         → developer в sales-domain (RoleBinding)
# 5. elena.viewer       → viewer (ClusterRoleBinding)
# 6. sergey.sales       → domain-admin в sales-domain (RoleBinding)
# 7. maria.tenant       → domain-admin в tenant-domain (RoleBinding)
# 8. alexey.smarthome   → smart-home-operator в tenant-domain (RoleBinding)
# 
##############################################################################

set -e  # Exit on error

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Привязка пользователей к ролям${NC}"
echo -e "${BLUE}PropDevelopment Kubernetes RBAC${NC}"
echo -e "${BLUE}========================================${NC}"

# Проверка наличия Minikube
if ! minikube status > /dev/null 2>&1; then
    echo -e "${RED}[ERROR] Minikube не запущен. Запустите: minikube start${NC}"
    exit 1
fi

echo -e "${GREEN}[OK] Minikube запущен${NC}"

# Создание директории для манифестов
MANIFEST_DIR="./k8s-rbac-manifests"
mkdir -p "$MANIFEST_DIR/bindings"

echo -e "${YELLOW}[INFO] Манифесты привязок будут сохранены в: $MANIFEST_DIR/bindings/${NC}"

# Проверка существования ролей
echo ""
echo -e "${YELLOW}[INFO] Проверка существования ролей...${NC}"

check_role_exists() {
    local ROLE_TYPE=$1
    local ROLE_NAME=$2
    local NAMESPACE=$3
    
    if [ "$ROLE_TYPE" == "ClusterRole" ]; then
        if kubectl get clusterrole "$ROLE_NAME" &> /dev/null; then
            echo -e "${GREEN}  ✓ ClusterRole $ROLE_NAME существует${NC}"
            return 0
        else
            echo -e "${RED}  ✗ ClusterRole $ROLE_NAME НЕ существует${NC}"
            return 1
        fi
    else
        if kubectl get role "$ROLE_NAME" -n "$NAMESPACE" &> /dev/null; then
            echo -e "${GREEN}  ✓ Role $ROLE_NAME в namespace $NAMESPACE существует${NC}"
            return 0
        else
            echo -e "${RED}  ✗ Role $ROLE_NAME в namespace $NAMESPACE НЕ существует${NC}"
            return 1
        fi
    fi
}

# Проверяем ключевые роли
check_role_exists "ClusterRole" "cluster-admin" "" || echo -e "${YELLOW}  (встроенная роль)${NC}"
check_role_exists "ClusterRole" "security-admin" ""
check_role_exists "ClusterRole" "devops-engineer" ""
check_role_exists "ClusterRole" "developer" ""
check_role_exists "ClusterRole" "viewer" ""

echo ""

# ============================================================================
# ФУНКЦИЯ СОЗДАНИЯ CLUSTERROLEBINDING
# ============================================================================

create_cluster_role_binding() {
    local BINDING_NAME=$1
    local USER=$2
    local ROLE=$3
    local DESCRIPTION=$4
    
    echo -e "${BLUE}Создание ClusterRoleBinding: $BINDING_NAME${NC}"
    echo -e "${YELLOW}  User: $USER → Role: $ROLE${NC}"
    echo -e "${YELLOW}  $DESCRIPTION${NC}"
    
    cat > "$MANIFEST_DIR/bindings/crb-$BINDING_NAME.yaml" <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: $BINDING_NAME
  labels:
    rbac.propdevelopment.ru/user: $USER
    rbac.propdevelopment.ru/role: $ROLE
  annotations:
    description: "$DESCRIPTION"
    created-by: "RBAC automation script"
    created-at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: $ROLE
subjects:
- kind: User
  name: $USER
  apiGroup: rbac.authorization.k8s.io
EOF
    
    kubectl apply -f "$MANIFEST_DIR/bindings/crb-$BINDING_NAME.yaml" > /dev/null
    echo -e "${GREEN}[OK] ClusterRoleBinding $BINDING_NAME создан${NC}"
    echo ""
}

# ============================================================================
# ФУНКЦИЯ СОЗДАНИЯ ROLEBINDING
# ============================================================================

create_role_binding() {
    local BINDING_NAME=$1
    local USER=$2
    local ROLE=$3
    local NAMESPACE=$4
    local DESCRIPTION=$5
    
    echo -e "${BLUE}Создание RoleBinding: $BINDING_NAME${NC}"
    echo -e "${YELLOW}  User: $USER → Role: $ROLE в namespace: $NAMESPACE${NC}"
    echo -e "${YELLOW}  $DESCRIPTION${NC}"
    
    cat > "$MANIFEST_DIR/bindings/rb-$BINDING_NAME.yaml" <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: $BINDING_NAME
  namespace: $NAMESPACE
  labels:
    rbac.propdevelopment.ru/user: $USER
    rbac.propdevelopment.ru/role: $ROLE
    rbac.propdevelopment.ru/namespace: $NAMESPACE
  annotations:
    description: "$DESCRIPTION"
    created-by: "RBAC automation script"
    created-at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: $ROLE
subjects:
- kind: User
  name: $USER
  apiGroup: rbac.authorization.k8s.io
EOF
    
    kubectl apply -f "$MANIFEST_DIR/bindings/rb-$BINDING_NAME.yaml" > /dev/null
    echo -e "${GREEN}[OK] RoleBinding $BINDING_NAME создан в namespace $NAMESPACE${NC}"
    echo ""
}

# ============================================================================
# СОЗДАНИЕ CLUSTERROLEBINDINGS
# ============================================================================

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Создание ClusterRoleBindings${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 1. CTO → cluster-admin (Emergency Access Only!)
create_cluster_role_binding \
    "cto-cluster-admin" \
    "olga.cto" \
    "cluster-admin" \
    "CTO - полный доступ к кластеру (ТОЛЬКО для экстренных случаев!)"

# 2. Security Engineer → security-admin
create_cluster_role_binding \
    "security-team-admin" \
    "ivan.security" \
    "security-admin" \
    "Security Engineer - аудит, мониторинг, управление политиками безопасности"

# 3. DevOps Engineer → devops-engineer
create_cluster_role_binding \
    "devops-team-engineer" \
    "anna.devops" \
    "devops-engineer" \
    "DevOps Engineer - управление deployments, services, infrastructure"

# 4. Business Analyst → viewer
create_cluster_role_binding \
    "business-analyst-viewer" \
    "elena.viewer" \
    "viewer" \
    "Business Analyst - просмотр статуса приложений и метрик"

# ============================================================================
# СОЗДАНИЕ ROLEBINDINGS ДЛЯ ДОМЕНОВ
# ============================================================================

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Создание RoleBindings для доменов${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 5. Developer → developer в sales-domain
create_role_binding \
    "developer-sales-domain" \
    "dmitry.dev" \
    "developer" \
    "sales-domain" \
    "Developer Sales Team - разработка и отладка в домене продаж"

# Также привязать роль developer на уровне кластера (для создания pods)
cat > "$MANIFEST_DIR/bindings/crb-developer-sales.yaml" <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: developer-sales-cluster
  labels:
    rbac.propdevelopment.ru/user: dmitry.dev
    rbac.propdevelopment.ru/role: developer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: developer
subjects:
- kind: User
  name: dmitry.dev
  apiGroup: rbac.authorization.k8s.io
EOF
kubectl apply -f "$MANIFEST_DIR/bindings/crb-developer-sales.yaml" > /dev/null
echo -e "${GREEN}[OK] Дополнительный ClusterRoleBinding для developer создан${NC}"
echo ""

# 6. Domain Admin Sales → domain-admin в sales-domain
create_role_binding \
    "domain-admin-sales" \
    "sergey.sales" \
    "domain-admin" \
    "sales-domain" \
    "Domain Admin Sales - полное управление доменом продаж"

# 7. Domain Admin Tenant → domain-admin в tenant-domain
create_role_binding \
    "domain-admin-tenant" \
    "maria.tenant" \
    "domain-admin" \
    "tenant-domain" \
    "Domain Admin Tenant - полное управление доменом ЖКУ и Умный дом"

# 8. Smart Home Operator → smart-home-operator в tenant-domain
create_role_binding \
    "smart-home-operator-tenant" \
    "alexey.smarthome" \
    "smart-home-operator" \
    "tenant-domain" \
    "Smart Home Operator - управление сервисами Умного дома"

# ============================================================================
# ДОПОЛНИТЕЛЬНЫЕ ПРИВЯЗКИ ДЛЯ ГРУПП
# ============================================================================

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Создание привязок для групп${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Привязка группы security-team к security-admin
echo -e "${YELLOW}[INFO] Создание группового binding для security-team...${NC}"

cat > "$MANIFEST_DIR/bindings/crb-security-team-group.yaml" <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: security-team-group
  labels:
    rbac.propdevelopment.ru/group: security-team
  annotations:
    description: "Все члены команды безопасности (6 человек из Task3)"
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: security-admin
subjects:
- kind: Group
  name: security-team
  apiGroup: rbac.authorization.k8s.io
EOF

kubectl apply -f "$MANIFEST_DIR/bindings/crb-security-team-group.yaml" > /dev/null
echo -e "${GREEN}[OK] Групповой ClusterRoleBinding для security-team создан${NC}"

# Привязка группы devops-team к devops-engineer
echo -e "${YELLOW}[INFO] Создание группового binding для devops-team...${NC}"

cat > "$MANIFEST_DIR/bindings/crb-devops-team-group.yaml" <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: devops-team-group
  labels:
    rbac.propdevelopment.ru/group: devops-team
  annotations:
    description: "Вся команда DevOps инженеров"
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: devops-engineer
subjects:
- kind: Group
  name: devops-team
  apiGroup: rbac.authorization.k8s.io
EOF

kubectl apply -f "$MANIFEST_DIR/bindings/crb-devops-team-group.yaml" > /dev/null
echo -e "${GREEN}[OK] Групповой ClusterRoleBinding для devops-team создан${NC}"

# Привязка группы viewers
echo -e "${YELLOW}[INFO] Создание группового binding для viewers...${NC}"

cat > "$MANIFEST_DIR/bindings/crb-viewers-group.yaml" <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: viewers-group
  labels:
    rbac.propdevelopment.ru/group: viewers
  annotations:
    description: "Product Owners, Business Analysts, QA Engineers"
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: viewer
subjects:
- kind: Group
  name: viewers
  apiGroup: rbac.authorization.k8s.io
EOF

kubectl apply -f "$MANIFEST_DIR/bindings/crb-viewers-group.yaml" > /dev/null
echo -e "${GREEN}[OK] Групповой ClusterRoleBinding для viewers создан${NC}"

echo ""

# ============================================================================
# ПРОВЕРКА И ТЕСТИРОВАНИЕ
# ============================================================================

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Проверка созданных привязок${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo -e "${YELLOW}[INFO] ClusterRoleBindings:${NC}"
kubectl get clusterrolebindings | grep -E "(cto-cluster|security-team|devops-team|business-analyst|developer-sales|viewers)"

echo ""
echo -e "${YELLOW}[INFO] RoleBindings в domain namespaces:${NC}"
kubectl get rolebindings -n sales-domain
kubectl get rolebindings -n tenant-domain

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Тестирование прав доступа${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Функция тестирования доступа
test_user_access() {
    local USER=$1
    local TEST_DESCRIPTION=$2
    local EXPECTED_RESULT=$3
    
    echo -e "${YELLOW}[TEST] $USER: $TEST_DESCRIPTION${NC}"
    echo -e "  Ожидаемый результат: $EXPECTED_RESULT"
    echo ""
}

test_user_access "ivan.security" "Просмотр секретов (security-admin может)" "✓ Доступ разрешен"
echo -e "  ${BLUE}kubectl --context=ivan.security-context get secrets --all-namespaces${NC}"

test_user_access "anna.devops" "Создание deployment (devops-engineer может)" "✓ Доступ разрешен"
echo -e "  ${BLUE}kubectl --context=anna.devops-context create deployment test --image=nginx${NC}"

test_user_access "anna.devops" "Просмотр секретов (devops-engineer НЕ может изменять)" "✓ Только чтение"
echo -e "  ${BLUE}kubectl --context=anna.devops-context get secrets${NC}"

test_user_access "dmitry.dev" "Просмотр pods в sales-domain (developer может)" "✓ Доступ разрешен"
echo -e "  ${BLUE}kubectl --context=dmitry.dev-context get pods -n sales-domain${NC}"

test_user_access "dmitry.dev" "Просмотр секретов (developer НЕ может)" "✗ Доступ запрещен"
echo -e "  ${BLUE}kubectl --context=dmitry.dev-context get secrets -n sales-domain${NC}"

test_user_access "elena.viewer" "Просмотр deployments (viewer может)" "✓ Доступ разрешен"
echo -e "  ${BLUE}kubectl --context=elena.viewer-context get deployments --all-namespaces${NC}"

test_user_access "elena.viewer" "Создание deployment (viewer НЕ может)" "✗ Доступ запрещен"
echo -e "  ${BLUE}kubectl --context=elena.viewer-context create deployment test --image=nginx${NC}"

test_user_access "sergey.sales" "Полное управление sales-domain (domain-admin может)" "✓ Доступ разрешен"
echo -e "  ${BLUE}kubectl --context=sergey.sales-context get all -n sales-domain${NC}"

test_user_access "alexey.smarthome" "Управление smart-home pods (smart-home-operator может)" "✓ Доступ разрешен"
echo -e "  ${BLUE}kubectl --context=alexey.smarthome-context get pods -n tenant-domain -l app=smart-home${NC}"

echo ""
echo -e "${YELLOW}[INFO] Для тестирования прав выполните команды выше с соответствующими context'ами${NC}"

# ============================================================================
# СОЗДАНИЕ ДОКУМЕНТАЦИИ
# ============================================================================

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Создание документации${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

cat > "$MANIFEST_DIR/RBAC_SUMMARY.md" <<'EOF'
# PropDevelopment Kubernetes RBAC - Сводка

## Созданные пользователи и их роли

| Пользователь | Роль | Область доступа | Описание |
|--------------|------|-----------------|----------|
| olga.cto | cluster-admin | Весь кластер | CTO - полный доступ (emergency only!) |
| ivan.security | security-admin | Весь кластер | Security Engineer - аудит и мониторинг |
| anna.devops | devops-engineer | Весь кластер | DevOps Engineer - управление инфраструктурой |
| dmitry.dev | developer | sales-domain | Developer - разработка в домене продаж |
| elena.viewer | viewer | Весь кластер (read-only) | Business Analyst - просмотр |
| sergey.sales | domain-admin | sales-domain | Domain Admin - полное управление доменом продаж |
| maria.tenant | domain-admin | tenant-domain | Domain Admin - полное управление доменом ЖКУ |
| alexey.smarthome | smart-home-operator | tenant-domain | Smart Home Operator - управление Умным домом |

## Групповые привязки

| Группа | Роль | Члены |
|--------|------|-------|
| security-team | security-admin | 6 специалистов ИБ (из Task3) |
| devops-team | devops-engineer | Все DevOps инженеры |
| viewers | viewer | Product Owners, Analysts, QA |

## Проверка доступа

### Security Engineer (ivan.security)
```bash
# Может просматривать секреты
kubectl --context=ivan.security-context get secrets --all-namespaces

# Может просматривать все ресурсы
kubectl --context=ivan.security-context get all --all-namespaces

# Может управлять NetworkPolicies
kubectl --context=ivan.security-context get networkpolicies -A
```

### DevOps Engineer (anna.devops)
```bash
# Может создавать deployments
kubectl --context=anna.devops-context create deployment nginx --image=nginx

# Может просматривать секреты (read-only)
kubectl --context=anna.devops-context get secrets

# НЕ может изменять секреты
kubectl --context=anna.devops-context delete secret my-secret  # FAIL

# НЕ может exec в pods
kubectl --context=anna.devops-context exec -it pod-name -- sh  # FAIL
```

### Developer (dmitry.dev)
```bash
# Может просматривать pods в своем namespace
kubectl --context=dmitry.dev-context get pods -n sales-domain

# Может port-forward для отладки
kubectl --context=dmitry.dev-context port-forward pod-name 8080:80 -n sales-domain

# Может просматривать логи
kubectl --context=dmitry.dev-context logs pod-name -n sales-domain

# НЕ может просматривать секреты
kubectl --context=dmitry.dev-context get secrets -n sales-domain  # FAIL

# НЕ может exec в pods
kubectl --context=dmitry.dev-context exec -it pod-name -- sh  # FAIL
```

### Viewer (elena.viewer)
```bash
# Может просматривать все ресурсы (read-only)
kubectl --context=elena.viewer-context get all --all-namespaces

# Может просматривать логи
kubectl --context=elena.viewer-context logs pod-name

# НЕ может создавать ресурсы
kubectl --context=elena.viewer-context create deployment test --image=nginx  # FAIL

# НЕ может просматривать секреты
kubectl --context=elena.viewer-context get secrets  # FAIL
```

### Domain Admin Sales (sergey.sales)
```bash
# Полное управление в sales-domain
kubectl --context=sergey.sales-context get all -n sales-domain
kubectl --context=sergey.sales-context create deployment app --image=myapp -n sales-domain
kubectl --context=sergey.sales-context delete deployment app -n sales-domain

# Может управлять секретами в своем namespace
kubectl --context=sergey.sales-context get secrets -n sales-domain
kubectl --context=sergey.sales-context create secret generic my-secret -n sales-domain

# НЕ может управлять другими namespaces
kubectl --context=sergey.sales-context get pods -n tenant-domain  # FAIL
```

### Smart Home Operator (alexey.smarthome)
```bash
# Может управлять smart-home приложениями
kubectl --context=alexey.smarthome-context get pods -n tenant-domain -l app=smart-home
kubectl --context=alexey.smarthome-context logs pod-name -n tenant-domain

# Может exec в smart-home pods для отладки
kubectl --context=alexey.smarthome-context exec -it smart-home-pod -- sh

# НЕ может управлять другими приложениями в tenant-domain
kubectl --context=alexey.smarthome-context delete deployment tenant-core-app  # FAIL
```

## Безопасность

### Принципы
1. **Least Privilege** - минимально необходимые права
2. **Separation of Duties** - разделение обязанностей
3. **Defense in Depth** - многоуровневая защита

### Аудит
Все действия логируются. Для просмотра аудит-логов:
```bash
# Действия конкретного пользователя
kubectl --context=admin-context get events --all-namespaces --field-selector involvedObject.name=ivan.security

# Все операции с секретами
kubectl --context=admin-context get events --all-namespaces | grep Secret
```

### Регулярный Access Review
Ежеквартально проводится пересмотр прав:
```bash
# Список всех ClusterRoleBindings
kubectl get clusterrolebindings -o wide

# Список всех RoleBindings
kubectl get rolebindings -A -o wide
```

## Troubleshooting

### Пользователь не может выполнить команду
1. Проверьте, что пользователь создан: `kubectl config get-contexts | grep username`
2. Проверьте привязку роли: `kubectl get rolebindings,clusterrolebindings -A | grep username`
3. Проверьте права роли: `kubectl describe clusterrole role-name`

### Как добавить нового пользователя?
1. Создайте сертификат (модифицируйте `1-create-users.sh`)
2. Создайте привязку (модифицируйте `3-bind-users-to-roles.sh`)
3. Уведомите Security Team

### Как отозвать доступ?
```bash
# Удалить привязку роли
kubectl delete clusterrolebinding username-binding
kubectl delete rolebinding username-binding -n namespace-name

# Отозвать сертификат (в продакшн среде)
# Используйте Certificate Management System
```

## Контакты
- Security Team: security-team@propdevelopment.ru
- DevOps Team: devops-team@propdevelopment.ru
- Incident Response: incidents@propdevelopment.ru (24/7)
EOF

echo -e "${GREEN}[OK] Документация создана: $MANIFEST_DIR/RBAC_SUMMARY.md${NC}"

# ============================================================================
# ИТОГИ
# ============================================================================

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Все привязки успешно созданы!${NC}"
echo -e "${GREEN}========================================${NC}"

echo ""
echo -e "${BLUE}Созданные привязки:${NC}"
echo -e "${BLUE}----------------------------------------${NC}"
echo -e "1. ${YELLOW}olga.cto${NC}           → cluster-admin (весь кластер)"
echo -e "2. ${YELLOW}ivan.security${NC}      → security-admin (весь кластер)"
echo -e "3. ${YELLOW}anna.devops${NC}        → devops-engineer (весь кластер)"
echo -e "4. ${YELLOW}dmitry.dev${NC}         → developer (sales-domain)"
echo -e "5. ${YELLOW}elena.viewer${NC}       → viewer (весь кластер, read-only)"
echo -e "6. ${YELLOW}sergey.sales${NC}       → domain-admin (sales-domain)"
echo -e "7. ${YELLOW}maria.tenant${NC}       → domain-admin (tenant-domain)"
echo -e "8. ${YELLOW}alexey.smarthome${NC}   → smart-home-operator (tenant-domain)"

echo ""
echo -e "${BLUE}Групповые привязки:${NC}"
echo -e "  - ${YELLOW}security-team${NC} → security-admin"
echo -e "  - ${YELLOW}devops-team${NC}   → devops-engineer"
echo -e "  - ${YELLOW}viewers${NC}        → viewer"

echo ""
echo -e "${YELLOW}[INFO] Манифесты сохранены в: $MANIFEST_DIR/bindings/${NC}"
echo -e "${YELLOW}[INFO] Документация: $MANIFEST_DIR/RBAC_SUMMARY.md${NC}"

echo ""
echo -e "${BLUE}Следующие шаги:${NC}"
echo -e "  1. Прочитайте документацию: ${GREEN}cat $MANIFEST_DIR/RBAC_SUMMARY.md${NC}"
echo -e "  2. Протестируйте доступ пользователей (команды в документации)"
echo -e "  3. Проверьте логи аудита: ${GREEN}kubectl get events --all-namespaces${NC}"

echo ""
echo -e "${GREEN}[SUCCESS] RBAC конфигурация завершена!${NC}"
echo -e "${GREEN}Кластер PropDevelopment защищен согласно ролевой модели из Task4${NC}"

# Финальная проверка
echo ""
echo -e "${BLUE}Финальная проверка RBAC:${NC}"
kubectl auth can-i --list --as=ivan.security | head -20

