
locals {
  # Path to your local JSON secret file (adjust if you put the file elsewhere).
  # This file must exist on the machine where you run 'terraform apply'.
  local_secret_file = "${path.module}/../.secrets.json"

  # Try common bash locations so local-exec works on Windows Git Bash too.
  bash_candidates = compact([
    var.local_exec_bash,
    "/bin/bash",
    "C:/Program Files/Git/bin/bash.exe",
    "C:/Program Files/Git/usr/bin/bash.exe"
  ])

  bash_candidates_existing = [for c in local.bash_candidates : c if fileexists(c)]

  resolved_bash_path = length(local.bash_candidates_existing) > 0 ? local.bash_candidates_existing[0] : "/bin/bash"
}

resource "aws_secretsmanager_secret" "newsapi" {
  name        = "news-mvp_newsapi_${var.environment}"
  description = "NewsAPI key for News Ingest MVP"
  tags = {
    Environment = var.environment
    Project     = "news-ingest-mvp"
  }
}

resource "aws_secretsmanager_secret" "kafka" {
  name        = "news-mvp_kafka_${var.environment}"
  description = "Kafka credentials for News Ingest MVP"
  tags = {
    Environment = var.environment
    Project     = "news-ingest-mvp"
  }
}

# placeholder so secret exists (no value stored in TF state)
resource "aws_secretsmanager_secret_version" "newsapi_placeholder" {
  secret_id     = aws_secretsmanager_secret.newsapi.id
  secret_string = jsonencode({})
}

resource "aws_secretsmanager_secret_version" "kafka_placeholder" {
  secret_id     = aws_secretsmanager_secret.kafka.id
  secret_string = jsonencode({})
}

resource "null_resource" "upload_newsapi_secret" {
  triggers = {
    file_sha  = filemd5(local.local_secret_file)
    newsapi_secret_id = aws_secretsmanager_secret.newsapi.id
    kafka_secret_id   = aws_secretsmanager_secret.kafka.id
  }

  provisioner "local-exec" {
    interpreter = [local.resolved_bash_path, "-c"]
    command = <<EOT
      if [ ! -f "${local.local_secret_file}" ]; then
        echo "ERROR: Local secret file not found: ${local.local_secret_file}"
        echo "Create it (see README) and re-run 'terraform apply'."
        exit 1
      fi

      python <<'PY'
import json
import subprocess
import sys

secret_file = r"${local.local_secret_file}"
region = "${var.aws_region}"
targets = [
    ("${aws_secretsmanager_secret.newsapi.name}", "newsapi"),
    ("${aws_secretsmanager_secret.kafka.name}", "kafka"),
]

try:
    with open(secret_file, "r", encoding="utf-8") as f:
        payload = json.load(f)
except FileNotFoundError:
    print(f"Secret file not found: {secret_file}", file=sys.stderr)
    sys.exit(1)

for secret_name, key in targets:
    data = payload.get(key)
    if not data:
        print(f"Skipping {secret_name}: key '{key}' missing or empty")
        continue

    subprocess.run(
        [
            "aws",
            "secretsmanager",
            "put-secret-value",
            "--secret-id",
            secret_name,
            "--secret-string",
            json.dumps(data),
            "--region",
            region,
        ],
        check=True,
    )
    print(f"Uploaded secret to {secret_name}")
PY
    EOT
  }

  depends_on = [
    aws_secretsmanager_secret.newsapi,
    aws_secretsmanager_secret.kafka,
    aws_secretsmanager_secret_version.newsapi_placeholder,
    aws_secretsmanager_secret_version.kafka_placeholder,
  ]
}
