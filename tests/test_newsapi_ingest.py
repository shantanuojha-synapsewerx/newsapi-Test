import importlib
import unittest
from unittest import mock


ingest = importlib.import_module("lambda.newsapi_ingest")


SAMPLE_ARTICLE = {
    "source": {"id": None, "name": "Biztoc.com"},
    "author": "finance.yahoo.com",
    "title": "Bitcoin rises 2.5%, retakes $111,00, leading crypto stocks higher as markets stabilize after October sell-off",
    "description": "",
    "url": "https://biztoc.com/x/3ca0b6db9c0b8168",
    "urlToImage": "https://biztoc.com/cdn/950/og.png",
    "publishedAt": "2025-10-20T16:40:21Z",
    "content": (
        "{ window.open(this.href, '_blank'); }, 200); return false;\">Why did Amazon Web Services outage disrupt global "
        "websites? { window.open(this.href, '_blank'); }, 200); return false;\">How will Japa\u2026 [+837 chars]"
    ),
}


class NewsApiIngestTests(unittest.TestCase):
    def test_normalise_article_schema_sample_article_preserves_values(self):
        normalised = ingest.normalise_article_schema(SAMPLE_ARTICLE)

        # Expect the same structure the curated pipeline relies on.
        self.assertEqual(normalised, SAMPLE_ARTICLE)
        self.assertIsNot(normalised, SAMPLE_ARTICLE)

    def test_normalise_article_schema_adds_missing_fields(self):
        article = {"title": "only-title"}

        normalised = ingest.normalise_article_schema(article)

        self.assertEqual(set(normalised.keys()), ingest.EXPECTED_ARTICLE_KEYS)
        self.assertEqual(normalised["title"], "only-title")
        self.assertIsNone(normalised["author"])
        self.assertEqual(normalised["source"], {"id": None, "name": None})

    @mock.patch.object(ingest, "fetch_news")
    def test_fetch_all_news_respects_total_results(self, fetch_news_mock):
        fetch_news_mock.side_effect = [
            {"articles": [{"url": "a"}, {"url": "b"}], "totalResults": 3},
            {"articles": [{"url": "c"}], "totalResults": 3},
            {"articles": [{"url": "d"}], "totalResults": 4},
        ]

        with mock.patch.object(ingest, "MAX_PAGES", 5), mock.patch.object(ingest, "PAGE_SIZE", 2):
            articles = ingest.fetch_all_news("dummy-key", "2025-10-01T00:00:00Z")

        self.assertEqual([article["url"] for article in articles], ["a", "b", "c"])
        self.assertEqual(fetch_news_mock.call_count, 2)

    def test_publish_raw_to_kafka_success(self):
        ingest.kafka_producer = None
        producer_mock = mock.Mock()

        with mock.patch.object(ingest, "get_kafka_producer", return_value=producer_mock):
            article = {"url": "https://example.com", "title": "ok"}
            result = ingest.publish_raw_to_kafka(article, key="abc", topic="topic_private_dev_newsapi")

        self.assertTrue(result)
        producer_mock.produce.assert_called_once()
        kwargs = producer_mock.produce.call_args.kwargs
        self.assertEqual(kwargs["topic"], "topic_private_dev_newsapi")
        self.assertEqual(kwargs["key"], b"abc")
        self.assertTrue(kwargs["value"].decode("utf-8").startswith('{"url":'))
        self.assertGreaterEqual(producer_mock.flush.call_count, 1)

    def test_publish_raw_to_kafka_handles_serialisation_failure(self):
        ingest.kafka_producer = None
        producer_mock = mock.Mock()

        with mock.patch.object(ingest, "get_kafka_producer", return_value=producer_mock):
            with mock.patch.object(ingest.json, "dumps", side_effect=TypeError("cannot serialise")):
                article = {"url": "https://example.com"}
                result = ingest.publish_raw_to_kafka(article, key="abc", topic="topic_private_dev_newsapi")

        self.assertFalse(result)
        producer_mock.produce.assert_not_called()

    def test_get_existing_hashes_returns_known_items(self):
        original_dynamodb = ingest.dynamodb
        table_mock = mock.Mock()
        table_mock.get_item.side_effect = [
            {"Item": {"id": "hash1"}},
            {},
            {"Item": {"id": "hash3"}},
        ]
        dynamodb_mock = mock.Mock()
        dynamodb_mock.Table.return_value = table_mock
        ingest.dynamodb = dynamodb_mock

        try:
            result = ingest.get_existing_hashes("table", ["hash1", "hash2", "hash3"])
        finally:
            ingest.dynamodb = original_dynamodb

        self.assertEqual(result, {"hash1", "hash3"})
        self.assertTrue(table_mock.get_item.called)

    def test_compute_hash_is_deterministic(self):
        value = "https://example.com/path"
        first = ingest.compute_hash(value)
        second = ingest.compute_hash(value)

        self.assertEqual(first, second)
        self.assertEqual(len(first), 64)


if __name__ == "__main__":
    unittest.main()
