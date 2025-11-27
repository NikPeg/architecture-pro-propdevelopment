#!/bin/bash

##############################################################################
# Скрипт создания ролей для Kubernetes кластера PropDevelopment
# 
# Назначение: Создание ClusterRoles и Roles согласно ролевой модели
# Использование: ./2-create-roles.sh
# 
# Предусловия:
# - Запущен Minikube кластер
# - kubectl настроен с правами администратора
# - Созданы namespace для доменов
# 
# Создаваемые роли:
# ClusterRoles (cluster-wide):
# 1. security-admin         - Для команды безопасности
# 2. devops-engineer        - Для DevOps команды
# 3. developer              - Для разработчиков
# 4. viewer                 - Для бизнес-пользователей
# 5. monitoring-reader      - Для систем мониторинга
# 6. logs-reader            - Для систем логирования
# 7. ci-cd-deployer         - Для CI/CD систем
# 
# Roles (namespace-specific):
# 8. domain-admin (в каждом domain namespace)
# 9. smart-home-operator (в tenant-domain)
# 
# Примечание: cluster-admin роль уже существует в Kubernetes (встроенная)
##############################################################################

set -e  # Exit on error

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Создание ролей для кластера PropDevelopment${NC}"
echo -e "${BLUE}========================================${NC}"

# Проверка наличия Minikube
if ! minikube status > /dev/null 2>&1; then
    echo -e "${RED}[ERROR] Minikube не запущен. Запустите: minikube start${NC}"
    exit 1
fi

echo -e "${GREEN}[OK] Minikube запущен${NC}"

# Создание директории для манифестов
MANIFEST_DIR="./k8s-rbac-manifests"
mkdir -p "$MANIFEST_DIR"

echo -e "${YELLOW}[INFO] Манифесты будут сохранены в: $MANIFEST_DIR${NC}"

# ============================================================================
# СОЗДАНИЕ NAMESPACES ДЛЯ ДОМЕНОВ
# ============================================================================

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Создание namespaces для доменов${NC}"
echo -e "${BLUE}========================================${NC}"

create_namespace() {
    local NS=$1
    local DESCRIPTION=$2
    
    echo -e "${YELLOW}[INFO] Создание namespace: $NS${NC}"
    
    cat <<EOF | kubectl apply -f - > /dev/null
apiVersion: v1
kind: Namespace
metadata:
  name: $NS
  labels:
    domain: $NS
    description: "$DESCRIPTION"
EOF
    
    echo -e "${GREEN}[OK] Namespace $NS создан${NC}"
}

create_namespace "sales-domain" "Домен продаж (client-mart-app, client-crm-app)"
create_namespace "tenant-domain" "Домен ЖКУ (tenant-core-app, smart-home-service)"
create_namespace "finance-domain" "Домен финансов (accountant-service-1)"
create_namespace "data-domain" "Домен данных (DWH, auth-service)"
create_namespace "monitoring" "Системы мониторинга (Prometheus, Grafana)"
create_namespace "logging" "Системы логирования (ELK Stack)"

echo ""

# ============================================================================
# CLUSTERROLE: security-admin
# ============================================================================

echo -e "${BLUE}[1/9] Создание ClusterRole: security-admin${NC}"

cat > "$MANIFEST_DIR/clusterrole-security-admin.yaml" <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: security-admin
  labels:
    rbac.propdevelopment.ru/role: security
rules:
# Read-only доступ ко всем ресурсам (для аудита)
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]

# Специальный доступ к Secrets (для анализа, но не изменения)
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list", "watch"]

# Управление NetworkPolicies (для изоляции при инцидентах)
- apiGroups: ["networking.k8s.io"]
  resources: ["networkpolicies"]
  verbs: ["get", "list", "watch", "create", "update", "delete"]

# Управление PodSecurityPolicies
- apiGroups: ["policy"]
  resources: ["podsecuritypolicies"]
  verbs: ["get", "list", "watch", "create", "update", "delete"]

# Доступ к RBAC для аудита (read-only)
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
  verbs: ["get", "list", "watch"]

# Доступ к Events для расследования
- apiGroups: [""]
  resources: ["events"]
  verbs: ["get", "list", "watch"]

# Доступ к метрикам
- apiGroups: ["metrics.k8s.io"]
  resources: ["pods", "nodes"]
  verbs: ["get", "list"]
