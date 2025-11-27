#!/bin/bash

##############################################################################
# Скрипт симуляции инцидентов безопасности
# PropDevelopment - Security Audit Testing
# 
# Назначение: Генерация подозрительных событий для тестирования аудита
# Использование: ./simulate-incident.sh
# 
# ВНИМАНИЕ: Этот скрипт создает потенциально опасные ресурсы!
# Использовать ТОЛЬКО в тестовом окружении!
# 
##############################################################################

set -e  # Exit on error

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${RED}========================================${NC}"
echo -e "${RED}СИМУЛЯЦИЯ ИНЦИДЕНТОВ БЕЗОПАСНОСТИ${NC}"
echo -e "${RED}PropDevelopment Security Audit Test${NC}"
echo -e "${RED}========================================${NC}"

echo ""
echo -e "${YELLOW}ВНИМАНИЕ: Этот скрипт создает потенциально опасные ресурсы!${NC}"
echo -e "${YELLOW}Используйте ТОЛЬКО в тестовом окружении!${NC}"
echo ""

read -p "Продолжить? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Отменено пользователем"
    exit 0
fi

# Namespace для тестирования
TEST_NAMESPACE="secure-ops"

echo ""
echo -e "${BLUE}[INFO] Создание тестового namespace: $TEST_NAMESPACE${NC}"

# Создаем namespace
if ! kubectl get namespace "$TEST_NAMESPACE" &> /dev/null; then
    kubectl create ns "$TEST_NAMESPACE"
    echo -e "${GREEN}[OK] Namespace создан${NC}"
else
    echo -e "${YELLOW}[INFO] Namespace уже существует${NC}"
fi

# Переключаемся на namespace
kubectl config set-context --current --namespace="$TEST_NAMESPACE"

# ============================================================================
# ИНЦИДЕНТ 1: Попытка доступа к секретам от ServiceAccount
# ============================================================================

echo ""
echo -e "${RED}========================================${NC}"
echo -e "${RED}ИНЦИДЕНТ 1: Доступ к секретам${NC}"
echo -e "${RED}========================================${NC}"

echo -e "${BLUE}[1/5] Создание ServiceAccount 'monitoring'${NC}"
kubectl create sa monitoring 2>/dev/null || echo -e "${YELLOW}[INFO] SA уже существует${NC}"

echo -e "${BLUE}[1/5] Создание пода 'attacker-pod'${NC}"
kubectl run attacker-pod --image=alpine --command -- sleep 3600 2>/dev/null || echo -e "${YELLOW}[INFO] Pod уже существует${NC}"

echo -e "${BLUE}[1/5] Проверка прав на чтение секретов${NC}"
kubectl auth can-i get secrets --as=system:serviceaccount:${TEST_NAMESPACE}:monitoring || true

echo -e "${BLUE}[1/5] Попытка прочитать секрет из kube-system (SUSPICIOUS!)${NC}"
# Попытка получить токен из kube-system
SECRET_NAME=$(kubectl get secrets -n kube-system | grep default-token | head -n1 | awk '{print $1}' || echo "")
if [ -n "$SECRET_NAME" ]; then
    kubectl get secret -n kube-system "$SECRET_NAME" \
        --as=system:serviceaccount:${TEST_NAMESPACE}:monitoring \
        2>&1 || echo -e "${YELLOW}[INFO] Доступ запрещен (ожидаемо)${NC}"
else
    echo -e "${YELLOW}[INFO] Секрет не найден${NC}"
fi

sleep 1

# ============================================================================
# ИНЦИДЕНТ 2: Создание привилегированного пода
# ============================================================================

echo ""
echo -e "${RED}========================================${NC}"
echo -e "${RED}ИНЦИДЕНТ 2: Privileged Pod${NC}"
echo -e "${RED}========================================${NC}"

echo -e "${BLUE}[2/5] Создание привилегированного пода (DANGEROUS!)${NC}"

cat <<EOF | kubectl apply -f - 2>&1 || echo -e "${YELLOW}[INFO] Не удалось создать (возможно PodSecurityPolicy блокирует)${NC}"
apiVersion: v1
kind: Pod
metadata:
  name: privileged-pod
  namespace: ${TEST_NAMESPACE}
  labels:
    app: suspicious
    security-risk: high
spec:
  containers:
  - name: pwn
    image: alpine
    command: ["sleep", "3600"]
    securityContext:
      privileged: true
      allowPrivilegeEscalation: true
      runAsUser: 0
  restartPolicy: Never
EOF

sleep 1

# ============================================================================
# ИНЦИДЕНТ 3: Использование kubectl exec в чужом поде
# ============================================================================

echo ""
echo -e "${RED}========================================${NC}"
echo -e "${RED}ИНЦИДЕНТ 3: kubectl exec в чужой под${NC}"
echo -e "${RED}========================================${NC}"

echo -e "${BLUE}[3/5] Попытка выполнить команду в поде kube-system (SUSPICIOUS!)${NC}"

# Находим под coredns в kube-system
COREDNS_POD=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o name 2>/dev/null | head -n1 | cut -d'/' -f2 || echo "")

if [ -n "$COREDNS_POD" ]; then
    echo -e "${YELLOW}[INFO] Попытка exec в $COREDNS_POD${NC}"
    kubectl exec -n kube-system "$COREDNS_POD" -- cat /etc/resolv.conf 2>&1 | head -5 || true
