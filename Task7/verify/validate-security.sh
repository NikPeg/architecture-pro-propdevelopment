#!/bin/bash

##############################################################################
# Скрипт валидации security конфигурации подов
# PropDevelopment - Task7: Container Security Policy Validation
# 
# Назначение: Детальная проверка security context всех подов
# Использование: ./validate-security.sh [namespace]
# 
##############################################################################

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

NAMESPACE="${1:-audit-zone}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Security Configuration Validator${NC}"
echo -e "${BLUE}PropDevelopment - Task7${NC}"
echo -e "${BLUE}========================================${NC}"

echo ""
echo -e "${YELLOW}[INFO] Анализируемый namespace: ${NAMESPACE}${NC}"

# Проверка kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}[ERROR] kubectl не установлен${NC}"
    exit 1
fi

# Проверка jq
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}[WARNING] jq не установлен, вывод будет упрощенным${NC}"
    HAS_JQ=false
else
    HAS_JQ=true
fi

# ============================================================================
# Функция проверки security context пода
# ============================================================================

check_pod_security() {
    local pod_name=$1
    local namespace=$2
    
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}Pod: ${pod_name}${NC}"
    echo -e "${CYAN}========================================${NC}"
    
    if [ "$HAS_JQ" = true ]; then
        # Получаем полный spec пода
        POD_JSON=$(kubectl get pod "$pod_name" -n "$namespace" -o json)
        
        # Pod-level security context
        echo -e "${BLUE}[1] Pod SecurityContext:${NC}"
        echo "$POD_JSON" | jq '.spec.securityContext' || echo "  Не установлен"
        
        # Проверка containers
        echo ""
        echo -e "${BLUE}[2] Containers Security:${NC}"
        
        CONTAINERS=$(echo "$POD_JSON" | jq -r '.spec.containers[].name')
        
        for container in $CONTAINERS; do
            echo ""
            echo -e "${YELLOW}  Container: ${container}${NC}"
            
            # SecurityContext контейнера
            SEC_CTX=$(echo "$POD_JSON" | jq ".spec.containers[] | select(.name==\"$container\") | .securityContext")
            
            echo -e "    ${CYAN}securityContext:${NC}"
            echo "$SEC_CTX" | jq '.' | sed 's/^/      /'
            
            # Проверка критичных параметров
            PRIVILEGED=$(echo "$SEC_CTX" | jq -r 'if has("privileged") then .privileged else "not set" end')
            RUN_AS_USER=$(echo "$SEC_CTX" | jq -r 'if has("runAsUser") then .runAsUser else "not set" end')
            RUN_AS_NON_ROOT=$(echo "$SEC_CTX" | jq -r 'if has("runAsNonRoot") then .runAsNonRoot else "not set" end')
            READ_ONLY_ROOT_FS=$(echo "$SEC_CTX" | jq -r 'if has("readOnlyRootFilesystem") then .readOnlyRootFilesystem else "not set" end')
            ALLOW_PRIV_ESC=$(echo "$SEC_CTX" | jq -r 'if has("allowPrivilegeEscalation") then .allowPrivilegeEscalation else "not set" end')
            
            echo ""
            echo -e "    ${CYAN}Security Check:${NC}"
            
            # Проверка privileged
            if [ "$PRIVILEGED" = "true" ]; then
                echo -e "      ${RED}✗ privileged: true (ОПАСНО!)${NC}"
            elif [ "$PRIVILEGED" = "false" ]; then
                echo -e "      ${GREEN}✓ privileged: false${NC}"
            else
                echo -e "      ${YELLOW}⚠ privileged: not set (default false)${NC}"
            fi
            
            # Проверка runAsUser
            if [ "$RUN_AS_USER" = "0" ]; then
                echo -e "      ${RED}✗ runAsUser: 0 (root, ОПАСНО!)${NC}"
            elif [ "$RUN_AS_USER" != "not set" ]; then
                echo -e "      ${GREEN}✓ runAsUser: $RUN_AS_USER (non-root)${NC}"
            else
                echo -e "      ${YELLOW}⚠ runAsUser: not set${NC}"
            fi
            
            # Проверка runAsNonRoot
            if [ "$RUN_AS_NON_ROOT" = "true" ]; then
                echo -e "      ${GREEN}✓ runAsNonRoot: true${NC}"
            elif [ "$RUN_AS_NON_ROOT" = "false" ]; then
                echo -e "      ${RED}✗ runAsNonRoot: false (ОПАСНО!)${NC}"
            else
                echo -e "      ${YELLOW}⚠ runAsNonRoot: not set${NC}"
            fi
            
            # Проверка readOnlyRootFilesystem
            if [ "$READ_ONLY_ROOT_FS" = "true" ]; then
                echo -e "      ${GREEN}✓ readOnlyRootFilesystem: true${NC}"
            elif [ "$READ_ONLY_ROOT_FS" = "false" ]; then
                echo -e "      ${RED}✗ readOnlyRootFilesystem: false (РЕКОМЕНДУЕТСЯ true)${NC}"
            else
                echo -e "      ${YELLOW}⚠ readOnlyRootFilesystem: not set (default false)${NC}"
            fi
            
            # Проверка allowPrivilegeEscalation
            if [ "$ALLOW_PRIV_ESC" = "false" ]; then
                echo -e "      ${GREEN}✓ allowPrivilegeEscalation: false${NC}"
            elif [ "$ALLOW_PRIV_ESC" = "true" ]; then
                echo -e "      ${RED}✗ allowPrivilegeEscalation: true (ОПАСНО!)${NC}"
            else
                echo -e "      ${YELLOW}⚠ allowPrivilegeEscalation: not set${NC}"
            fi
            
            # Capabilities
            CAPS=$(echo "$SEC_CTX" | jq -r '.capabilities')
            if [ "$CAPS" != "null" ]; then
                echo -e "      ${CYAN}capabilities:${NC}"
                echo "$CAPS" | jq '.' | sed 's/^/        /'
            fi
        done
        
        # Проверка volumes
        echo ""
        echo -e "${BLUE}[3] Volumes:${NC}"
        VOLUMES=$(echo "$POD_JSON" | jq '.spec.volumes')
        
        if [ "$VOLUMES" = "null" ] || [ "$VOLUMES" = "[]" ]; then
            echo "  Нет volumes"
        else
            echo "$VOLUMES" | jq -r '.[] | "  - \(.name): \(keys[] | select(. != "name"))"'
            
            # Проверка hostPath
            HOSTPATH_COUNT=$(echo "$VOLUMES" | jq '[.[] | select(.hostPath)] | length')
            if [ "$HOSTPATH_COUNT" -gt 0 ]; then
                echo -e "  ${RED}✗ Обнаружены hostPath volumes (ОПАСНО!)${NC}"
                echo "$VOLUMES" | jq '.[] | select(.hostPath) | "    - \(.name): \(.hostPath.path)"' -r
            else
                echo -e "  ${GREEN}✓ Нет hostPath volumes${NC}"
            fi
        fi
        
    else
        # Упрощенный вывод без jq
        echo -e "${YELLOW}[INFO] Установите jq для детального анализа: brew install jq${NC}"
        kubectl get pod "$pod_name" -n "$namespace" -o yaml | grep -A 20 "securityContext:"
    fi
}

