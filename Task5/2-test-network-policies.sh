#!/bin/bash

##############################################################################
# Скрипт тестирования NetworkPolicies
# PropDevelopment - Network Isolation Testing
# 
# Назначение: Проверка работы сетевых политик
# Использование: ./2-test-network-policies.sh
# 
# Предусловия:
# - Развернуты 4 пода (1-deploy-services.sh)
# - Применены NetworkPolicies (non-admin-api-allow.yaml, admin-api-allow.yaml)
# 
# Тесты:
# 1. front-end → back-end-api (должен работать ✓)
# 2. front-end → admin-back-end-api (должен быть заблокирован ✗)
# 3. admin-front-end → admin-back-end-api (должен работать ✓)
# 4. admin-front-end → back-end-api (должен быть заблокирован ✗)
# 
##############################################################################

set -e  # Exit on error

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Тестирование NetworkPolicies${NC}"
echo -e "${BLUE}PropDevelopment Network Isolation${NC}"
echo -e "${BLUE}========================================${NC}"

NAMESPACE="propdevelopment-demo"

# Проверка Kubernetes
if ! kubectl cluster-info > /dev/null 2>&1; then
    echo -e "${RED}[ERROR] Kubernetes кластер недоступен${NC}"
    exit 1
fi

# Проверка существования подов
echo ""
echo -e "${YELLOW}[INFO] Проверка подов...${NC}"

required_pods=("front-end-app" "back-end-api-app" "admin-front-end-app" "admin-back-end-api-app")
all_pods_ready=true

for pod in "${required_pods[@]}"; do
    if kubectl get pod "$pod" -n "$NAMESPACE" &> /dev/null; then
        status=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
        if [ "$status" == "Running" ]; then
            echo -e "${GREEN}  ✓ $pod ($status)${NC}"
        else
            echo -e "${RED}  ✗ $pod ($status)${NC}"
            all_pods_ready=false
        fi
    else
        echo -e "${RED}  ✗ $pod (not found)${NC}"
        all_pods_ready=false
    fi
done

if [ "$all_pods_ready" == "false" ]; then
    echo -e "${RED}[ERROR] Не все поды готовы. Запустите: ./1-deploy-services.sh${NC}"
    exit 1
fi

# Проверка NetworkPolicies
echo ""
echo -e "${YELLOW}[INFO] Проверка NetworkPolicies...${NC}"

policies=$(kubectl get networkpolicies -n "$NAMESPACE" -o name 2>/dev/null | wc -l)
if [ "$policies" -eq 0 ]; then
    echo -e "${YELLOW}  [WARNING] NetworkPolicies не применены${NC}"
    echo -e "${YELLOW}  Тесты покажут доступность БЕЗ ограничений${NC}"
    echo -e "${YELLOW}  Примените политики: kubectl apply -f non-admin-api-allow.yaml${NC}"
else
    echo -e "${GREEN}  ✓ Найдено NetworkPolicies: $policies${NC}"
    kubectl get networkpolicies -n "$NAMESPACE"
fi

# ============================================================================
# ФУНКЦИЯ ТЕСТИРОВАНИЯ СВЯЗНОСТИ
# ============================================================================

test_connectivity() {
    local SOURCE_POD=$1
    local TARGET_POD=$2
    local EXPECTED_RESULT=$3  # "allow" или "deny"
    local TEST_DESCRIPTION=$4
    
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}ТЕСТ: $TEST_DESCRIPTION${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo -e "${YELLOW}Источник: $SOURCE_POD${NC}"
    echo -e "${YELLOW}Цель: $TARGET_POD${NC}"
    
    # Используем Service DNS вместо IP (для поддержки IPv6)
    TARGET_SERVICE="$TARGET_POD"
    
    echo -e "${BLUE}Целевой Service: $TARGET_SERVICE${NC}"
    echo -e "${YELLOW}Выполнение: curl -s --max-time 2 http://$TARGET_SERVICE${NC}"
    
    # Выполняем тест
    if kubectl exec "$SOURCE_POD" -n "$NAMESPACE" -- curl -s --max-time 2 "http://$TARGET_SERVICE" &> /dev/null; then
        # Успешное подключение
        if [ "$EXPECTED_RESULT" == "allow" ]; then
            echo -e "${GREEN}✓ PASS: Соединение установлено (ожидаемо)${NC}"
            return 0
        else
            echo -e "${RED}✗ FAIL: Соединение установлено (НЕ ожидаемо! NetworkPolicy не работает)${NC}"
            echo -e "${RED}   Проверьте, применены ли политики корректно${NC}"
            return 1
        fi
    else
        # Подключение заблокировано
        if [ "$EXPECTED_RESULT" == "deny" ]; then
            echo -e "${GREEN}✓ PASS: Соединение заблокировано (ожидаемо)${NC}"
            return 0
        else
            echo -e "${RED}✗ FAIL: Соединение заблокировано (НЕ ожидаемо! Проблема с подами или политикой)${NC}"
            return 1
        fi
    fi
}

