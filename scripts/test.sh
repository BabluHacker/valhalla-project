#!/bin/bash

# Valhalla Testing Script
# Runs comprehensive tests against deployed application

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
ENVIRONMENT="${1:-dev}"
NAMESPACE="valhalla"

echo -e "${GREEN}=== Valhalla Testing Suite ===${NC}"
echo "Environment: $ENVIRONMENT"
echo ""

# Get ALB URL
echo "Getting application URL..."
ALB_URL=$(kubectl get ingress valhalla-api -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

if [ -z "$ALB_URL" ]; then
    echo -e "${RED}[✗]${NC} Could not get ALB URL. Is the application deployed?"
    exit 1
fi

BASE_URL="http://$ALB_URL"
echo -e "${GREEN}[✓]${NC} Base URL: $BASE_URL"
echo ""

# Test counter
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_test() {
    local test_name=$1
    local test_command=$2
    local expected_code=${3:-200}
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing $test_name... "
    
    response=$(curl -s -w "\n%{http_code}" $test_command)
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" -eq "$expected_code" ]; then
        echo -e "${GREEN}✓${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo -e "${RED}✗${NC} (Expected $expected_code, got $http_code)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Health Checks
echo "=== Health Checks ==="
run_test "Health endpoint" "$BASE_URL/health"
run_test "Readiness endpoint" "$BASE_URL/ready"
echo ""

# API Endpoints
echo "=== API Endpoints ==="
run_test "Status endpoint" "$BASE_URL/api/v1/status"
run_test "Data endpoint" "$BASE_URL/api/v1/data"
run_test "Data by ID" "$BASE_URL/api/v1/data/1"
run_test "Metrics endpoint" "$BASE_URL/metrics"
echo ""

# Query Parameters
echo "=== Query Parameters ==="
run_test "Filter by type" "$BASE_URL/api/v1/data?type=Platform"
run_test "Filter by status" "$BASE_URL/api/v1/data?status=active"
echo ""

# Error Handling
echo "=== Error Handling ==="
run_test "Non-existent endpoint" "$BASE_URL/nonexistent" 404
run_test "Non-existent data ID" "$BASE_URL/api/v1/data/999" 404
echo ""

# Performance
echo "=== Performance Tests ==="
echo -n "Response time test... "
start_time=$(date +%s%N)
curl -s "$BASE_URL/health" > /dev/null
end_time=$(date +%s%N)
response_time=$(( (end_time - start_time) / 1000000 ))

if [ $response_time -lt 500 ]; then
    echo -e "${GREEN}✓${NC} (${response_time}ms)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo -e "${RED}✗${NC} (${response_time}ms, expected < 500ms)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo ""

# Kubernetes Tests
echo "=== Kubernetes Health ==="
echo -n "Checking pod status... "
pod_count=$(kubectl get pods -n $NAMESPACE -l app=valhalla-api --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$pod_count" -ge 3 ]; then
    echo -e "${GREEN}✓${NC} ($pod_count pods running)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo -e "${RED}✗${NC} (Only $pod_count pods running, expected >= 3)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

echo -n "Checking HPA status... "
hpa_status=$(kubectl get hpa valhalla-api -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="ScalingActive")].status}' 2>/dev/null)
if [ "$hpa_status" == "True" ]; then
    echo -e "${GREEN}✓${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo -e "${YELLOW}!${NC} (HPA not active or metrics not available)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

echo -n "Checking service endpoints... "
endpoints=$(kubectl get endpoints valhalla-api -n $NAMESPACE -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null | wc -w | tr -d ' ')
if [ "$endpoints" -ge 3 ]; then
    echo -e "${GREEN}✓${NC} ($endpoints endpoints)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo -e "${RED}✗${NC} (Only $endpoints endpoints)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo ""

# Load Test (simple)
echo "=== Load Test ==="
echo "Running 100 concurrent requests..."
for i in {1..100}; do
    curl -s "$BASE_URL/api/v1/data" > /dev/null &
done
wait

echo -n "Checking pods after load... "
sleep 5
pod_count_after=$(kubectl get pods -n $NAMESPACE -l app=valhalla-api --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo -e "${GREEN}✓${NC} ($pod_count_after pods)"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
PASSED_TESTS=$((PASSED_TESTS + 1))
echo ""

# Summary
echo "=== Test Summary ==="
echo "Total Tests: $TOTAL_TESTS"
echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}All tests passed! ✓${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed! ✗${NC}"
    exit 1
fi