# ============================================================================
# Основной цикл
# ============================================================================

echo ""
echo -e "${BLUE}Получение списка подов в namespace ${NAMESPACE}...${NC}"

PODS=$(kubectl get pods -n "$NAMESPACE" -o name 2>/dev/null | cut -d'/' -f2)

if [ -z "$PODS" ]; then
    echo -e "${YELLOW}[WARNING] Нет подов в namespace ${NAMESPACE}${NC}"
    exit 0
fi

POD_COUNT=$(echo "$PODS" | wc -l | tr -d ' ')
echo -e "${GREEN}[OK] Найдено подов: ${POD_COUNT}${NC}"

for pod in $PODS; do
    check_pod_security "$pod" "$NAMESPACE"
done

# ============================================================================
# Статистика
# ============================================================================

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}СТАТИСТИКА${NC}"
echo -e "${BLUE}========================================${NC}"

if [ "$HAS_JQ" = true ]; then
    ALL_PODS_JSON=$(kubectl get pods -n "$NAMESPACE" -o json)
    
    # Подсчет privileged контейнеров
    PRIVILEGED_COUNT=$(echo "$ALL_PODS_JSON" | jq '[.items[].spec.containers[] | select(.securityContext.privileged == true)] | length')
    echo -e "Privileged контейнеры: ${RED}${PRIVILEGED_COUNT}${NC}"
    
    # Подсчет root контейнеров
    ROOT_COUNT=$(echo "$ALL_PODS_JSON" | jq '[.items[].spec.containers[] | select(.securityContext.runAsUser == 0 or (.securityContext.runAsNonRoot == false))] | length')
    echo -e "Root контейнеры: ${RED}${ROOT_COUNT}${NC}"
    
    # Подсчет hostPath volumes
    HOSTPATH_COUNT=$(echo "$ALL_PODS_JSON" | jq '[.items[].spec.volumes[]? | select(.hostPath)] | length')
    echo -e "HostPath volumes: ${RED}${HOSTPATH_COUNT}${NC}"
    
    # Подсчет readOnlyRootFilesystem
    READONLY_COUNT=$(echo "$ALL_PODS_JSON" | jq '[.items[].spec.containers[] | select(.securityContext.readOnlyRootFilesystem == true)] | length')
    TOTAL_CONTAINERS=$(echo "$ALL_PODS_JSON" | jq '[.items[].spec.containers[]] | length')
    echo -e "ReadOnlyRootFS контейнеры: ${GREEN}${READONLY_COUNT}${NC} / ${TOTAL_CONTAINERS}"
fi

# ============================================================================
# Рекомендации
# ============================================================================

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}РЕКОМЕНДАЦИИ${NC}"
echo -e "${BLUE}========================================${NC}"

echo ""
echo -e "${CYAN}Минимальные требования безопасности (Pod Security Standard: restricted):${NC}"
echo -e "  1. ${GREEN}runAsNonRoot: true${NC} - запрет запуска от root"
echo -e "  2. ${GREEN}readOnlyRootFilesystem: true${NC} - read-only корневая ФС"
echo -e "  3. ${GREEN}allowPrivilegeEscalation: false${NC} - запрет эскалации"
echo -e "  4. ${GREEN}privileged: false${NC} - запрет privileged режима"
echo -e "  5. ${GREEN}capabilities: drop ALL${NC} - минимальные capabilities"
echo -e "  6. ${GREEN}Нет hostPath volumes${NC} - запрет доступа к хост ФС"
echo -e "  7. ${GREEN}seccompProfile: RuntimeDefault${NC} - seccomp профиль"

echo ""
echo -e "${YELLOW}Для исправления нарушений используйте примеры из secure-manifests/${NC}"

echo ""
echo -e "${GREEN}[SUCCESS] Валидация завершена${NC}"

echo ""

