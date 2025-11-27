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

# Проверка наличия Minikube
if ! minikube status > /dev/null 2>&1; then
    echo -e "${RED}[ERROR] Minikube не запущен. Запустите: minikube start${NC}"
    exit 1
fi

echo -e "${GREEN}[OK] Minikube запущен${NC}"

# Создание директорий для хранения сертификатов
CERT_DIR="./k8s-users-certs"
mkdir -p "$CERT_DIR"

echo -e "${YELLOW}[INFO] Сертификаты будут сохранены в: $CERT_DIR${NC}"

# Получение CA сертификата и ключа из Minikube
MINIKUBE_HOME=$(minikube status -o json | grep Host | awk '{print $2}' | tr -d '",' || echo "$HOME/.minikube")
CA_CERT="$HOME/.minikube/ca.crt"
CA_KEY="$HOME/.minikube/ca.key"

if [[ ! -f "$CA_CERT" ]] || [[ ! -f "$CA_KEY" ]]; then
    echo -e "${RED}[ERROR] CA сертификаты не найдены в $HOME/.minikube/${NC}"
    exit 1
fi

echo -e "${GREEN}[OK] CA сертификаты найдены${NC}"

# Функция создания пользователя
create_user() {
    local USERNAME=$1
    local COMMON_NAME=$2
    local ORGANIZATION=$3  # Группа/роль для RBAC
    
    echo ""
    echo -e "${BLUE}----------------------------------------${NC}"
    echo -e "${BLUE}Создание пользователя: $USERNAME${NC}"
    echo -e "${BLUE}Common Name: $COMMON_NAME${NC}"
    echo -e "${BLUE}Organization: $ORGANIZATION${NC}"
    echo -e "${BLUE}----------------------------------------${NC}"
    
    USER_DIR="$CERT_DIR/$USERNAME"
    mkdir -p "$USER_DIR"
    
    # 1. Создание приватного ключа
    echo -e "${YELLOW}[1/5] Генерация приватного ключа...${NC}"
    openssl genrsa -out "$USER_DIR/$USERNAME.key" 2048 2>/dev/null
    echo -e "${GREEN}[OK] Приватный ключ создан: $USER_DIR/$USERNAME.key${NC}"
    
    # 2. Создание Certificate Signing Request (CSR)
    echo -e "${YELLOW}[2/5] Создание Certificate Signing Request...${NC}"
    openssl req -new \
        -key "$USER_DIR/$USERNAME.key" \
        -out "$USER_DIR/$USERNAME.csr" \
        -subj "/CN=$COMMON_NAME/O=$ORGANIZATION" 2>/dev/null
    echo -e "${GREEN}[OK] CSR создан: $USER_DIR/$USERNAME.csr${NC}"
    
    # 3. Подписание сертификата с помощью CA кластера
    echo -e "${YELLOW}[3/5] Подписание сертификата CA кластера...${NC}"
    openssl x509 -req \
        -in "$USER_DIR/$USERNAME.csr" \
        -CA "$CA_CERT" \
        -CAkey "$CA_KEY" \
        -CAcreateserial \
        -out "$USER_DIR/$USERNAME.crt" \
        -days 365 2>/dev/null
    echo -e "${GREEN}[OK] Сертификат подписан: $USER_DIR/$USERNAME.crt${NC}"
    
    # 4. Создание kubeconfig для пользователя
    echo -e "${YELLOW}[4/5] Создание kubeconfig файла...${NC}"
    
    # Получение адреса API сервера
    API_SERVER=$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}')
    
    # Создание kubeconfig
    cat > "$USER_DIR/$USERNAME-kubeconfig.yaml" <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: $(cat "$CA_CERT" | base64 | tr -d '\n')
    server: $API_SERVER
  name: propdevelopment-cluster
contexts:
- context:
    cluster: propdevelopment-cluster
    user: $USERNAME
    namespace: default
  name: $USERNAME-context
current-context: $USERNAME-context
users:
- name: $USERNAME
  user:
    client-certificate-data: $(cat "$USER_DIR/$USERNAME.crt" | base64 | tr -d '\n')
    client-key-data: $(cat "$USER_DIR/$USERNAME.key" | base64 | tr -d '\n')
