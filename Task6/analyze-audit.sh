#!/bin/bash

##############################################################################
# Скрипт анализа Kubernetes Audit Log
# PropDevelopment - Security Incident Detection
# 
# Назначение: Фильтрация и анализ audit.log для выявления инцидентов
# Использование: ./analyze-audit.sh [путь_к_audit.log]
# 
# Предусловия:
# - Установлен jq (JSON processor)
# - Доступен audit.log файл
# 
# Вывод:
# - audit-extract.json - подозрительные события
# - Консольный отчет о найденных инцидентах
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

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Анализ Kubernetes Audit Log${NC}"
echo -e "${BLUE}PropDevelopment Security Audit${NC}"
echo -e "${BLUE}========================================${NC}"

# Путь к audit log
AUDIT_LOG="${1:-/var/log/audit.log}"

if [ ! -f "$AUDIT_LOG" ]; then
    echo -e "${YELLOW}[WARNING] Файл $AUDIT_LOG не найден${NC}"
    echo -e "${YELLOW}[INFO] Создание демонстрационного audit.log с симулированными событиями${NC}"
    AUDIT_LOG="./demo-audit.log"
    
    # Создаем демонстрационный audit.log
    cat > "$AUDIT_LOG" <<'DEMO_EOF'
{"kind":"Event","apiVersion":"audit.k8s.io/v1","level":"RequestResponse","auditID":"abc123","stage":"ResponseComplete","requestURI":"/api/v1/namespaces/kube-system/secrets/default-token-xyz","verb":"get","user":{"username":"system:serviceaccount:secure-ops:monitoring","groups":["system:serviceaccounts","system:serviceaccounts:secure-ops"]},"sourceIPs":["10.0.0.1"],"userAgent":"kubectl/v1.28.0","objectRef":{"resource":"secrets","namespace":"kube-system","name":"default-token-xyz","apiVersion":"v1"},"responseStatus":{"metadata":{},"code":403},"requestReceivedTimestamp":"2025-11-27T15:00:01.000000Z","stageTimestamp":"2025-11-27T15:00:01.100000Z"}
{"kind":"Event","apiVersion":"audit.k8s.io/v1","level":"RequestResponse","auditID":"def456","stage":"ResponseComplete","requestURI":"/api/v1/namespaces/secure-ops/pods","verb":"create","user":{"username":"kubernetes-admin","groups":["system:masters","system:authenticated"]},"sourceIPs":["10.0.0.2"],"userAgent":"kubectl/v1.28.0","objectRef":{"resource":"pods","namespace":"secure-ops","name":"privileged-pod","apiVersion":"v1"},"requestObject":{"spec":{"containers":[{"name":"pwn","image":"alpine","securityContext":{"privileged":true,"allowPrivilegeEscalation":true}}]}},"responseStatus":{"metadata":{},"code":201},"requestReceivedTimestamp":"2025-11-27T15:01:00.000000Z","stageTimestamp":"2025-11-27T15:01:00.200000Z"}
{"kind":"Event","apiVersion":"audit.k8s.io/v1","level":"RequestResponse","auditID":"ghi789","stage":"ResponseComplete","requestURI":"/api/v1/namespaces/kube-system/pods/coredns-abc123/exec","verb":"create","user":{"username":"john.attacker","groups":["system:authenticated"]},"sourceIPs":["10.0.0.3"],"userAgent":"kubectl/v1.28.0","objectRef":{"resource":"pods","namespace":"kube-system","name":"coredns-abc123","apiVersion":"v1","subresource":"exec"},"responseStatus":{"metadata":{},"code":200},"requestReceivedTimestamp":"2025-11-27T15:02:00.000000Z","stageTimestamp":"2025-11-27T15:02:00.300000Z"}
{"kind":"Event","apiVersion":"audit.k8s.io/v1","level":"RequestResponse","auditID":"jkl012","stage":"ResponseComplete","requestURI":"/apis/rbac.authorization.k8s.io/v1/namespaces/secure-ops/rolebindings","verb":"create","user":{"username":"suspicious.user","groups":["system:authenticated"]},"sourceIPs":["10.0.0.4"],"userAgent":"kubectl/v1.28.0","objectRef":{"resource":"rolebindings","namespace":"secure-ops","name":"escalate-binding","apiGroup":"rbac.authorization.k8s.io","apiVersion":"v1"},"requestObject":{"subjects":[{"kind":"ServiceAccount","name":"monitoring","namespace":"secure-ops"}],"roleRef":{"kind":"ClusterRole","name":"cluster-admin","apiGroup":"rbac.authorization.k8s.io"}},"responseStatus":{"metadata":{},"code":201},"requestReceivedTimestamp":"2025-11-27T15:03:00.000000Z","stageTimestamp":"2025-11-27T15:03:00.400000Z"}
{"kind":"Event","apiVersion":"audit.k8s.io/v1","level":"Metadata","auditID":"mno345","stage":"ResponseComplete","requestURI":"/api/v1/namespaces/secure-ops/configmaps","verb":"delete","user":{"username":"admin","groups":["system:masters"]},"sourceIPs":["10.0.0.5"],"userAgent":"kubectl/v1.28.0","objectRef":{"resource":"configmaps","namespace":"kube-system","name":"audit-policy","apiVersion":"v1"},"responseStatus":{"metadata":{},"code":404},"requestReceivedTimestamp":"2025-11-27T15:04:00.000000Z","stageTimestamp":"2025-11-27T15:04:00.500000Z"}
DEMO_EOF
    
    echo -e "${GREEN}[OK] Создан демонстрационный $AUDIT_LOG${NC}"