else
    echo -e "${YELLOW}[INFO] CoreDNS pod не найден, попробуем другой${NC}"
    # Попробуем любой под в kube-system
    ANY_POD=$(kubectl get pods -n kube-system -o name 2>/dev/null | head -n1 | cut -d'/' -f2 || echo "")
    if [ -n "$ANY_POD" ]; then
        kubectl exec -n kube-system "$ANY_POD" -- echo "test" 2>&1 | head -5 || true
    fi
fi

sleep 1

# ============================================================================
# ИНЦИДЕНТ 4: Попытка удаления audit-policy
# ============================================================================

echo ""
echo -e "${RED}========================================${NC}"
echo -e "${RED}ИНЦИДЕНТ 4: Удаление audit-policy${NC}"
echo -e "${RED}========================================${NC}"

echo -e "${BLUE}[4/5] Попытка удалить audit-policy (CRITICAL!)${NC}"

# Это должно fail, но попытка будет залогирована
kubectl delete -f /etc/kubernetes/audit-policy.yaml --as=admin 2>&1 || echo -e "${YELLOW}[INFO] Не удалось удалить (ожидаемо, файл не существует как ресурс)${NC}"

# Попытка удалить ConfigMap с audit policy (если существует)
kubectl delete configmap audit-policy -n kube-system 2>&1 || echo -e "${YELLOW}[INFO] ConfigMap не найден${NC}"

sleep 1

# ============================================================================
# ИНЦИДЕНТ 5: Создание RoleBinding с правами cluster-admin
# ============================================================================

echo ""
echo -e "${RED}========================================${NC}"
echo -e "${RED}ИНЦИДЕНТ 5: Privilege Escalation${NC}"
echo -e "${RED}========================================${NC}"

echo -e "${BLUE}[5/5] Создание RoleBinding с cluster-admin (CRITICAL!)${NC}"

cat <<EOF | kubectl apply -f - 2>&1
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: escalate-binding
  namespace: ${TEST_NAMESPACE}
  labels:
    security-risk: critical
    created-by: simulate-incident
subjects:
- kind: ServiceAccount
  name: monitoring
  namespace: ${TEST_NAMESPACE}
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF

echo -e "${RED}[WARNING] ServiceAccount 'monitoring' теперь имеет права cluster-admin!${NC}"

sleep 1

# ============================================================================
# ДОПОЛНИТЕЛЬНЫЕ ПОДОЗРИТЕЛЬНЫЕ ДЕЙСТВИЯ
# ============================================================================

echo ""
echo -e "${RED}========================================${NC}"
echo -e "${RED}ДОПОЛНИТЕЛЬНЫЕ ИНЦИДЕНТЫ${NC}"
echo -e "${RED}========================================${NC}"

# Попытка создать секрет с подозрительным именем
echo -e "${BLUE}[EXTRA] Создание подозрительного секрета${NC}"
kubectl create secret generic aws-credentials \
    --from-literal=access_key=AKIAIOSFODNN7EXAMPLE \
    --from-literal=secret_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY \
    2>/dev/null || echo -e "${YELLOW}[INFO] Секрет уже существует${NC}"

# Попытка создать под с host network
echo -e "${BLUE}[EXTRA] Создание пода с host network (DANGEROUS!)${NC}"
cat <<EOF | kubectl apply -f - 2>&1 || echo -e "${YELLOW}[INFO] Не удалось создать${NC}"
apiVersion: v1
kind: Pod
metadata:
  name: host-network-pod
  namespace: ${TEST_NAMESPACE}
spec:
  hostNetwork: true
  hostPID: true
  containers:
  - name: attacker
    image: alpine
    command: ["sleep", "3600"]
EOF

# Попытка создать NetworkPolicy, которая открывает все
echo -e "${BLUE}[EXTRA] Создание небезопасной NetworkPolicy${NC}"
cat <<EOF | kubectl apply -f - 2>&1 || echo -e "${YELLOW}[INFO] Не удалось создать${NC}"
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all
  namespace: ${TEST_NAMESPACE}
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - {}
  egress:
  - {}
EOF

# ============================================================================
# ИТОГИ
# ============================================================================

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}СИМУЛЯЦИЯ ЗАВЕРШЕНА${NC}"
echo -e "${GREEN}========================================${NC}"

echo ""
echo -e "${YELLOW}Созданные ресурсы:${NC}"
kubectl get all,sa,rolebinding,networkpolicy,secrets -n "$TEST_NAMESPACE" 2>/dev/null || true

echo ""
echo -e "${BLUE}Следующие шаги:${NC}"
echo -e "  1. Проверьте audit.log: ${GREEN}jq . /var/log/audit.log | less${NC}"
echo -e "  2. Запустите анализ: ${GREEN}./analyze-audit.sh${NC}"
echo -e "  3. Очистите тестовые ресурсы: ${GREEN}kubectl delete namespace $TEST_NAMESPACE${NC}"

echo ""
echo -e "${RED}ВНИМАНИЕ: Не забудьте удалить опасные ресурсы!${NC}"
echo -e "  ${GREEN}kubectl delete rolebinding escalate-binding -n $TEST_NAMESPACE${NC}"
echo -e "  ${GREEN}kubectl delete pod privileged-pod host-network-pod -n $TEST_NAMESPACE${NC}"

echo ""
echo -e "${YELLOW}Для просмотра событий в audit log:${NC}"
echo -e "  ${GREEN}kubectl get events -n $TEST_NAMESPACE --sort-by='.lastTimestamp'${NC}"

