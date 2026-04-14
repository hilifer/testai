"""
demo.py 测试脚本
验证所有业务逻辑：参数解析、API 请求构建、数据展示

运行: python test_demo.py
"""

import io
import json
import sys
import unittest
from unittest.mock import patch, MagicMock
from urllib.error import HTTPError, URLError

import demo


class TestParseArgs(unittest.TestCase):
    """测试命令行参数解析"""

    def test_defaults(self):
        args = demo.parse_args([])
        self.assertEqual(args.base, "USD")
        self.assertEqual(args.targets, demo.DEFAULT_TARGETS)
        self.assertIsNone(args.amount)
        self.assertIsNone(args.history)
        self.assertFalse(args.list)

    def test_custom_base(self):
        args = demo.parse_args(["-b", "EUR"])
        self.assertEqual(args.base, "EUR")

    def test_custom_targets(self):
        args = demo.parse_args(["-t", "GBP,JPY"])
        self.assertEqual(args.targets, "GBP,JPY")

    def test_amount(self):
        args = demo.parse_args(["-a", "1000"])
        self.assertEqual(args.amount, 1000.0)

    def test_history(self):
        args = demo.parse_args(["--history", "2025-01-01", "2025-01-31"])
        self.assertEqual(args.history, ["2025-01-01", "2025-01-31"])

    def test_list_flag(self):
        args = demo.parse_args(["--list"])
        self.assertTrue(args.list)

    def test_all_combined(self):
        args = demo.parse_args(["-b", "EUR", "-t", "USD,GBP", "-a", "500"])
        self.assertEqual(args.base, "EUR")
        self.assertEqual(args.targets, "USD,GBP")
        self.assertEqual(args.amount, 500.0)


class TestApiRequest(unittest.TestCase):
    """测试 API 请求逻辑"""

    @patch("demo.urllib.request.urlopen")
    def test_success(self, mock_urlopen):
        mock_resp = MagicMock()
        mock_resp.read.return_value = b'{"base":"USD","rates":{"EUR":0.92}}'
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_resp

        result = demo.api_request("latest?base=USD")
        self.assertEqual(result["base"], "USD")
        self.assertAlmostEqual(result["rates"]["EUR"], 0.92)

        call_args = mock_urlopen.call_args
        req = call_args[0][0]
        self.assertIn("latest?base=USD", req.full_url)
        self.assertEqual(req.get_header("User-agent"), "ToolBoxPro/1.0")

    @patch("demo.urllib.request.urlopen")
    def test_http_error_422(self, mock_urlopen):
        mock_urlopen.side_effect = HTTPError(
            "url", 422, "Unprocessable", {}, io.BytesIO(b"")
        )
        with self.assertRaises(SystemExit) as ctx:
            demo.api_request("latest?base=INVALID")
        self.assertEqual(ctx.exception.code, 1)

    @patch("demo.urllib.request.urlopen")
    def test_network_error(self, mock_urlopen):
        mock_urlopen.side_effect = URLError("Connection refused")
        with self.assertRaises(SystemExit) as ctx:
            demo.api_request("latest?base=USD")
        self.assertEqual(ctx.exception.code, 1)


class TestQueryLatest(unittest.TestCase):
    """测试最新汇率查询"""

    @patch("demo.api_request")
    def test_basic_query(self, mock_api):
        mock_api.return_value = {
            "base": "USD",
            "date": "2025-04-10",
            "rates": {"EUR": 0.92, "GBP": 0.79, "JPY": 149.5}
        }
        with patch("sys.stdout", new_callable=io.StringIO) as out:
            rates = demo.query_latest("USD", "EUR,GBP,JPY")

        mock_api.assert_called_once_with("latest?base=USD&symbols=EUR,GBP,JPY")
        self.assertEqual(len(rates), 3)
        self.assertIn("EUR", rates)
        output = out.getvalue()
        self.assertIn("USD/EUR", output)
        self.assertIn("0.92", output)

    @patch("demo.api_request")
    def test_with_amount(self, mock_api):
        mock_api.return_value = {
            "base": "USD",
            "date": "2025-04-10",
            "rates": {"CNY": 7.25}
        }
        with patch("sys.stdout", new_callable=io.StringIO) as out:
            demo.query_latest("USD", "CNY", amount=1000)

        output = out.getvalue()
        self.assertIn("1,000.00 USD", output)
        self.assertIn("7,250.00 CNY", output)

    @patch("demo.api_request")
    def test_empty_rates(self, mock_api):
        mock_api.return_value = {"base": "USD", "date": "2025-04-10", "rates": {}}
        with patch("sys.stdout", new_callable=io.StringIO) as out:
            rates = demo.query_latest("USD", "XYZ")

        self.assertEqual(rates, {})
        self.assertIn("无数据", out.getvalue())


