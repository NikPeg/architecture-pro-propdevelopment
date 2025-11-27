#!/bin/bash

##############################################################################
# Скрипт проверки работы Pod Security Admission и OPA Gatekeeper
# PropDevelopment - Task7: Container Security Policy Audit
# 
# Назначение: Проверка блокировки небезопасных подов
# Использование: ./verify-admission.sh
# 
##############################################################################

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Проверка Pod Security Admission${NC}"
echo -e "${BLUE}PropDevelopment - Task7${NC}"
echo -e "${BLUE}========================================${NC}"

# Проверка kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}[ERROR] kubectl не установлен${NC}"
    exit 1
fi

echo -e "${GREEN}[OK] kubectl найден${NC}"

# ============================================================================
# STEP 1: Проверка namespace
# ============================================================================

echo ""
echo -e "${YELLOW}[1/7] Проверка namespace audit-zone${NC}"

if kubectl get namespace audit-zone &> /dev/null; then
    echo -e "${GREEN}[OK] Namespace audit-zone существует${NC}"
    
    # Проверка Pod Security labels
    echo -e "${BLUE}Проверка Pod Security labels:${NC}"
    kubectl get namespace audit-zone -o jsonpath='{.metadata.labels}' | jq '.'
else
    echo -e "${RED}[ERROR] Namespace audit-zone не найден${NC}"
    echo -e "${YELLOW}[INFO] Создайте namespace: kubectl apply -f 01-create-namespace.yaml${NC}"
    exit 1
fi

# ============================================================================
# STEP 2: Тест небезопасных манифестов
# ============================================================================

echo ""
echo -e "${YELLOW}[2/7] Тест: Privileged Pod (должен быть ЗАБЛОКИРОВАН)${NC}"

RESULT=$(kubectl apply -f ../insecure-manifests/01-privileged-pod.yaml 2>&1 || true)

if echo "$RESULT" | grep -i "violates PodSecurity\|forbidden\|denied"; then
    echo -e "${GREEN}[✓ PASS] Privileged pod заблокирован${NC}"
    echo -e "${BLUE}    Причина: ${RESULT}${NC}"
else
    echo -e "${RED}[✗ FAIL] Privileged pod НЕ заблокирован (ошибка политики!)${NC}"
    echo -e "${YELLOW}    Ответ: ${RESULT}${NC}"
fi

echo ""
echo -e "${YELLOW}[3/7] Тест: HostPath Pod (должен быть ЗАБЛОКИРОВАН)${NC}"

RESULT=$(kubectl apply -f ../insecure-manifests/02-hostpath-pod.yaml 2>&1 || true)

if echo "$RESULT" | grep -i "violates PodSecurity\|forbidden\|denied\|hostPath"; then
    echo -e "${GREEN}[✓ PASS] HostPath pod заблокирован${NC}"
    echo -e "${BLUE}    Причина: ${RESULT}${NC}"
else
    echo -e "${RED}[✗ FAIL] HostPath pod НЕ заблокирован (ошибка политики!)${NC}"
    echo -e "${YELLOW}    Ответ: ${RESULT}${NC}"
fi

echo ""
echo -e "${YELLOW}[4/7] Тест: Root User Pod (должен быть ЗАБЛОКИРОВАН)${NC}"

RESULT=$(kubectl apply -f ../insecure-manifests/03-root-user-pod.yaml 2>&1 || true)

if echo "$RESULT" | grep -i "violates PodSecurity\|forbidden\|denied\|runAsNonRoot"; then
    echo -e "${GREEN}[✓ PASS] Root user pod заблокирован${NC}"
    echo -e "${BLUE}    Причина: ${RESULT}${NC}"
else
    echo -e "${RED}[✗ FAIL] Root user pod НЕ заблокирован (ошибка политики!)${NC}"
    echo -e "${YELLOW}    Ответ: ${RESULT}${NC}"
fi

