locals {
  ksql_raw_topic_name     = length(confluent_kafka_topic.raw) > 0 ? confluent_kafka_topic.raw[0].topic_name : "topic_private_${var.environment}_newsapi"
  ksql_curated_topic_name = length(confluent_kafka_topic.curated) > 0 ? confluent_kafka_topic.curated[0].topic_name : "topic_${var.environment}_news"
}

locals {
  ksql_payload = jsonencode({
    ksql               = templatefile("${path.module}/../../ksqldb/newsapi.sql.tpl", {
      raw_topic       = local.ksql_raw_topic_name,
      curated_topic   = local.ksql_curated_topic_name,
      retention_ms    = var.kafka_curated_retention_ms
    })
    streamsProperties = {
      "ksql.streams.auto.offset.reset" = "earliest"
    }
  })
}

resource "null_resource" "apply_ksql" {
  count = var.confluent_ksql_endpoint != "" && var.confluent_ksql_api_key != null && var.confluent_ksql_api_secret != null ? 1 : 0

  triggers = {
    payload_sha = sha256(local.ksql_payload)
    endpoint    = var.confluent_ksql_endpoint
  }

  provisioner "local-exec" {
    interpreter = [local.resolved_bash_path, "-c"]
    command = <<EOT
      set -euo pipefail
      tmpfile=$(mktemp)
      cat <<'JSON' > "$tmpfile"
${local.ksql_payload}
JSON
      response=$({
  KSQL_KEY=${var.confluent_ksql_api_key}
  KSQL_SECRET=${var.confluent_ksql_api_secret}
        curl -sS -w "\n%%{http_code}" -X POST \
          -H "Content-Type: application/vnd.ksql.v1+json; charset=utf-8" \
          -u "$KSQL_KEY:$KSQL_SECRET" \
          "${var.confluent_ksql_endpoint}/ksql" \
          -d @"$tmpfile"
      })
      status_code=$(printf "%s" "$response" | tail -n1)
      body=$(printf "%s" "$response" | sed '$d')
      trimmed=$(printf "%s" "$body" | tr -d '\n' | tr -d '\r' | tr -d '\t' | tr -d ' ')
      if [ -z "$trimmed" ]; then
        if [ "$status_code" -ge 400 ]; then
          printf "%s\n" "$body"
          exit 1
        fi
        rm -f "$tmpfile"
        exit 0
      fi
      printf "%s" "$body" | python - <<'PY'
import json
import sys

raw = sys.stdin.read().strip()
if not raw:
  sys.exit(0)

try:
  payload = json.loads(raw)
except json.JSONDecodeError as exc:
  print(raw)
  raise SystemExit(f"Invalid JSON from ksqlDB: {exc}")

errors = []
for entry in payload:
  status = entry.get("commandStatus", {}).get("status")
  if status and status != "SUCCESS":
    errors.append(entry)

if errors:
  print(json.dumps(payload, indent=2))
  raise SystemExit("ksqlDB statements failed")
PY
      if [ "$status_code" -ge 400 ]; then
        printf "%s\n" "$body"
        exit 1
      fi
      rm -f "$tmpfile"
    EOT
  }

  depends_on = [
    confluent_kafka_topic.raw,
    confluent_kafka_topic.curated
  ]
}