fi

echo ""
echo -e "${YELLOW}[INFO] Анализируемый файл: $AUDIT_LOG${NC}"

# Проверка jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}[ERROR] jq не установлен. Установите: brew install jq${NC}"
    exit 1
fi

echo -e "${GREEN}[OK] jq установлен${NC}"

# Выходной файл
OUTPUT_JSON="audit-extract.json"
OUTPUT_REPORT="analysis-temp.md"

echo -e "${YELLOW}[INFO] Результаты будут сохранены в: $OUTPUT_JSON${NC}"

# ============================================================================
# АНАЛИЗ 1: Доступ к секретам
# ============================================================================

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}[1/5] Анализ: Доступ к секретам${NC}"
echo -e "${CYAN}========================================${NC}"

SECRET_ACCESS=$(jq -c 'select(.objectRef.resource=="secrets" and (.verb=="get" or .verb=="list"))' "$AUDIT_LOG" 2>/dev/null || echo "")

if [ -n "$SECRET_ACCESS" ]; then
    COUNT=$(echo "$SECRET_ACCESS" | wc -l | tr -d ' ')
    echo -e "${RED}[!] Найдено событий доступа к секретам: $COUNT${NC}"
    echo "$SECRET_ACCESS" | jq -r '. | "  User: \(.user.username) | Namespace: \(.objectRef.namespace) | Secret: \(.objectRef.name) | Verb: \(.verb) | Status: \(.responseStatus.code)"' | head -10
else
    echo -e "${GREEN}[OK] Подозрительных событий не найдено${NC}"
fi

# ============================================================================
# АНАЛИЗ 2: Привилегированные поды
# ============================================================================

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}[2/5] Анализ: Привилегированные поды${NC}"
echo -e "${CYAN}========================================${NC}"

PRIVILEGED_PODS=$(jq -c 'select(.objectRef.resource=="pods" and .verb=="create" and (.requestObject.spec.containers[]?.securityContext.privileged==true or .requestObject.spec.hostNetwork==true or .requestObject.spec.hostPID==true))' "$AUDIT_LOG" 2>/dev/null || echo "")

if [ -n "$PRIVILEGED_PODS" ]; then
    COUNT=$(echo "$PRIVILEGED_PODS" | wc -l | tr -d ' ')
    echo -e "${RED}[!] Найдено привилегированных подов: $COUNT${NC}"
    echo "$PRIVILEGED_PODS" | jq -r '. | "  User: \(.user.username) | Pod: \(.objectRef.name) | Namespace: \(.objectRef.namespace) | Status: \(.responseStatus.code)"' | head -10