EOF

kubectl apply -f "$MANIFEST_DIR/clusterrole-security-admin.yaml" > /dev/null
echo -e "${GREEN}[OK] ClusterRole security-admin создана${NC}"

# ============================================================================
# CLUSTERROLE: devops-engineer
# ============================================================================

echo -e "${BLUE}[2/9] Создание ClusterRole: devops-engineer${NC}"

cat > "$MANIFEST_DIR/clusterrole-devops-engineer.yaml" <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: devops-engineer
  labels:
    rbac.propdevelopment.ru/role: devops
rules:
# Полное управление Deployments, StatefulSets, DaemonSets
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets", "daemonsets", "replicasets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

# Управление Services, Ingresses
- apiGroups: [""]
  resources: ["services", "endpoints"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

# Управление ConfigMaps (полный доступ)
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

# Read-only доступ к Secrets (не может создавать/изменять!)
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list", "watch"]

# Просмотр Pods (но НЕТ exec!)
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]

# Управление Jobs и CronJobs
- apiGroups: ["batch"]
  resources: ["jobs", "cronjobs"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

# Управление PersistentVolumeClaims
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

# Управление HorizontalPodAutoscaler
- apiGroups: ["autoscaling"]
  resources: ["horizontalpodautoscalers"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

# Просмотр Events
- apiGroups: [""]
  resources: ["events"]
  verbs: ["get", "list", "watch"]

# Просмотр Nodes и метрик
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["metrics.k8s.io"]
  resources: ["pods", "nodes"]
  verbs: ["get", "list"]

# Просмотр Namespaces
- apiGroups: [""]
  resources: ["namespaces"]
  verbs: ["get", "list", "watch"]
EOF

kubectl apply -f "$MANIFEST_DIR/clusterrole-devops-engineer.yaml" > /dev/null
echo -e "${GREEN}[OK] ClusterRole devops-engineer создана${NC}"

# ============================================================================
# CLUSTERROLE: developer
# ============================================================================

echo -e "${BLUE}[3/9] Создание ClusterRole: developer${NC}"

cat > "$MANIFEST_DIR/clusterrole-developer.yaml" <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: developer
  labels:
    rbac.propdevelopment.ru/role: developer
rules:
# Просмотр Pods, Deployments, Services
- apiGroups: [""]
  resources: ["pods", "services", "endpoints"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets", "statefulsets"]
  verbs: ["get", "list", "watch"]

# Доступ к логам
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get", "list", "watch"]

# Port-forward для локальной отладки
- apiGroups: [""]
  resources: ["pods/portforward"]
  verbs: ["create", "get"]

# Просмотр ConfigMaps (read-only)
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list", "watch"]

# Просмотр Events
- apiGroups: [""]
  resources: ["events"]
  verbs: ["get", "list", "watch"]

# Создание/удаление Pods для отладки (но не update!)
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["create", "delete"]

# НЕТ доступа к Secrets
# НЕТ exec в Pods (безопасность)
EOF

kubectl apply -f "$MANIFEST_DIR/clusterrole-developer.yaml" > /dev/null
echo -e "${GREEN}[OK] ClusterRole developer создана${NC}"

# ============================================================================
# CLUSTERROLE: viewer
# ============================================================================

echo -e "${BLUE}[4/9] Создание ClusterRole: viewer${NC}"

cat > "$MANIFEST_DIR/clusterrole-viewer.yaml" <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: viewer
  labels:
    rbac.propdevelopment.ru/role: viewer
rules:
# Read-only на основные ресурсы
- apiGroups: [""]
  resources: ["pods", "services", "endpoints", "configmaps"]
  verbs: ["get", "list", "watch"]

- apiGroups: ["apps"]
  resources: ["deployments", "replicasets", "statefulsets", "daemonsets"]
  verbs: ["get", "list", "watch"]

- apiGroups: ["batch"]
  resources: ["jobs", "cronjobs"]
  verbs: ["get", "list", "watch"]

# Доступ к логам
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get", "list", "watch"]

# Доступ к Events
- apiGroups: [""]
  resources: ["events"]
  verbs: ["get", "list", "watch"]

# Просмотр Ingresses
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "watch"]

# Просмотр PVCs
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["get", "list", "watch"]

# Просмотр HPA
- apiGroups: ["autoscaling"]
  resources: ["horizontalpodautoscalers"]
  verbs: ["get", "list", "watch"]

# Просмотр Namespaces
- apiGroups: [""]
  resources: ["namespaces"]
  verbs: ["get", "list"]

# Доступ к метрикам
- apiGroups: ["metrics.k8s.io"]
  resources: ["pods", "nodes"]
  verbs: ["get", "list"]

# НЕТ доступа к Secrets
# НЕТ изменения ресурсов
# НЕТ exec, port-forward
EOF

kubectl apply -f "$MANIFEST_DIR/clusterrole-viewer.yaml" > /dev/null
echo -e "${GREEN}[OK] ClusterRole viewer создана${NC}"

# ============================================================================
# CLUSTERROLE: monitoring-reader
# ============================================================================

echo -e "${BLUE}[5/9] Создание ClusterRole: monitoring-reader${NC}"

cat > "$MANIFEST_DIR/clusterrole-monitoring-reader.yaml" <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: monitoring-reader
  labels:
    rbac.propdevelopment.ru/role: monitoring
rules:
# Доступ к метрикам
- apiGroups: ["metrics.k8s.io"]
  resources: ["pods", "nodes"]
  verbs: ["get", "list", "watch"]

# Доступ к Pods для Prometheus
- apiGroups: [""]
  resources: ["pods", "nodes", "services", "endpoints"]
  verbs: ["get", "list", "watch"]

# Доступ к Events
- apiGroups: [""]
  resources: ["events"]
  verbs: ["get", "list", "watch"]

# Доступ к Namespaces
- apiGroups: [""]
  resources: ["namespaces"]
  verbs: ["get", "list", "watch"]

# НЕТ доступа к Secrets
EOF

kubectl apply -f "$MANIFEST_DIR/clusterrole-monitoring-reader.yaml" > /dev/null
echo -e "${GREEN}[OK] ClusterRole monitoring-reader создана${NC}"

# ============================================================================
# CLUSTERROLE: logs-reader
# ============================================================================

echo -e "${BLUE}[6/9] Создание ClusterRole: logs-reader${NC}"

cat > "$MANIFEST_DIR/clusterrole-logs-reader.yaml" <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: logs-reader
  labels:
    rbac.propdevelopment.ru/role: logging
rules:
# Доступ к логам
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get", "list", "watch"]

# Доступ к Pods (метаданные)
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]

# Доступ к Events
- apiGroups: [""]
  resources: ["events"]
  verbs: ["get", "list", "watch"]

# НЕТ exec, port-forward
# НЕТ доступа к Secrets
EOF

kubectl apply -f "$MANIFEST_DIR/clusterrole-logs-reader.yaml" > /dev/null
echo -e "${GREEN}[OK] ClusterRole logs-reader создана${NC}"

# ============================================================================
# CLUSTERROLE: ci-cd-deployer
# ============================================================================

echo -e "${BLUE}[7/9] Создание ClusterRole: ci-cd-deployer${NC}"

cat > "$MANIFEST_DIR/clusterrole-ci-cd-deployer.yaml" <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ci-cd-deployer
  labels:
    rbac.propdevelopment.ru/role: automation
rules:
# Управление Deployments (но НЕТ delete!)
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]