class TestQueryHistory(unittest.TestCase):
    """测试历史汇率查询"""

    @patch("demo.api_request")
    def test_history_query(self, mock_api):
        mock_api.return_value = {
            "base": "USD",
            "start_date": "2025-01-02",
            "end_date": "2025-01-03",
            "rates": {
                "2025-01-02": {"EUR": 0.91},
                "2025-01-03": {"EUR": 0.92}
            }
        }
        with patch("sys.stdout", new_callable=io.StringIO) as out:
            rates = demo.query_history("USD", "EUR", "2025-01-02", "2025-01-03")

        mock_api.assert_called_once_with(
            "2025-01-02..2025-01-03?base=USD&symbols=EUR"
        )
        self.assertEqual(len(rates), 2)
        output = out.getvalue()
        self.assertIn("2025-01-02", output)
        self.assertIn("0.91", output)

    @patch("demo.api_request")
    def test_empty_history(self, mock_api):
        mock_api.return_value = {
            "base": "USD",
            "start_date": "2025-01-01",
            "end_date": "2025-01-01",
            "rates": {}
        }
        with patch("sys.stdout", new_callable=io.StringIO) as out:
            rates = demo.query_history("USD", "EUR", "2025-01-01", "2025-01-01")

        self.assertEqual(rates, {})
        self.assertIn("无数据", out.getvalue())


class TestListCurrencies(unittest.TestCase):
    """测试货币列表"""

    @patch("demo.api_request")
    def test_list(self, mock_api):
        mock_api.return_value = {
            "USD": "United States Dollar",
            "EUR": "Euro",
            "CNY": "Chinese Renminbi",
        }
        with patch("sys.stdout", new_callable=io.StringIO) as out:
            demo.list_currencies()

        mock_api.assert_called_once_with("currencies")
        output = out.getvalue()
        self.assertIn("共 3 种", output)
        self.assertIn("CNY", output)
        self.assertIn("Chinese Renminbi", output)


class TestMain(unittest.TestCase):
    """测试 main 入口"""

    @patch("demo.query_latest")
    def test_main_default(self, mock_query):
        mock_query.return_value = {}
        with patch("sys.stdout", new_callable=io.StringIO):
            demo.main([])
        mock_query.assert_called_once_with("USD", demo.DEFAULT_TARGETS, None)

    @patch("demo.query_latest")
    def test_main_with_amount(self, mock_query):
        mock_query.return_value = {}
        with patch("sys.stdout", new_callable=io.StringIO):
            demo.main(["-b", "EUR", "-t", "USD", "-a", "100"])
        mock_query.assert_called_once_with("EUR", "USD", 100.0)

    @patch("demo.list_currencies")
    def test_main_list(self, mock_list):
        with patch("sys.stdout", new_callable=io.StringIO):
            demo.main(["--list"])
        mock_list.assert_called_once()

    @patch("demo.query_history")
    def test_main_history(self, mock_hist):
        mock_hist.return_value = {}
        with patch("sys.stdout", new_callable=io.StringIO):
            demo.main(["--history", "2025-01-01", "2025-01-31"])
        mock_hist.assert_called_once_with(
            "USD", demo.DEFAULT_TARGETS, "2025-01-01", "2025-01-31"
        )


if __name__ == "__main__":
    unittest.main()
