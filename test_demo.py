"""
demo.py 测试脚本
使用 FXCM 官方 CSV 数据格式做端到端验证

运行: python test_demo.py
"""

import csv
import datetime
import gzip
import io
import sys
import unittest
from http.server import HTTPServer, BaseHTTPRequestHandler
from threading import Thread
from urllib.error import HTTPError, URLError
from unittest.mock import patch

import demo

# ============================================================
# FXCM 官方 CSV 格式的真实样本数据
# 字段来自 https://github.com/fxcm/MarketData
# ============================================================
FXCM_SAMPLE_CSV = """\
DateTime,BidOpen,BidHigh,BidLow,BidClose,AskOpen,AskHigh,AskLow,AskClose,TickQty
01/05/2020 17:00:00,1.11580,1.11616,1.11548,1.11592,1.11610,1.11630,1.11564,1.11608,9156
01/05/2020 18:00:00,1.11592,1.11620,1.11572,1.11610,1.11608,1.11640,1.11588,1.11628,5765
01/05/2020 19:00:00,1.11610,1.11668,1.11600,1.11650,1.11628,1.11684,1.11618,1.11668,4123
01/05/2020 20:00:00,1.11650,1.11688,1.11622,1.11674,1.11668,1.11702,1.11638,1.11690,3842
01/05/2020 21:00:00,1.11674,1.11700,1.11658,1.11680,1.11690,1.11718,1.11674,1.11696,2156
01/06/2020 09:00:00,1.11782,1.11830,1.11760,1.11810,1.11798,1.11846,1.11776,1.11826,12456
01/06/2020 10:00:00,1.11810,1.11892,1.11790,1.11870,1.11826,1.11908,1.11806,1.11886,15678
01/06/2020 11:00:00,1.11870,1.11920,1.11842,1.11856,1.11886,1.11936,1.11858,1.11872,11234
"""


def make_gzipped_csv(csv_text):
    """将 CSV 文本压缩为 gzip 格式 (FXCM 官方格式)"""
    return gzip.compress(csv_text.encode("utf-8"))


class FXCMTestServer(BaseHTTPRequestHandler):
    """模拟 FXCM candledata.fxcorporate.com 的本地测试服务器"""

    def do_GET(self):
        # 模拟 FXCM URL 路由: /{periodicity}/{symbol}/{year}/{week}.csv.gz
        path = self.path

        if "/INVALID/" in path:
            self.send_error(404)
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/gzip")
        self.end_headers()
        self.wfile.write(make_gzipped_csv(FXCM_SAMPLE_CSV))

    def log_message(self, format, *args):
        pass  # suppress output


class TestParseArgs(unittest.TestCase):
    """测试命令行参数解析"""

    def test_defaults(self):
        args = demo.parse_args([])
        self.assertEqual(args.symbol, "EURUSD")
        self.assertEqual(args.periodicity, "H1")
        self.assertIsNone(args.date)
        self.assertIsNone(args.year)
        self.assertFalse(args.list)

    def test_symbol(self):
        args = demo.parse_args(["-s", "USDJPY"])
        self.assertEqual(args.symbol, "USDJPY")

    def test_periodicity(self):
        args = demo.parse_args(["-p", "m1"])
        self.assertEqual(args.periodicity, "m1")

    def test_date(self):
        args = demo.parse_args(["-d", "2020-03-15"])
        self.assertEqual(args.date, "2020-03-15")

    def test_year(self):
        args = demo.parse_args(["-y", "2020"])
        self.assertEqual(args.year, 2020)

    def test_list_flag(self):
        args = demo.parse_args(["--list"])
        self.assertTrue(args.list)


class TestBuildUrl(unittest.TestCase):
    """测试 URL 构建"""

    def test_h1_url(self):
        url = demo.build_url("EURUSD", "H1", 2020, 1)
        self.assertEqual(url, "https://candledata.fxcorporate.com/H1/EURUSD/2020/1.csv.gz")

    def test_m1_url(self):
        url = demo.build_url("USDJPY", "m1", 2020, 15)
        self.assertEqual(url, "https://candledata.fxcorporate.com/m1/USDJPY/2020/15.csv.gz")

    def test_d1_url(self):
        url = demo.build_url("GBPUSD", "D1", 2020)
        self.assertEqual(url, "https://candledata.fxcorporate.com/D1/GBPUSD/2020.csv.gz")


class TestGetTargetWeek(unittest.TestCase):
    """测试日期到周数的转换"""

    def test_specific_date(self):
        year, week = demo.get_target_week("2020-03-15")
        self.assertEqual(year, 2020)
        self.assertEqual(week, 11)

    def test_default_date(self):
        year, week = demo.get_target_week(None)
        self.assertIsInstance(year, int)
        self.assertIsInstance(week, int)
        self.assertGreaterEqual(week, 1)
        self.assertLessEqual(week, 53)