# Управление Services
- apiGroups: [""]
  resources: ["services"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]

# Управление ConfigMaps
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]

# Read-only доступ к Secrets (для validation)
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list"]

# Управление Jobs (для миграций БД)
- apiGroups: ["batch"]
  resources: ["jobs"]
  verbs: ["get", "list", "watch", "create", "update"]

# Просмотр Pods и Events
- apiGroups: [""]
  resources: ["pods", "events"]
  verbs: ["get", "list", "watch"]

# Rollout операции
- apiGroups: ["apps"]
  resources: ["deployments/rollback", "deployments/status"]
  verbs: ["get", "update"]

# НЕТ delete на Deployments (безопасность)
# НЕТ exec, port-forward
EOF

kubectl apply -f "$MANIFEST_DIR/clusterrole-ci-cd-deployer.yaml" > /dev/null
echo -e "${GREEN}[OK] ClusterRole ci-cd-deployer создана${NC}"

# ============================================================================
# ROLE: domain-admin (в каждом domain namespace)
# ============================================================================

echo -e "${BLUE}[8/9] Создание Roles: domain-admin (в каждом domain)${NC}"

create_domain_admin_role() {
    local NS=$1
    local DOMAIN=$2
    
    echo -e "${YELLOW}[INFO] Создание Role domain-admin в namespace: $NS${NC}"
    
    cat > "$MANIFEST_DIR/role-domain-admin-$DOMAIN.yaml" <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: domain-admin
  namespace: $NS
  labels:
    rbac.propdevelopment.ru/role: domain-admin
    rbac.propdevelopment.ru/domain: $DOMAIN
rules:
# Полный доступ ко всем ресурсам в namespace
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]

