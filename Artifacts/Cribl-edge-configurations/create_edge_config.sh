#!/bin/bash
AUTH_URL="http://localhost:9420/api/v1/auth/login"
USERNAME="admin"
PASSWORD="admin"
CRIBL_HOST="http://localhost:9420"

AUTH_TOKEN=$(curl -sk -X POST "$AUTH_URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "{\"username\": \"$USERNAME\", \"password\": \"$PASSWORD\"}" | \
  grep -o '"token":"[^"]*"' | cut -d':' -f2 | tr -d '"')

echo "$AUTH_TOKEN"


#DEST
curl -X POST $CRIBL_HOST/api/v1/system/outputs \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d @payload.json
echo "==========================================================================================================================================="
echo "==========================================================================================================================================="
#SOURCE
curl -X POST $CRIBL_HOST/api/v1/system/inputs \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d @source.json
echo "==========================================================================================================================================="
echo "==========================================================================================================================================="

#Pipeline
curl -X POST $CRIBL_HOST/api/v1/pipelines \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d @pipeline.json
echo "==========================================================================================================================================="
echo "==========================================================================================================================================="

curl -X PATCH $CRIBL_HOST/api/v1/pipelines/node-info \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d @pipeline_patch.json

echo "==========================================================================================================================================="
echo "==========================================================================================================================================="

#Pipeline
curl -X PATCH $CRIBL_HOST/api/v1/routes/default \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d @routes_patch.json
echo "==========================================================================================================================================="
echo "==========================================================================================================================================="

#Test
curl -X PATCH $CRIBL_HOST/api/v1/system/inputs/in_system_metrics \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d @system_metrics.json
echo "==========================================================================================================================================="
echo "==========================================================================================================================================="

curl -X PATCH $CRIBL_HOST/api/v1/system/inputs/in_file_auto \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d @in_file_monitor.json

echo "======================================================================"


# List Inputs
#curl -s -X GET $CRIBL_HOST/api/v1/system/inputs \
#  -H "Authorization: Bearer $AUTH_TOKEN"

# List Outputs
#curl -s -X GET $CRIBL_HOST/api/v1/system/outputs \
#  -H "Authorization: Bearer $AUTH_TOKEN"

# List Pipelines
#curl -s -X GET $CRIBL_HOST/api/v1/pipelines \
#  -H "Authorization: Bearer $AUTH_TOKEN"

# List Routes
#curl -s -X GET $CRIBL_HOST/api/v1/routes \
#  -H "Authorization: Bearer $AUTH_TOKEN"
