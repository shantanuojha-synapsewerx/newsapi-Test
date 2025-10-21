SET 'auto.offset.reset'='earliest';

CREATE OR REPLACE STREAM NEWSAPI_RAW (
  url STRING,
  title STRING,
  description STRING,
  content STRING,
  publishedAt STRING,
  source STRUCT<id STRING, name STRING>
) WITH (
  KAFKA_TOPIC='${raw_topic}',
  VALUE_FORMAT='JSON'
);

CREATE OR REPLACE STREAM NEWSAPI_CURATED WITH (
  KAFKA_TOPIC='${curated_topic}',
  VALUE_FORMAT='AVRO',
  PARTITIONS=3,
  RETENTION_MS=${retention_ms}
) AS
SELECT
  url,
  title,
  description,
  content,
  source->name AS source_name,
  TIMESTAMPTOSTRING(ROWTIME, 'yyyy-MM-dd''T''HH:mm:ss.SSSZ') AS ingested_at,
  FROM_UNIXTIME(CAST(ROWTIME AS BIGINT) / 1000) AS ingested_at_epoch,
  publishedAt
FROM NEWSAPI_RAW
WHERE url IS NOT NULL
EMIT CHANGES;