# Управление RBAC в своем namespace
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["roles", "rolebindings"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
EOF
    
    kubectl apply -f "$MANIFEST_DIR/role-domain-admin-$DOMAIN.yaml" > /dev/null
    echo -e "${GREEN}[OK] Role domain-admin создана в $NS${NC}"
}

create_domain_admin_role "sales-domain" "sales"
create_domain_admin_role "tenant-domain" "tenant"
create_domain_admin_role "finance-domain" "finance"
create_domain_admin_role "data-domain" "data"

# ============================================================================
# ROLE: smart-home-operator (в tenant-domain)
# ============================================================================

echo -e "${BLUE}[9/9] Создание Role: smart-home-operator${NC}"

cat > "$MANIFEST_DIR/role-smart-home-operator.yaml" <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: smart-home-operator
  namespace: tenant-domain
  labels:
    rbac.propdevelopment.ru/role: smart-home
rules:
# Управление Deployments с label app=smart-home
- apiGroups: ["apps"]
  resources: ["deployments"]
  resourceNames: []  # Будет фильтроваться по label selector в реальном окружении
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

# Доступ к Pods с label app=smart-home
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]

# Exec и logs для отладки
- apiGroups: [""]
  resources: ["pods/exec", "pods/log"]
  verbs: ["create", "get"]

# Управление ConfigMaps для smart-home
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list", "watch", "update"]

# Read-only доступ к Secrets для smart-home
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list"]

# Управление Services и Ingresses для smart-home
- apiGroups: [""]
  resources: ["services"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
  
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]

# Управление HPA для smart-home
- apiGroups: ["autoscaling"]
  resources: ["horizontalpodautoscalers"]
  verbs: ["get", "list", "watch", "create", "update"]

# Доступ к Events
- apiGroups: [""]
  resources: ["events"]
  verbs: ["get", "list", "watch"]
EOF

kubectl apply -f "$MANIFEST_DIR/role-smart-home-operator.yaml" > /dev/null
echo -e "${GREEN}[OK] Role smart-home-operator создана${NC}"

# ============================================================================
# ИТОГИ
# ============================================================================

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Все роли успешно созданы!${NC}"
echo -e "${GREEN}========================================${NC}"

echo ""
echo -e "${BLUE}Созданные ClusterRoles:${NC}"
kubectl get clusterroles | grep -E "(security-admin|devops-engineer|developer|viewer|monitoring-reader|logs-reader|ci-cd-deployer)" || echo "  (показаны только custom роли)"

echo ""
echo -e "${BLUE}Созданные Roles в domain namespaces:${NC}"
kubectl get roles -A | grep -E "(domain-admin|smart-home-operator)" || echo "  (в domain namespaces)"

echo ""
echo -e "${BLUE}Созданные Namespaces:${NC}"
kubectl get namespaces | grep -E "(sales-domain|tenant-domain|finance-domain|data-domain|monitoring|logging)"

echo ""
echo -e "${YELLOW}[INFO] Манифесты сохранены в: $MANIFEST_DIR${NC}"

echo ""
echo -e "${BLUE}Следующие шаги:${NC}"
echo -e "  1. Проверьте созданные роли: ${GREEN}kubectl get clusterroles,roles -A${NC}"
echo -e "  2. Запустите скрипт привязки пользователей: ${GREEN}./3-bind-users-to-roles.sh${NC}"

echo ""
echo -e "${GREEN}[SUCCESS] Скрипт успешно завершен!${NC}"

# Детальный вывод одной из ролей для примера
echo ""
echo -e "${BLUE}Пример созданной роли (security-admin):${NC}"
kubectl describe clusterrole security-admin | head -30

