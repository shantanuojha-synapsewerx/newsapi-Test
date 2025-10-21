# newsapi_ingest.py
import os
import json
import logging
import hashlib
from datetime import datetime, timezone
from typing import List, Dict, Any, Optional, Set

import boto3
import requests
from botocore.exceptions import ClientError

try:
    from confluent_kafka import Producer
except ImportError as kafka_import_error:  # pragma: no cover - import validated at deploy time
    Producer = None  # type: ignore
    KAFKA_IMPORT_ERROR = kafka_import_error
else:
    KAFKA_IMPORT_ERROR = None

logger = logging.getLogger("newsapi_ingest")
logger.setLevel(os.getenv("LOG_LEVEL", "INFO"))

# env
NEWSAPI_SECRET_ARN = os.getenv("NEWSAPI_SECRET_ARN")
DDB_TABLE = os.getenv("DDB_TABLE")
KAFKA_SECRET_ARN = os.getenv("KAFKA_SECRET_ARN")
PAGE_SIZE = int(os.getenv("PAGE_SIZE", "10"))
NEWSAPI_URL = "https://newsapi.org/v2/everything"
DEFAULT_FROM = os.getenv("DEFAULT_FROM", "2025-10-01T00:00:00Z")
ENV = os.getenv("ENVIRONMENT", "dev")
MAX_PAGES = int(os.getenv("MAX_PAGES", "10"))
RAW_TOPIC = os.getenv("RAW_TOPIC", f"topic_private_{ENV}_newsapi")
CURATED_TOPIC = os.getenv("CURATED_TOPIC", f"topic_{ENV}_news")

secrets = boto3.client("secretsmanager")
cw = boto3.client("cloudwatch")
dynamodb = boto3.resource("dynamodb")

secret_cache: Dict[str, Dict[str, Any]] = {}
kafka_producer: Optional[Any] = None

# Expected fields from NewsAPI responses to ensure downstream schemas see consistent shape.
EXPECTED_ARTICLE_KEYS = {
    "source",
    "author",
    "title",
    "description",
    "url",
    "urlToImage",
    "publishedAt",
    "content",
}
EXPECTED_SOURCE_KEYS = {"id", "name"}

def get_secret(secret_arn: Optional[str]) -> Dict[str, Any]:
    if not secret_arn:
        raise RuntimeError("Secret ARN not provided")
    if secret_arn in secret_cache:
        return secret_cache[secret_arn]
    try:
        resp = secrets.get_secret_value(SecretId=secret_arn)
        if "SecretString" in resp:
            value = json.loads(resp["SecretString"])
            secret_cache[secret_arn] = value
            return value
        else:
            raise RuntimeError("Secret has no SecretString")
    except ClientError as e:
        logger.error("Unable to fetch secret %s: %s", secret_arn, e)
        raise

