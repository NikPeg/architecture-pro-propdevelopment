#!/bin/bash

##############################################################################
# Скрипт развертывания сервисов для демонстрации NetworkPolicies
# PropDevelopment Kubernetes Network Isolation
# 
# Назначение: Развертывание 4 подов с разными ролями
# Использование: ./1-deploy-services.sh
# 
# Предусловия:
# - Запущен Minikube с поддержкой NetworkPolicies
# - kubectl настроен и имеет доступ к кластеру
# 
# Создаваемые сервисы:
# 1. front-end-app           (role=front-end) - UI для клиентов
# 2. back-end-api-app        (role=back-end-api) - API для клиентов
# 3. admin-front-end-app     (role=admin-front-end) - Admin UI
# 4. admin-back-end-api-app  (role=admin-back-end-api) - Admin API
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
echo -e "${BLUE}Развертывание сервисов PropDevelopment${NC}"
echo -e "${BLUE}Network Isolation Demo${NC}"
echo -e "${BLUE}========================================${NC}"

# Проверка Minikube
if ! minikube status > /dev/null 2>&1; then
    echo -e "${RED}[ERROR] Minikube не запущен${NC}"
    echo -e "${YELLOW}Запустите: minikube start --network-plugin=cni --cni=calico${NC}"
    exit 1
fi

echo -e "${GREEN}[OK] Minikube запущен${NC}"

# Проверка поддержки NetworkPolicy
echo -e "${YELLOW}[INFO] Проверка поддержки NetworkPolicies...${NC}"

# Для Minikube нужно убедиться, что установлен network plugin (Calico/Cilium)
CNI_PLUGIN=$(kubectl get nodes -o jsonpath='{.items[0].spec.podCIDR}' 2>/dev/null || echo "")
if [ -z "$CNI_PLUGIN" ]; then
    echo -e "${YELLOW}[WARNING] Возможно, NetworkPolicy plugin не установлен${NC}"
    echo -e "${YELLOW}Для Minikube: minikube start --cni=calico${NC}"
    echo -e "${YELLOW}Продолжаем, но NetworkPolicies могут не работать...${NC}"
else
    echo -e "${GREEN}[OK] CNI plugin настроен${NC}"
fi

# Создание namespace (опционально, используем default)
NAMESPACE="default"
echo -e "${YELLOW}[INFO] Используем namespace: $NAMESPACE${NC}"