# ============================================================================
# ТЕСТЫ
# ============================================================================

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Запуск тестов связности${NC}"
echo -e "${BLUE}========================================${NC}"

passed=0
failed=0

# Тест 1: front-end → back-end-api (РАЗРЕШЕНО)
if test_connectivity \
    "front-end-app" \
    "back-end-api-app" \
    "allow" \
    "Клиентский front-end → Клиентский API"; then
    ((passed++))
else
    ((failed++))
fi

# Тест 2: front-end → admin-back-end-api (ЗАПРЕЩЕНО)
if test_connectivity \
    "front-end-app" \
    "admin-back-end-api-app" \
    "deny" \
    "Клиентский front-end → Админский API (должен быть заблокирован)"; then
    ((passed++))
else
    ((failed++))
fi

# Тест 3: admin-front-end → admin-back-end-api (РАЗРЕШЕНО)
if test_connectivity \
    "admin-front-end-app" \
    "admin-back-end-api-app" \
    "allow" \
    "Админский front-end → Админский API"; then
    ((passed++))
else
    ((failed++))
fi

# Тест 4: admin-front-end → back-end-api (ЗАПРЕЩЕНО, опционально)
# Примечание: Этот тест зависит от вашей конфигурации
# Если admin-front-end должен иметь доступ к обычному API, измените на "allow"
if test_connectivity \
    "admin-front-end-app" \
    "back-end-api-app" \
    "deny" \
    "Админский front-end → Клиентский API (опционально заблокирован)"; then
    ((passed++))
else
    ((failed++))
fi

# Дополнительный тест: back-end-api → admin-back-end-api (ЗАПРЕЩЕНО)
if test_connectivity \
    "back-end-api-app" \
    "admin-back-end-api-app" \
    "deny" \
    "Клиентский API → Админский API (должен быть заблокирован для защиты)"; then
    ((passed++))
else
    ((failed++))
fi

# ============================================================================
# ТЕСТ С TEMPORARY POD (как в задании)
# ============================================================================

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}ДОПОЛНИТЕЛЬНЫЙ ТЕСТ: Temporary Alpine Pod${NC}"
echo -e "${CYAN}========================================${NC}"

echo -e "${YELLOW}[INFO] Создаем временный pod для тестирования...${NC}"
echo -e "${BLUE}Команда: kubectl run test-\$RANDOM --rm -i -t --image=alpine -- sh${NC}"

# Получаем IP back-end-api
BACKEND_IP=$(kubectl get pod back-end-api-app -n "$NAMESPACE" -o jsonpath='{.status.podIP}')

echo ""
echo -e "${YELLOW}Для ручного теста выполните:${NC}"
echo -e "${GREEN}kubectl run test-\$RANDOM --rm -i -t --image=alpine -- sh${NC}"
echo ""
echo -e "${YELLOW}Внутри контейнера:${NC}"
echo -e "${GREEN}/ # wget -qO- --timeout=2 http://back-end-api-app${NC}"
echo -e "${GREEN}/ # wget -qO- --timeout=2 http://admin-back-end-api-app${NC}"
echo ""
echo -e "${YELLOW}[INFO] Temporary pod (без меток) будет заблокирован NetworkPolicies${NC}"

# ============================================================================
# РЕЗУЛЬТАТЫ
# ============================================================================

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}РЕЗУЛЬТАТЫ ТЕСТИРОВАНИЯ${NC}"
echo -e "${BLUE}========================================${NC}"

total=$((passed + failed))
echo -e "Всего тестов: ${BLUE}$total${NC}"
echo -e "Пройдено: ${GREEN}$passed${NC}"
echo -e "Провалено: ${RED}$failed${NC}"

if [ "$failed" -eq 0 ]; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ ВСЕ ТЕСТЫ ПРОЙДЕНЫ УСПЕШНО!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}NetworkPolicies работают корректно${NC}"
    echo -e "${GREEN}Трафик изолирован согласно политикам${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}✗ НЕКОТОРЫЕ ТЕСТЫ ПРОВАЛЕНЫ${NC}"
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Проверьте конфигурацию NetworkPolicies${NC}"
    echo ""
    echo -e "${YELLOW}Возможные проблемы:${NC}"
    echo -e "  1. NetworkPolicies не применены: ${GREEN}kubectl apply -f non-admin-api-allow.yaml${NC}"
    echo -e "  2. CNI plugin не поддерживает NetworkPolicy (Minikube нужен Calico)"
    echo -e "  3. Неверная конфигурация label selectors"
    echo ""
    echo -e "${YELLOW}Отладка:${NC}"
    echo -e "  - Проверьте политики: ${GREEN}kubectl get networkpolicies -n $NAMESPACE${NC}"
    echo -e "  - Проверьте метки подов: ${GREEN}kubectl get pods -n $NAMESPACE --show-labels${NC}"
    echo -e "  - Детали политики: ${GREEN}kubectl describe networkpolicy <policy-name>${NC}"
    exit 1
fi

