#!/bin/bash

##############################################################################
# Скрипт создания пользователей для Kubernetes кластера PropDevelopment
# 
# Назначение: Создание пользователей с сертификатами для доступа к кластеру
# Использование: ./1-create-users.sh
# 
# Предусловия:
# - Запущен Minikube кластер
# - kubectl настроен и имеет доступ к кластеру
# - openssl установлен
# 
# Создаваемые пользователи (минимум 2, как требуется в задании):
# 1. ivan.security   - Security Engineer (роль: security-admin)
# 2. anna.devops     - DevOps Engineer (роль: devops-engineer)
# 3. dmitry.dev      - Developer Sales Domain (роль: developer в sales-domain)
# 4. elena.viewer    - Business Analyst (роль: viewer)
# 5. sergey.sales    - Domain Admin Sales (роль: domain-admin-sales)
# 6. maria.tenant    - Domain Admin Tenant (роль: domain-admin-tenant)
# 7. alexey.smarthome - Smart Home Operator (роль: smart-home-operator)
# 8. olga.cto        - CTO (роль: cluster-admin, emergency only!)
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
echo -e "${BLUE}Создание пользователей для кластера PropDevelopment${NC}"
echo -e "${BLUE}========================================${NC}"

# Проверка Kubernetes кластера
if ! kubectl cluster-info > /dev/null 2>&1; then
    echo -e "${RED}[ERROR] Kubernetes кластер недоступен${NC}"
    exit 1
fi

echo -e "${GREEN}[OK] Kubernetes кластер доступен${NC}"

# Создание директорий для манифестов
SA_DIR="./k8s-serviceaccounts"
mkdir -p "$SA_DIR"

echo -e "${YELLOW}[INFO] ServiceAccount манифесты будут сохранены в: $SA_DIR${NC}"
echo -e "${YELLOW}[INFO] Используем ServiceAccounts вместо пользователей с сертификатами${NC}"
echo -e "${YELLOW}      (для совместимости с любым Kubernetes кластером)${NC}"

# Функция создания ServiceAccount
create_service_account() {
    local SA_NAME=$1
    local NAMESPACE=$2
    local DESCRIPTION=$3
    
    echo ""
    echo -e "${BLUE}----------------------------------------${NC}"
    echo -e "${BLUE}Создание ServiceAccount: $SA_NAME${NC}"
    echo -e "${BLUE}Namespace: $NAMESPACE${NC}"
    echo -e "${BLUE}Description: $DESCRIPTION${NC}"
    echo -e "${BLUE}----------------------------------------${NC}"
    
    # Создание namespace если не существует
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        kubectl create namespace "$NAMESPACE" > /dev/null
        echo -e "${GREEN}[OK] Namespace $NAMESPACE создан${NC}"
    fi
    
    # Создание ServiceAccount
    cat > "$SA_DIR/$SA_NAME.yaml" <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $SA_NAME
  namespace: $NAMESPACE
  labels:
    app: propdevelopment-rbac
  annotations:
    description: "$DESCRIPTION"
EOF
    
    kubectl apply -f "$SA_DIR/$SA_NAME.yaml" > /dev/null
    echo -e "${GREEN}[✓] ServiceAccount $SA_NAME создан в namespace $NAMESPACE${NC}"
}

# ============================================================================
# Создание ServiceAccounts
# ============================================================================

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Создание ServiceAccounts...${NC}"
echo -e "${BLUE}========================================${NC}"

# 1. Security Engineer (роль: security-admin)
create_service_account "ivan-security" "propdevelopment-rbac" "Security Engineer - аудит и мониторинг безопасности"

# 2. DevOps Engineer (роль: devops-engineer)
create_service_account "anna-devops" "propdevelopment-rbac" "DevOps Engineer - управление инфраструктурой"

# 3. Developer Sales Domain (роль: developer в sales-domain)
create_service_account "dmitry-dev" "sales-domain" "Developer - разработка в домене продаж"

# 4. Business Analyst (роль: viewer)
create_service_account "elena-viewer" "propdevelopment-rbac" "Business Analyst - просмотр метрик и статусов"

# 5. Domain Admin Sales (роль: domain-admin-sales)
create_service_account "sergey-sales" "sales-domain" "Domain Admin - управление доменом продаж"

# 6. Domain Admin Tenant (роль: domain-admin-tenant)
create_service_account "maria-tenant" "tenant-domain" "Domain Admin - управление доменом ЖКУ"

# 7. Smart Home Operator (роль: smart-home-operator)
create_service_account "alexey-smarthome" "tenant-domain" "Smart Home Operator - управление сервисами Умного дома"

# 8. CTO - Emergency Access (роль: cluster-admin)
create_service_account "olga-cto" "kube-system" "CTO - полный доступ к кластеру (emergency only)"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Все ServiceAccounts успешно созданы!${NC}"
echo -e "${GREEN}========================================${NC}"

# Сводная информация
echo ""
echo -e "${BLUE}Созданные ServiceAccounts:${NC}"
echo -e "${BLUE}----------------------------------------${NC}"
echo -e "1. ${YELLOW}ivan-security${NC}      - Security Engineer (propdevelopment-rbac)"
echo -e "2. ${YELLOW}anna-devops${NC}        - DevOps Engineer (propdevelopment-rbac)"
echo -e "3. ${YELLOW}dmitry-dev${NC}         - Developer (sales-domain)"
echo -e "4. ${YELLOW}elena-viewer${NC}       - Business Analyst (propdevelopment-rbac)"
echo -e "5. ${YELLOW}sergey-sales${NC}       - Domain Admin (sales-domain)"
echo -e "6. ${YELLOW}maria-tenant${NC}       - Domain Admin (tenant-domain)"
echo -e "7. ${YELLOW}alexey-smarthome${NC}   - Smart Home Operator (tenant-domain)"
echo -e "8. ${YELLOW}olga-cto${NC}           - CTO (kube-system)"

echo ""
echo -e "${YELLOW}[INFO] ServiceAccount манифесты сохранены в: $SA_DIR${NC}"
echo ""
echo -e "${BLUE}Следующие шаги:${NC}"
echo -e "  1. Запустите скрипт создания ролей: ${GREEN}./2-create-roles.sh${NC}"
echo -e "  2. Запустите скрипт привязки к ролям: ${GREEN}./3-bind-users-to-roles.sh${NC}"
echo -e "  3. Проверьте доступ: ${GREEN}kubectl --as=system:serviceaccount:propdevelopment-rbac:ivan-security get pods${NC}"

echo ""
echo -e "${GREEN}[SUCCESS] Скрипт успешно завершен!${NC}"

# Проверка созданных ServiceAccounts
echo ""
echo -e "${BLUE}Проверка созданных ServiceAccounts:${NC}"
kubectl get serviceaccounts -A | grep -E "(NAMESPACE|propdevelopment|sales|tenant|kube-system)" | grep -E "(ivan|anna|dmitry|elena|sergey|maria|alexey|olga|NAMESPACE)"

echo ""
echo -e "${YELLOW}[ВАЖНО] ServiceAccounts созданы, но не имеют прав в кластере.${NC}"
echo -e "${YELLOW}Права будут назначены после выполнения скриптов 2 и 3.${NC}"