# ============================================================================
# РАЗВЕРТЫВАНИЕ СЕРВИСОВ
# ============================================================================

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Развертывание подов и сервисов${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

deploy_service() {
    local APP_NAME=$1
    local ROLE=$2
    local DESCRIPTION=$3
    
    echo -e "${BLUE}[$(date +%H:%M:%S)] Развертывание: $APP_NAME${NC}"
    echo -e "${YELLOW}  Role: $ROLE${NC}"
    echo -e "${YELLOW}  Description: $DESCRIPTION${NC}"
    
    # Проверка существования
    if kubectl get pod "$APP_NAME" -n "$NAMESPACE" &> /dev/null; then
        echo -e "${YELLOW}  [INFO] Pod $APP_NAME уже существует, удаляем...${NC}"
        kubectl delete pod "$APP_NAME" -n "$NAMESPACE" --grace-period=0 --force &> /dev/null || true
        sleep 2
    fi
    
    # Создание пода с меткой и Service
    kubectl run "$APP_NAME" \
        --image=nginx \
        --labels="role=$ROLE,app=propdevelopment" \
        --expose \
        --port=80 \
        -n "$NAMESPACE" > /dev/null
    
    # Ожидание готовности
    echo -e "${YELLOW}  [WAIT] Ожидание готовности пода...${NC}"
    kubectl wait --for=condition=Ready pod/"$APP_NAME" -n "$NAMESPACE" --timeout=60s > /dev/null
    
    echo -e "${GREEN}  [OK] $APP_NAME готов${NC}"
    echo ""
}

# 1. Front-End (UI для клиентов PropDevelopment)
deploy_service \
    "front-end-app" \
    "front-end" \
    "Витрина продаж / Мобильное приложение для клиентов"

# 2. Back-End API (API для клиентов)
deploy_service \
    "back-end-api-app" \
    "back-end-api" \
    "API: client-mart-app, tenant-core-app, витрины"

# 3. Admin Front-End (UI для администраторов)
deploy_service \
    "admin-front-end-app" \
    "admin-front-end" \
    "Административная панель для управления системой"

# 4. Admin Back-End API (API для администраторов)
deploy_service \
    "admin-back-end-api-app" \
    "admin-back-end-api" \
    "Admin API: CRM, управление пользователями, настройки"

# ============================================================================
# ПРОВЕРКА РАЗВЕРТЫВАНИЯ
# ============================================================================

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Проверка развертывания${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo -e "${YELLOW}[INFO] Поды в namespace $NAMESPACE:${NC}"
kubectl get pods -n "$NAMESPACE" -l app=propdevelopment -o wide

echo ""
echo -e "${YELLOW}[INFO] Сервисы в namespace $NAMESPACE:${NC}"
kubectl get services -n "$NAMESPACE" -l app=propdevelopment

echo ""
echo -e "${YELLOW}[INFO] Детали подов с метками:${NC}"
kubectl get pods -n "$NAMESPACE" -l app=propdevelopment --show-labels

# ============================================================================
# ТЕСТИРОВАНИЕ СВЯЗНОСТИ (до применения NetworkPolicies)
# ============================================================================

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Тест связности (ДО NetworkPolicies)${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo -e "${YELLOW}[INFO] Сейчас все поды могут общаться друг с другом${NC}"
echo -e "${YELLOW}Проверим доступность back-end-api-app из front-end-app...${NC}"

# Получаем IP back-end-api
BACKEND_IP=$(kubectl get pod back-end-api-app -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
echo -e "${BLUE}  back-end-api-app IP: $BACKEND_IP${NC}"

# Тест из front-end-app
echo -e "${YELLOW}  Тестирование: front-end-app → back-end-api-app${NC}"
if kubectl exec front-end-app -n "$NAMESPACE" -- wget -qO- --timeout=2 "http://$BACKEND_IP" &> /dev/null; then
    echo -e "${GREEN}  ✓ Связь есть (ожидаемо, NetworkPolicies ещё не применены)${NC}"
else
    echo -e "${RED}  ✗ Связи нет (неожиданно, проверьте поды)${NC}"
fi

echo ""
echo -e "${YELLOW}Проверим доступность admin-back-end-api-app из front-end-app...${NC}"

# Получаем IP admin-back-end-api
ADMIN_BACKEND_IP=$(kubectl get pod admin-back-end-api-app -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
echo -e "${BLUE}  admin-back-end-api-app IP: $ADMIN_BACKEND_IP${NC}"

# Тест из front-end-app к admin API (НЕ должен работать после применения политик)
echo -e "${YELLOW}  Тестирование: front-end-app → admin-back-end-api-app${NC}"
if kubectl exec front-end-app -n "$NAMESPACE" -- wget -qO- --timeout=2 "http://$ADMIN_BACKEND_IP" &> /dev/null; then
    echo -e "${GREEN}  ✓ Связь есть (сейчас разрешена, после политик будет запрещена)${NC}"
else
    echo -e "${RED}  ✗ Связи нет${NC}"
fi

# ============================================================================
# СОХРАНЕНИЕ IP АДРЕСОВ
# ============================================================================

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Информация о сервисах${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

cat > service-ips.txt <<EOF
# IP адреса подов PropDevelopment
# Создано: $(date)

FRONT_END_IP=$(kubectl get pod front-end-app -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
BACK_END_API_IP=$(kubectl get pod back-end-api-app -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
ADMIN_FRONT_END_IP=$(kubectl get pod admin-front-end-app -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
ADMIN_BACK_END_API_IP=$(kubectl get pod admin-back-end-api-app -n "$NAMESPACE" -o jsonpath='{.status.podIP}')

# Service DNS names
FRONT_END_DNS=front-end-app.$NAMESPACE.svc.cluster.local
BACK_END_API_DNS=back-end-api-app.$NAMESPACE.svc.cluster.local
ADMIN_FRONT_END_DNS=admin-front-end-app.$NAMESPACE.svc.cluster.local
ADMIN_BACK_END_API_DNS=admin-back-end-api-app.$NAMESPACE.svc.cluster.local
EOF

echo -e "${GREEN}[OK] IP адреса сохранены в service-ips.txt${NC}"

cat service-ips.txt

# ============================================================================
# ИТОГИ
# ============================================================================

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Все сервисы успешно развернуты!${NC}"
echo -e "${GREEN}========================================${NC}"

echo ""
echo -e "${BLUE}Развернутые сервисы:${NC}"
echo -e "${BLUE}----------------------------------------${NC}"
echo -e "1. ${YELLOW}front-end-app${NC}           (role=front-end)"
echo -e "2. ${YELLOW}back-end-api-app${NC}        (role=back-end-api)"
echo -e "3. ${YELLOW}admin-front-end-app${NC}     (role=admin-front-end)"
echo -e "4. ${YELLOW}admin-back-end-api-app${NC}  (role=admin-back-end-api)"

echo ""
echo -e "${BLUE}Архитектура (PropDevelopment):${NC}"
echo -e "${BLUE}----------------------------------------${NC}"
echo ""
echo -e "  ${GREEN}Клиенты (Собственники)${NC}"
echo -e "          ↓"
echo -e "  ${YELLOW}front-end-app${NC} ←→ ${YELLOW}back-end-api-app${NC}"
echo -e "  (Витрина/Mobile)    (API: client-mart, tenant-core)"
echo ""
echo -e "  ${GREEN}Администраторы (Менеджеры, Охрана)${NC}"
echo -e "          ↓"
echo -e "  ${YELLOW}admin-front-end-app${NC} ←→ ${YELLOW}admin-back-end-api-app${NC}"
echo -e "  (Admin Panel)        (CRM, User Management)"

echo ""
echo -e "${YELLOW}[ВАЖНО] Сейчас все поды могут общаться друг с другом${NC}"
echo -e "${YELLOW}NetworkPolicies ещё не применены${NC}"

echo ""
echo -e "${BLUE}Следующие шаги:${NC}"
echo -e "  1. Примените NetworkPolicies: ${GREEN}kubectl apply -f non-admin-api-allow.yaml${NC}"
echo -e "  2. Примените админские политики: ${GREEN}kubectl apply -f admin-api-allow.yaml${NC}"
echo -e "  3. Опционально (default deny): ${GREEN}kubectl apply -f default-deny-all.yaml${NC}"
echo -e "  4. Протестируйте политики: ${GREEN}./2-test-network-policies.sh${NC}"

echo ""
echo -e "${GREEN}[SUCCESS] Развертывание завершено!${NC}"

