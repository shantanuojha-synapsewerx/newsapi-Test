# newsapi-Test
A demo for using teraform and cicd effectively.

## Build Lambda Package

From the repo root you can rebuild `terraform/newsapi_ingest.zip` with dependencies:

```bash
rm -rf build
MSYS_NO_PATHCONV=1 docker run --rm \
  -v "$(pwd -W):/workspace" \
  -w /workspace \
  --entrypoint /bin/bash \
  public.ecr.aws/lambda/python:3.10 \
  -c 'pip install --upgrade pip && pip install --no-cache-dir -r lambda/requirements.lock -t build'
cp lambda/newsapi_ingest.py build/
cd build
zip -r ../terraform/newsapi_ingest.zip .
cd ..
cd terraform/main
terraform apply -auto-approve
cd ../..
```

After updating the zip, run `terraform apply` so the new package is deployed.

### Secrets Manager gotcha

If you delete the `news-mvp_*` secrets and immediately rerun Terraform, AWS Secrets Manager keeps the same names in a “scheduled for deletion” state for up to seven days. Terraform can’t recreate them until the hold expires. To unblock yourself quickly, either restore the secrets or purge them before applying again:

```bash
# Option 1: restore the scheduled-for-deletion secrets
aws secretsmanager restore-secret --secret-id news-mvp_newsapi_dev
aws secretsmanager restore-secret --secret-id news-mvp_kafka_dev

# Option 2: permanently delete so Terraform can recreate (destructive)
aws secretsmanager delete-secret --secret-id news-mvp_newsapi_dev --force-delete-without-recovery
aws secretsmanager delete-secret --secret-id news-mvp_kafka_dev --force-delete-without-recovery

# If you restored, import them into state so Terraform stops trying to recreate
terraform import aws_secretsmanager_secret.newsapi news-mvp_newsapi_dev
terraform import aws_secretsmanager_secret.kafka   news-mvp_kafka_dev
```

Pick the approach that matches what you need—restoring keeps the data, force deletion wipes it.

## View Lambda Logs

CloudWatch logs can be tailed with the AWS CLI. On PowerShell/CMD:

```powershell
aws logs tail /aws/lambda/newsapi_ingest_dev
```

In Git Bash/MSYS, disable path conversion so the `/aws/...` argument is preserved:

```bash
MSYS_NO_PATHCONV=1 aws logs tail /aws/lambda/newsapi_ingest_dev
```

## Run Unit Tests

Execute the locally runnable test suite without touching AWS resources:

```powershell
python -m unittest discover -s tests
```