else
    echo -e "${GREEN}[OK] Привилегированных подов не найдено${NC}"
fi

# ============================================================================
# АНАЛИЗ 3: kubectl exec
# ============================================================================

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}[3/5] Анализ: kubectl exec${NC}"
echo -e "${CYAN}========================================${NC}"

EXEC_EVENTS=$(jq -c 'select(.verb=="create" and .objectRef.subresource=="exec")' "$AUDIT_LOG" 2>/dev/null || echo "")

if [ -n "$EXEC_EVENTS" ]; then
    COUNT=$(echo "$EXEC_EVENTS" | wc -l | tr -d ' ')
    echo -e "${RED}[!] Найдено kubectl exec событий: $COUNT${NC}"
    echo "$EXEC_EVENTS" | jq -r '. | "  User: \(.user.username) | Pod: \(.objectRef.name) | Namespace: \(.objectRef.namespace) | Status: \(.responseStatus.code)"' | head -10
else
    echo -e "${GREEN}[OK] kubectl exec событий не найдено${NC}"
fi

# ============================================================================
# АНАЛИЗ 4: Операции с RBAC
# ============================================================================

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}[4/5] Анализ: Изменения RBAC${NC}"
echo -e "${CYAN}========================================${NC}"

RBAC_CHANGES=$(jq -c 'select(.objectRef.resource=="rolebindings" or .objectRef.resource=="clusterrolebindings" and (.verb=="create" or .verb=="update" or .verb=="patch" or .verb=="delete"))' "$AUDIT_LOG" 2>/dev/null || echo "")

if [ -n "$RBAC_CHANGES" ]; then
    COUNT=$(echo "$RBAC_CHANGES" | wc -l | tr -d ' ')
    echo -e "${RED}[!] Найдено изменений RBAC: $COUNT${NC}"
    echo "$RBAC_CHANGES" | jq -r '. | "  User: \(.user.username) | Resource: \(.objectRef.resource) | Name: \(.objectRef.name) | Verb: \(.verb) | Status: \(.responseStatus.code)"' | head -10
    
    # Специальная проверка на cluster-admin
    CLUSTER_ADMIN=$(echo "$RBAC_CHANGES" | jq -c 'select(.requestObject.roleRef.name=="cluster-admin")' 2>/dev/null || echo "")
    if [ -n "$CLUSTER_ADMIN" ]; then
        echo -e "${RED}  [!!!] КРИТИЧНО: Обнаружена привязка к cluster-admin!${NC}"
        echo "$CLUSTER_ADMIN" | jq -r '. | "    Subject: \(.requestObject.subjects[0].kind)/\(.requestObject.subjects[0].name) → cluster-admin"'
    fi
else
    echo -e "${GREEN}[OK] Изменений RBAC не найдено${NC}"
fi

# ============================================================================
# АНАЛИЗ 5: Попытки удаления критичных ресурсов
# ============================================================================

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}[5/5] Анализ: Удаление критичных ресурсов${NC}"
echo -e "${CYAN}========================================${NC}"

DELETE_EVENTS=$(jq -c 'select(.verb=="delete" and (.objectRef.resource=="namespaces" or .objectRef.resource=="persistentvolumes" or (.requestURI | contains("audit-policy")) or (.objectRef.name | contains("audit-policy"))))' "$AUDIT_LOG" 2>/dev/null || echo "")

if [ -n "$DELETE_EVENTS" ]; then
    COUNT=$(echo "$DELETE_EVENTS" | wc -l | tr -d ' ')
    echo -e "${RED}[!] Найдено попыток удаления критичных ресурсов: $COUNT${NC}"
    echo "$DELETE_EVENTS" | jq -r '. | "  User: \(.user.username) | Resource: \(.objectRef.resource) | Name: \(.objectRef.name // .requestURI) | Status: \(.responseStatus.code)"' | head -10
else
    echo -e "${GREEN}[OK] Попыток удаления не найдено${NC}"
fi