# ============================================================================
# STEP 3: Тест безопасных манифестов
# ============================================================================

echo ""
echo -e "${YELLOW}[5/7] Тест: Secure Pod #1 (должен быть РАЗРЕШЕН)${NC}"

RESULT=$(kubectl apply -f ../secure-manifests/01-secure.yaml 2>&1 || true)

if echo "$RESULT" | grep -i "created\|configured"; then
    echo -e "${GREEN}[✓ PASS] Secure pod #1 создан успешно${NC}"
else
    echo -e "${RED}[✗ FAIL] Secure pod #1 НЕ создан${NC}"
    echo -e "${YELLOW}    Ответ: ${RESULT}${NC}"
fi

echo ""
echo -e "${YELLOW}[6/7] Тест: Secure Pod #2 (должен быть РАЗРЕШЕН)${NC}"

RESULT=$(kubectl apply -f ../secure-manifests/02-secure.yaml 2>&1 || true)

if echo "$RESULT" | grep -i "created\|configured"; then
    echo -e "${GREEN}[✓ PASS] Secure pod #2 создан успешно${NC}"
else
    echo -e "${RED}[✗ FAIL] Secure pod #2 НЕ создан${NC}"
    echo -e "${YELLOW}    Ответ: ${RESULT}${NC}"
fi

echo ""
echo -e "${YELLOW}[7/7] Тест: Secure Pod #3 + Deployment (должны быть РАЗРЕШЕНЫ)${NC}"

RESULT=$(kubectl apply -f ../secure-manifests/03-secure.yaml 2>&1 || true)

if echo "$RESULT" | grep -i "created\|configured"; then
    echo -e "${GREEN}[✓ PASS] Secure pod #3 и deployment созданы успешно${NC}"
else
    echo -e "${RED}[✗ FAIL] Secure pod #3 НЕ создан${NC}"
    echo -e "${YELLOW}    Ответ: ${RESULT}${NC}"
fi

# ============================================================================
# STEP 4: Проверка созданных ресурсов
# ============================================================================

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Статус ресурсов в audit-zone${NC}"
echo -e "${BLUE}========================================${NC}"

kubectl get all -n audit-zone -o wide 2>/dev/null || echo -e "${YELLOW}[INFO] Нет ресурсов${NC}"

# ============================================================================
# STEP 5: Проверка Gatekeeper
# ============================================================================

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Проверка OPA Gatekeeper${NC}"
echo -e "${BLUE}========================================${NC}"

if kubectl get constrainttemplates &> /dev/null; then
    echo -e "${GREEN}[OK] Gatekeeper установлен${NC}"
    
    echo ""
    echo -e "${BLUE}ConstraintTemplates:${NC}"
    kubectl get constrainttemplates
    
    echo ""
    echo -e "${BLUE}Constraints:${NC}"
    kubectl get constraints -A 2>/dev/null || echo -e "${YELLOW}[INFO] Нет активных constraints${NC}"
    
else
    echo -e "${YELLOW}[INFO] Gatekeeper не установлен${NC}"
    echo -e "${YELLOW}[INFO] Для установки: kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/release-3.15/deploy/gatekeeper.yaml${NC}"
fi

# ============================================================================
# Итоги
# ============================================================================

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}ПРОВЕРКА ЗАВЕРШЕНА${NC}"
echo -e "${GREEN}========================================${NC}"

echo ""
echo -e "${BLUE}Следующие шаги:${NC}"
echo -e "  1. Проверьте, что небезопасные поды заблокированы"
echo -e "  2. Проверьте, что безопасные поды работают"
echo -e "  3. Установите Gatekeeper (если не установлен)"
echo -e "  4. Примените constraint templates и constraints"
echo -e "  5. Запустите validate-security.sh для детальной проверки"

echo ""
echo -e "${YELLOW}Для очистки:${NC}"
echo -e "  ${GREEN}kubectl delete namespace audit-zone${NC}"

echo ""