EOF
    
    echo -e "${GREEN}[OK] Kubeconfig создан: $USER_DIR/$USERNAME-kubeconfig.yaml${NC}"
    
    # 5. Добавление пользователя в основной kubeconfig (опционально, для тестирования)
    echo -e "${YELLOW}[5/5] Добавление пользователя в kubectl config...${NC}"
    
    kubectl config set-credentials "$USERNAME" \
        --client-certificate="$USER_DIR/$USERNAME.crt" \
        --client-key="$USER_DIR/$USERNAME.key" \
        --embed-certs=true > /dev/null
    
    kubectl config set-context "$USERNAME-context" \
        --cluster=minikube \
        --user="$USERNAME" \
        --namespace=default > /dev/null
    
    echo -e "${GREEN}[OK] Пользователь добавлен в kubectl config${NC}"
    echo -e "${GREEN}[✓] Пользователь $USERNAME успешно создан!${NC}"
    
    # Информация для пользователя
    echo -e "${YELLOW}[INFO] Для использования этого пользователя:${NC}"
    echo -e "  export KUBECONFIG=$USER_DIR/$USERNAME-kubeconfig.yaml"
    echo -e "  или: kubectl --context=$USERNAME-context get pods"
}

# ============================================================================
# Создание пользователей
# ============================================================================

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Начало создания пользователей...${NC}"
echo -e "${BLUE}========================================${NC}"

# 1. Security Engineer (роль: security-admin)
create_user "ivan.security" "Ivan Petrov" "security-team"

# 2. DevOps Engineer (роль: devops-engineer)
create_user "anna.devops" "Anna Smirnova" "devops-team"

# 3. Developer Sales Domain (роль: developer в sales-domain)
create_user "dmitry.dev" "Dmitry Ivanov" "developers:sales"

# 4. Business Analyst (роль: viewer)
create_user "elena.viewer" "Elena Kozlova" "viewers"

# 5. Domain Admin Sales (роль: domain-admin-sales)
create_user "sergey.sales" "Sergey Volkov" "domain-admins:sales"

# 6. Domain Admin Tenant (роль: domain-admin-tenant)
create_user "maria.tenant" "Maria Orlova" "domain-admins:tenant"

# 7. Smart Home Operator (роль: smart-home-operator)
create_user "alexey.smarthome" "Alexey Sokolov" "smart-home-operators"

# 8. CTO - Emergency Access (роль: cluster-admin)
create_user "olga.cto" "Olga Kuznetsova (CTO)" "system:masters"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Все пользователи успешно созданы!${NC}"
echo -e "${GREEN}========================================${NC}"

# Сводная информация
echo ""
echo -e "${BLUE}Созданные пользователи:${NC}"
echo -e "${BLUE}----------------------------------------${NC}"
echo -e "1. ${YELLOW}ivan.security${NC}      - Security Engineer"
echo -e "2. ${YELLOW}anna.devops${NC}        - DevOps Engineer"
echo -e "3. ${YELLOW}dmitry.dev${NC}         - Developer (Sales)"
echo -e "4. ${YELLOW}elena.viewer${NC}       - Business Analyst"
echo -e "5. ${YELLOW}sergey.sales${NC}       - Domain Admin (Sales)"
echo -e "6. ${YELLOW}maria.tenant${NC}       - Domain Admin (Tenant)"
echo -e "7. ${YELLOW}alexey.smarthome${NC}   - Smart Home Operator"
echo -e "8. ${YELLOW}olga.cto${NC}           - CTO (Emergency Access)"

echo ""
echo -e "${YELLOW}[INFO] Сертификаты сохранены в: $CERT_DIR${NC}"
echo -e "${YELLOW}[INFO] Срок действия сертификатов: 365 дней${NC}"
echo ""
echo -e "${BLUE}Следующие шаги:${NC}"
echo -e "  1. Запустите скрипт создания ролей: ${GREEN}./2-create-roles.sh${NC}"
echo -e "  2. Запустите скрипт привязки пользователей к ролям: ${GREEN}./3-bind-users-to-roles.sh${NC}"
echo -e "  3. Проверьте доступ: ${GREEN}kubectl --context=ivan.security-context get pods${NC}"

echo ""
echo -e "${GREEN}[SUCCESS] Скрипт успешно завершен!${NC}"

# Проверка созданных пользователей
echo ""
echo -e "${BLUE}Проверка созданных контекстов:${NC}"
kubectl config get-contexts | grep -E "(NAME|security|devops|dev|viewer|sales|tenant|smarthome|cto)"

echo ""
echo -e "${YELLOW}[ВАЖНО] Пока пользователи созданы, но не имеют прав в кластере.${NC}"
echo -e "${YELLOW}Права будут назначены после выполнения скриптов 2 и 3.${NC}"