# ============================================================================
# СОЗДАНИЕ ВЫЖИМКИ (audit-extract.json)
# ============================================================================

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Создание выжимки подозрительных событий${NC}"
echo -e "${BLUE}========================================${NC}"

# Объединяем все подозрительные события
cat > "$OUTPUT_JSON" <<'EOF'
{
  "audit_summary": {
    "analyzed_file": "",
    "analysis_timestamp": "",
    "total_suspicious_events": 0,
    "severity_breakdown": {
      "critical": 0,
      "high": 0,
      "medium": 0
    }
  },
  "incidents": {
    "secret_access": [],
    "privileged_pods": [],
    "kubectl_exec": [],
    "rbac_changes": [],
    "resource_deletion": []
  }
}
EOF

# Заполняем metadata
jq --arg file "$AUDIT_LOG" --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.audit_summary.analyzed_file = $file | .audit_summary.analysis_timestamp = $timestamp' \
    "$OUTPUT_JSON" > "${OUTPUT_JSON}.tmp" && mv "${OUTPUT_JSON}.tmp" "$OUTPUT_JSON"

# Добавляем события доступа к секретам
if [ -n "$SECRET_ACCESS" ]; then
    SECRETS_ARRAY=$(echo "$SECRET_ACCESS" | jq -s '.')
    jq --argjson secrets "$SECRETS_ARRAY" '.incidents.secret_access = $secrets' \
        "$OUTPUT_JSON" > "${OUTPUT_JSON}.tmp" && mv "${OUTPUT_JSON}.tmp" "$OUTPUT_JSON"
fi

# Добавляем привилегированные поды
if [ -n "$PRIVILEGED_PODS" ]; then
    PRIV_ARRAY=$(echo "$PRIVILEGED_PODS" | jq -s '.')
    jq --argjson priv "$PRIV_ARRAY" '.incidents.privileged_pods = $priv' \
        "$OUTPUT_JSON" > "${OUTPUT_JSON}.tmp" && mv "${OUTPUT_JSON}.tmp" "$OUTPUT_JSON"
fi

# Добавляем exec события
if [ -n "$EXEC_EVENTS" ]; then
    EXEC_ARRAY=$(echo "$EXEC_EVENTS" | jq -s '.')
    jq --argjson exec "$EXEC_ARRAY" '.incidents.kubectl_exec = $exec' \
        "$OUTPUT_JSON" > "${OUTPUT_JSON}.tmp" && mv "${OUTPUT_JSON}.tmp" "$OUTPUT_JSON"
fi

# Добавляем RBAC изменения
if [ -n "$RBAC_CHANGES" ]; then
    RBAC_ARRAY=$(echo "$RBAC_CHANGES" | jq -s '.')
    jq --argjson rbac "$RBAC_ARRAY" '.incidents.rbac_changes = $rbac' \
        "$OUTPUT_JSON" > "${OUTPUT_JSON}.tmp" && mv "${OUTPUT_JSON}.tmp" "$OUTPUT_JSON"
fi

# Добавляем удаления
if [ -n "$DELETE_EVENTS" ]; then
    DELETE_ARRAY=$(echo "$DELETE_EVENTS" | jq -s '.')
    jq --argjson del "$DELETE_ARRAY" '.incidents.resource_deletion = $del' \
        "$OUTPUT_JSON" > "${OUTPUT_JSON}.tmp" && mv "${OUTPUT_JSON}.tmp" "$OUTPUT_JSON"
fi

# Подсчет общего количества
TOTAL_EVENTS=$(jq '[.incidents | to_entries[] | .value | length] | add' "$OUTPUT_JSON" 2>/dev/null || echo "0")
jq --argjson total "$TOTAL_EVENTS" '.audit_summary.total_suspicious_events = $total' \
    "$OUTPUT_JSON" > "${OUTPUT_JSON}.tmp" && mv "${OUTPUT_JSON}.tmp" "$OUTPUT_JSON"

echo -e "${GREEN}[OK] Выжимка сохранена: $OUTPUT_JSON${NC}"

# ============================================================================
# СТАТИСТИКА
# ============================================================================

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}СТАТИСТИКА${NC}"
echo -e "${BLUE}========================================${NC}"