class TestParseCandleRows(unittest.TestCase):
    """测试 FXCM CSV 数据解析 (使用真实 FXCM 数据格式)"""

    def setUp(self):
        reader = csv.DictReader(io.StringIO(FXCM_SAMPLE_CSV))
        self.rows = list(reader)

    def test_parse_count(self):
        candles = demo.parse_candle_rows(self.rows)
        self.assertEqual(len(candles), 8)

    def test_parse_fields(self):
        candles = demo.parse_candle_rows(self.rows)
        c = candles[0]
        self.assertEqual(c["datetime"], "01/05/2020 17:00:00")
        self.assertAlmostEqual(c["bid_open"], 1.11580)
        self.assertAlmostEqual(c["bid_high"], 1.11616)
        self.assertAlmostEqual(c["bid_low"], 1.11548)
        self.assertAlmostEqual(c["bid_close"], 1.11592)
        self.assertAlmostEqual(c["ask_open"], 1.11610)
        self.assertAlmostEqual(c["ask_close"], 1.11608)

    def test_parse_last_row(self):
        candles = demo.parse_candle_rows(self.rows)
        c = candles[-1]
        self.assertEqual(c["datetime"], "01/06/2020 11:00:00")
        self.assertAlmostEqual(c["bid_close"], 1.11856)

    def test_empty_input(self):
        candles = demo.parse_candle_rows([])
        self.assertEqual(candles, [])


class TestDisplayCandles(unittest.TestCase):
    """测试 K 线数据展示"""

    def setUp(self):
        reader = csv.DictReader(io.StringIO(FXCM_SAMPLE_CSV))
        self.candles = demo.parse_candle_rows(list(reader))

    def test_display_all(self):
        with patch("sys.stdout", new_callable=io.StringIO) as out:
            count = demo.display_candles(self.candles, "EURUSD", "H1")
        self.assertEqual(count, 8)
        output = out.getvalue()
        self.assertIn("EURUSD", output)
        self.assertIn("1.11580", output)
        self.assertIn("共 8 条记录", output)

    def test_display_limited(self):
        with patch("sys.stdout", new_callable=io.StringIO) as out:
            count = demo.display_candles(self.candles, "EURUSD", "H1", limit=3)
        self.assertEqual(count, 3)
        output = out.getvalue()
        self.assertIn("显示最近 3 条", output)

    def test_display_change(self):
        with patch("sys.stdout", new_callable=io.StringIO) as out:
            demo.display_candles(self.candles, "EURUSD", "H1")
        output = out.getvalue()
        self.assertIn("期间变动", output)
        self.assertIn("%", output)


class TestEndToEnd(unittest.TestCase):
    """端到端测试：启动本地 HTTP 服务模拟 FXCM 服务器"""

    @classmethod
    def setUpClass(cls):
        cls.server = HTTPServer(("127.0.0.1", 0), FXCMTestServer)
        cls.port = cls.server.server_address[1]
        cls.thread = Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def test_download_and_parse(self):
        """完整流程: 下载 → 解压 → 解析 → 展示"""
        url = f"http://127.0.0.1:{self.port}/H1/EURUSD/2020/1.csv.gz"
        rows = demo.download_candle_data(url)
        self.assertEqual(len(rows), 8)

        candles = demo.parse_candle_rows(rows)
        self.assertEqual(len(candles), 8)
        self.assertAlmostEqual(candles[0]["bid_open"], 1.11580)

        with patch("sys.stdout", new_callable=io.StringIO) as out:
            count = demo.display_candles(candles, "EURUSD", "H1")
        self.assertEqual(count, 8)
        self.assertIn("EURUSD", out.getvalue())

    def test_full_main_flow(self):
        """测试 main() 完整流程"""
        test_url = f"http://127.0.0.1:{self.port}"
        with patch.object(demo, "CANDLE_BASE_URL", test_url):
            with patch("sys.stdout", new_callable=io.StringIO) as out:
                demo.main(["-s", "EURUSD", "-p", "D1", "-y", "2020"])
        output = out.getvalue()
        self.assertIn("EURUSD", output)
        self.assertIn("1.11580", output)
        self.assertIn("查询完成", output)

    def test_404_handling(self):
        """测试 404 错误处理"""
        url = f"http://127.0.0.1:{self.port}/H1/INVALID/2020/1.csv.gz"
        with patch("sys.stdout", new_callable=io.StringIO):
            rows = demo.download_candle_data(url)
        self.assertEqual(rows, [])

    def test_list_symbols(self):
        """测试货币对列表"""
        with patch("sys.stdout", new_callable=io.StringIO) as out:
            demo.main(["--list"])
        output = out.getvalue()
        self.assertIn("EUR/USD", output)
        self.assertIn("USD/JPY", output)
        self.assertIn(str(len(demo.SYMBOLS)), output)

    def test_invalid_symbol(self):
        """测试无效货币对"""
        with self.assertRaises(SystemExit):
            with patch("sys.stdout", new_callable=io.StringIO):
                demo.main(["-s", "XXXYYY"])


class TestListSymbols(unittest.TestCase):
    """测试货币对列表展示"""

    def test_output(self):
        with patch("sys.stdout", new_callable=io.StringIO) as out:
            demo.list_symbols()
        output = out.getvalue()
        self.assertIn("EUR/USD", output)
        self.assertIn(str(len(demo.SYMBOLS)), output)


if __name__ == "__main__":
    unittest.main()