def compute_hash(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()

def publish_metric(name: str, value: float):
    try:
        cw.put_metric_data(
            Namespace="NewsIngestMVP",
            MetricData=[
                {
                    "MetricName": name,
                    "Dimensions": [{"Name": "Environment", "Value": ENV}],
                    "Timestamp": datetime.now(timezone.utc),
                    "Value": value,
                    "Unit": "Count"
                }
            ]
        )
    except Exception as e:
        logger.warning("Failed to publish metric %s: %s", name, e)

def fetch_news(api_key: str, from_iso: str, page: int = 1) -> Dict[str, Any]:
    params = {
        "q": "bitcoin",
        "from": from_iso,
        "sortBy": "publishedAt",
        "pageSize": PAGE_SIZE,
        "page": page,
        "language": "en",
        "apiKey": api_key
    }
    headers = {"User-Agent": "newsapi-ingest-mvp/1.0"}
    r = requests.get(NEWSAPI_URL, params=params, headers=headers, timeout=10)
    r.raise_for_status()
    return r.json()


def fetch_all_news(api_key: str, from_iso: str) -> List[Dict[str, Any]]:
    articles: List[Dict[str, Any]] = []
    total_results: Optional[int] = None

    for page in range(1, MAX_PAGES + 1):
        resp = fetch_news(api_key, from_iso, page=page)
        if total_results is None:
            total_results = resp.get("totalResults")

        page_articles = resp.get("articles", []) or []
        if not page_articles:
            break

        articles.extend(page_articles)

        if total_results is not None and len(articles) >= total_results:
            break

        if len(page_articles) < PAGE_SIZE:
            break

    return articles

def put_url_in_dynamo(table_name: str, doc: Dict[str, Any]) -> bool:
    if not table_name:
        logger.error("DDB_TABLE env var not set; skipping persistence")
        return False

    table = dynamodb.Table(table_name)
    try:
        table.put_item(
            Item={
                "id": doc["url_hash"],
                "url": doc["url"],
                "inserted_at": doc["inserted_at"],
            },
            ConditionExpression="attribute_not_exists(id)",
        )
        return True
    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code")
        if error_code == "ConditionalCheckFailedException":
            logger.info("URL %s already recorded in DynamoDB", doc.get("url"))
            return False
        logger.error("Failed to write url %s: %s", doc.get("url"), e)
    except Exception as e:  # pragma: no cover - defensive
        logger.error("Unexpected error writing to DynamoDB: %s", e)
    return False


def get_existing_hashes(table_name: str, url_hashes: List[str]) -> Set[str]:
    if not table_name or not url_hashes:
        return set()

    existing: Set[str] = set()
    table = dynamodb.Table(table_name)

    for url_hash in url_hashes:
        try:
            resp = table.get_item(Key={"id": url_hash}, ProjectionExpression="id")
        except Exception as e:  # pragma: no cover - defensive
            logger.error("Failed to read hash %s from DynamoDB: %s", url_hash, e)
            continue
        item = resp.get("Item")
        if item and item.get("id"):
            existing.add(item["id"])

    return existing


def publish_raw_to_kafka(article: Dict[str, Any], key: str, topic: str) -> bool:
    try:
        producer = get_kafka_producer()
    except Exception as exc:
        logger.error("Kafka producer unavailable: %s", exc)
        return False

    try:
        payload = json.dumps(article, default=str).encode("utf-8")
    except (TypeError, ValueError) as exc:
        logger.error("Failed to serialise article for key %s: %s", key, exc)
        return False

    try:
        producer.produce(topic=topic, key=key.encode("utf-8"), value=payload)
        producer.flush()
        return True
    except BufferError:
        logger.warning("Kafka buffer full when producing key %s; flushing and retrying once", key)
        try:
            producer.flush()
            producer.produce(topic=topic, key=key.encode("utf-8"), value=payload)
            producer.flush()
            return True
        except Exception as inner_exc:
            logger.error("Kafka publish failed for key %s after retry: %s", key, inner_exc)
            return False
    except Exception as exc:  # pragma: no cover - defensive
        logger.error("Kafka publish failed for key %s: %s", key, exc)
        return False


def get_kafka_config() -> Dict[str, str]:
    if not KAFKA_SECRET_ARN:
        raise RuntimeError("KAFKA_SECRET_ARN env var not set")

    secret = get_secret(KAFKA_SECRET_ARN)
    confluent_section = secret.get("confluent") or {}

    bootstrap = confluent_section.get("bootstrap_servers") or secret.get("bootstrap")
    api_key = confluent_section.get("api_key") or secret.get("username")
    api_secret = confluent_section.get("api_secret") or secret.get("password")

    if not bootstrap or not api_key or not api_secret:
        raise RuntimeError("Kafka secret missing bootstrap/api credentials")

    config: Dict[str, str] = {
        "bootstrap.servers": bootstrap,
        "security.protocol": confluent_section.get("security_protocol", "SASL_SSL"),
        "sasl.mechanism": confluent_section.get("sasl_mechanism", "PLAIN"),
        "sasl.username": api_key,
        "sasl.password": api_secret,
        "linger.ms": "0",
        "acks": "all",
    }

    if "client_id" in confluent_section:
        config["client.id"] = str(confluent_section["client_id"])

    return config


def get_kafka_producer() -> Any:
    global kafka_producer

    if kafka_producer is not None:
        return kafka_producer

    if Producer is None:
        raise RuntimeError(f"confluent-kafka is not available: {KAFKA_IMPORT_ERROR}")

    config = get_kafka_config()
    kafka_producer = Producer(config)
    return kafka_producer


def normalise_article_schema(article: Dict[str, Any]) -> Dict[str, Any]:
    """Ensure NewsAPI article has all expected keys with explicit None defaults."""
    normalised = dict(article)  # shallow copy keeps nested structures mutable if already dicts

    # Normalise source structure
    source_obj = normalised.get("source")
    if not isinstance(source_obj, dict):
        source_obj = {}
    source_normalised = {key: source_obj.get(key) for key in EXPECTED_SOURCE_KEYS}
    normalised["source"] = source_normalised

    # Ensure all top-level keys exist so downstream schemas see consistent shape
    for key in EXPECTED_ARTICLE_KEYS:
        normalised.setdefault(key, None)

    return normalised

def lambda_handler(event, context):
    logger.info("Lambda triggered for News MVP")

    news_secret_arn = os.getenv("NEWSAPI_SECRET_ARN") or NEWSAPI_SECRET_ARN
    if not news_secret_arn:
        logger.error("Missing NEWSAPI_SECRET_ARN env var")
        return {"status": "error", "reason": "missing_newsapi_secret"}

    kafka_secret_arn = os.getenv("KAFKA_SECRET_ARN") or KAFKA_SECRET_ARN
    if not kafka_secret_arn:
        logger.error("Missing KAFKA_SECRET_ARN env var")
        return {"status": "error", "reason": "missing_kafka_secret"}

    try:
        news_secret = get_secret(news_secret_arn)
    except Exception as e:  # pragma: no cover - logged upstream
        logger.error("Failed to load NewsAPI secret: %s", e)
        return {"status": "error", "reason": "secret_fetch_failed"}

    api_key = (
        os.getenv("NEWSAPI_API_KEY")
        or news_secret.get("apiKey")
        or news_secret.get("newsapi", {}).get("apiKey")
    )
    if not api_key:
        logger.error("Missing NewsAPI key in secret or env")
        return {"status": "error", "reason": "missing_api_key"}

    table_name = os.getenv("DDB_TABLE") or DDB_TABLE
    if not table_name:
        logger.error("Missing DDB_TABLE env var")
        return {"status": "error", "reason": "missing_table"}

    try:
        get_kafka_producer()
    except Exception as exc:
        logger.error("Unable to initialise Kafka producer: %s", exc)
        return {"status": "error", "reason": "kafka_init_failed"}

    from_iso = DEFAULT_FROM
    try:
        articles = fetch_all_news(api_key, from_iso)
    except Exception as e:
        logger.error("Failed to fetch news: %s", e)
        return {"status": "error", "reason": "fetch_failed"}

    publish_metric("ArticlesFetched", len(articles))

    unique_records: Dict[str, Dict[str, Any]] = {}
    for article in articles:
        normalised_article = normalise_article_schema(article)
        url = normalised_article.get("url")
        if not url:
            continue
        url_hash = compute_hash(url)
        if url_hash not in unique_records:
            now_iso = datetime.now(timezone.utc).isoformat()
            unique_records[url_hash] = {
                "doc": {
                    "url": url,
                    "url_hash": url_hash,
                    "inserted_at": now_iso,
                },
                "article": normalised_article,
            }

    inserted = 0
    published = 0
    if unique_records:
        hashes = list(unique_records.keys())
        existing_hashes = get_existing_hashes(table_name, hashes)
        pending = [(h, data) for h, data in unique_records.items() if h not in existing_hashes]

        if not pending:
            logger.info("No new urls detected; nothing to enqueue for Kafka")
        else:
            for url_hash, data in pending:
                article = data["article"]
                doc = data["doc"]

                if not publish_raw_to_kafka(article, url_hash, RAW_TOPIC):
                    logger.error("Kafka publish failed for url %s; skipping DDB insert", doc.get("url"))
                    continue

                published += 1

                if put_url_in_dynamo(table_name, doc):
                    inserted += 1

            logger.info("Published %d messages to Kafka; %d persisted to DynamoDB", published, inserted)

    publish_metric("ArticlesInserted", inserted)

    logger.info(
        "Fetched %d articles; published %d new messages; inserted %d new urls",
        len(articles),
        published,
        inserted,
    )
    return {"fetched": len(articles), "published": published, "inserted": inserted}