SECRET_COUNT=$(echo "$SECRET_ACCESS" | wc -l | tr -d ' ')
PRIV_COUNT=$(echo "$PRIVILEGED_PODS" | wc -l | tr -d ' ')
EXEC_COUNT=$(echo "$EXEC_EVENTS" | wc -l | tr -d ' ')
RBAC_COUNT=$(echo "$RBAC_CHANGES" | wc -l | tr -d ' ')
DELETE_COUNT=$(echo "$DELETE_EVENTS" | wc -l | tr -d ' ')

echo -e "Доступ к секретам:              ${RED}$SECRET_COUNT${NC} событий"
echo -e "Привилегированные поды:         ${RED}$PRIV_COUNT${NC} событий"
echo -e "kubectl exec:                   ${RED}$EXEC_COUNT${NC} событий"
echo -e "Изменения RBAC:                 ${RED}$RBAC_COUNT${NC} событий"
echo -e "Удаление критичных ресурсов:    ${RED}$DELETE_COUNT${NC} событий"
echo ""
echo -e "ВСЕГО подозрительных событий:   ${RED}$TOTAL_EVENTS${NC}"

# ============================================================================
# РЕКОМЕНДАЦИИ
# ============================================================================

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}РЕКОМЕНДАЦИИ${NC}"
echo -e "${BLUE}========================================${NC}"

if [ "$TOTAL_EVENTS" -gt 0 ]; then
    echo -e "${RED}[!] Обнаружены подозрительные события!${NC}"
    echo ""
    echo -e "${YELLOW}Немедленные действия:${NC}"
    echo -e "  1. Проверьте все события в $OUTPUT_JSON"
    echo -e "  2. Свяжитесь с пользователями для подтверждения действий"
    echo -e "  3. Отзовите подозрительные RoleBindings:"
    echo -e "     ${GREEN}kubectl delete rolebinding escalate-binding -n secure-ops${NC}"
    echo -e "  4. Удалите привилегированные поды:"
    echo -e "     ${GREEN}kubectl delete pod privileged-pod -n secure-ops${NC}"
    echo -e "  5. Проверьте, кто имеет доступ к секретам:"
    echo -e "     ${GREEN}kubectl get rolebindings,clusterrolebindings -A | grep secrets${NC}"
    
    if [ -n "$CLUSTER_ADMIN" ]; then
        echo ""
        echo -e "${RED}[!!!] КРИТИЧНО: Обнаружена эскалация к cluster-admin!${NC}"
        echo -e "${RED}Требуется немедленное расследование и отзыв прав${NC}"
    fi
else
    echo -e "${GREEN}[OK] Подозрительных событий не обнаружено${NC}"
fi

# ============================================================================
# ИТОГИ
# ============================================================================

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}АНАЛИЗ ЗАВЕРШЕН${NC}"
echo -e "${GREEN}========================================${NC}"

echo ""
echo -e "${BLUE}Созданные файлы:${NC}"
echo -e "  - ${YELLOW}$OUTPUT_JSON${NC} - выжимка подозрительных событий (JSON)"
echo -e "  - ${YELLOW}analysis.md${NC} - детальный отчет (создайте вручную на основе этого вывода)"

echo ""
echo -e "${BLUE}Для детального анализа используйте jq:${NC}"
echo -e "  ${GREEN}jq '.incidents.secret_access' $OUTPUT_JSON${NC}"
echo -e "  ${GREEN}jq '.incidents.privileged_pods' $OUTPUT_JSON${NC}"
echo -e "  ${GREEN}jq '.incidents.rbac_changes' $OUTPUT_JSON${NC}"

echo ""
echo -e "${YELLOW}Следующие шаги:${NC}"
echo -e "  1. Просмотрите выжимку: ${GREEN}jq . $OUTPUT_JSON${NC}"
echo -e "  2. Создайте отчет analysis.md на основе findings"
echo -e "  3. Примите меры по устранению угроз"
echo -e "  4. Обновите RBAC политики (Task4)"

echo ""
echo -e "${GREEN}[SUCCESS] Скрипт анализа завершен${NC}"

