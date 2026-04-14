"""
ToolBox Pro - FXCM 外汇行情数据 Demo
基于 FXCM 官方免费 K 线数据接口，无需注册、无需 API Key

数据来源: https://github.com/fxcm/MarketData
接口地址: https://candledata.fxcorporate.com/

用法:
  python demo.py                                    # EURUSD 最近一周 H1 数据
  python demo.py -s USDJPY                          # 指定货币对
  python demo.py -s EURUSD -p m1 -d 2020-03-15      # 指定周期和日期
  python demo.py -s EURUSD -p D1 -y 2020            # 日线 (按年)
  python demo.py --list                             # 列出支持的货币对

依赖: 仅 Python 标准库 (无需 pip install)
"""

import argparse
import csv
import datetime
import gzip
import io
import sys
import urllib.request
import urllib.error

CANDLE_BASE_URL = "https://candledata.fxcorporate.com"

SYMBOLS = [
    "AUDCAD", "AUDCHF", "AUDJPY", "AUDNZD", "CADCHF",
    "EURAUD", "EURCHF", "EURGBP", "EURJPY", "EURUSD",
    "GBPCHF", "GBPJPY", "GBPNZD", "GBPUSD",
    "NZDCAD", "NZDCHF", "NZDJPY", "NZDUSD",
    "USDCAD", "USDCHF", "USDJPY",
]

PERIODICITIES = ["m1", "H1", "D1"]


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="FXCM 外汇行情数据查询工具 (官方免费数据接口)"
    )
    parser.add_argument("-s", "--symbol", default="EURUSD",
                        help="货币对 (默认: EURUSD)")
    parser.add_argument("-p", "--periodicity", default="H1",
                        choices=PERIODICITIES,
                        help="K线周期: m1(分钟), H1(小时), D1(日线) (默认: H1)")
    parser.add_argument("-d", "--date", default=None,
                        help="指定日期 YYYY-MM-DD (默认: 最近)")
    parser.add_argument("-y", "--year", type=int, default=None,
                        help="指定年份 (仅用于 D1 日线)")
    parser.add_argument("--list", action="store_true",
                        help="列出所有支持的货币对")
    return parser.parse_args(argv)


def build_url(symbol, periodicity, year, week=None):
    """构建 FXCM K 线数据下载 URL"""
    if periodicity == "D1":
        return f"{CANDLE_BASE_URL}/D1/{symbol}/{year}.csv.gz"
    else:
        return f"{CANDLE_BASE_URL}/{periodicity}/{symbol}/{year}/{week}.csv.gz"


def download_candle_data(url):
    """从 FXCM 下载并解压 K 线 CSV 数据"""
    req = urllib.request.Request(url, headers={"User-Agent": "ToolBoxPro/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as e:
        if e.code == 404:
            print(f"  数据不存在: {url}")
            print("  可能原因: 该时间段无数据，请尝试其他日期")
            return []
        print(f"  HTTP 错误 {e.code}: {url}")
        sys.exit(1)
    except urllib.error.URLError as e:
        print(f"  网络错误: {e.reason}")
        sys.exit(1)

    text = gzip.decompress(raw).decode("utf-8")
    reader = csv.DictReader(io.StringIO(text))
    return list(reader)


def parse_candle_rows(rows):
    """解析 FXCM K 线数据行，标准化字段名"""
    candles = []
    for row in rows:
        # FXCM CSV 字段名: DateTime, Open, High, Low, Close (Bid/Ask 前缀)
        candle = {}
        for key, val in row.items():
            k = key.strip().lower()
            if "datetime" in k or "date" in k:
                candle["datetime"] = val.strip()
            elif k.startswith("bid"):
                suffix = k.replace("bid", "").strip()
                if "open" in suffix:
                    candle["bid_open"] = float(val)
                elif "high" in suffix:
                    candle["bid_high"] = float(val)
                elif "low" in suffix:
                    candle["bid_low"] = float(val)
                elif "close" in suffix:
                    candle["bid_close"] = float(val)
            elif k.startswith("ask"):
                suffix = k.replace("ask", "").strip()
                if "open" in suffix:
                    candle["ask_open"] = float(val)
                elif "high" in suffix:
                    candle["ask_high"] = float(val)
                elif "low" in suffix:
                    candle["ask_low"] = float(val)
                elif "close" in suffix:
                    candle["ask_close"] = float(val)
        if candle.get("datetime"):
            candles.append(candle)
    return candles


def display_candles(candles, symbol, periodicity, limit=20):
    """展示 K 线数据"""
    print(f"\n{'='*70}")
    print(f"  {symbol} {periodicity} K线数据 (FXCM)")
    print(f"  共 {len(candles)} 条记录" + (f"，显示最近 {limit} 条" if len(candles) > limit else ""))
    print(f"{'='*70}")

    show = candles[-limit:] if len(candles) > limit else candles

    print(f"  {'时间':<22s} {'Bid开盘':>10s} {'Bid最高':>10s} {'Bid最低':>10s} {'Bid收盘':>10s}")
    print(f"  {'-'*22} {'-'*10} {'-'*10} {'-'*10} {'-'*10}")

    for c in show:
        dt = c.get("datetime", "N/A")
        bo = c.get("bid_open", 0)
        bh = c.get("bid_high", 0)
        bl = c.get("bid_low", 0)
        bc = c.get("bid_close", 0)
        print(f"  {dt:<22s} {bo:>10.5f} {bh:>10.5f} {bl:>10.5f} {bc:>10.5f}")

    if show:
        first = show[0]
        last = show[-1]
        open_price = first.get("bid_open", 0)
        close_price = last.get("bid_close", 0)
        if open_price > 0:
            change = close_price - open_price
            change_pct = (change / open_price) * 100
            print(f"\n  期间变动: {change:+.5f} ({change_pct:+.2f}%)")

    return len(show)


def list_symbols():
    """列出支持的货币对"""
    print(f"\nFXCM 支持的货币对 (共 {len(SYMBOLS)} 个):")
    print(f"{'='*50}")
    for i, sym in enumerate(SYMBOLS):
        base, quote = sym[:3], sym[3:]
        end = "\n" if (i + 1) % 4 == 0 else ""
        print(f"  {base}/{quote}", end=end)
    print()


def get_target_week(date_str=None):
    """获取目标日期对应的年份和周数"""
    if date_str:
        dt = datetime.datetime.strptime(date_str, "%Y-%m-%d").date()
    else:
        dt = datetime.date.today() - datetime.timedelta(days=7)
    iso = dt.isocalendar()
    return iso[0], iso[1]


def main(argv=None):
    args = parse_args(argv)

    print(f"\nFXCM 外汇行情数据 Demo")
    print(f"数据来源: FXCM (candledata.fxcorporate.com)")

    if args.list:
        list_symbols()
        return

    symbol = args.symbol.upper()
    if symbol not in SYMBOLS:
        print(f"\n错误: 不支持的货币对 '{symbol}'")
        print(f"支持的货币对: {', '.join(SYMBOLS)}")
        sys.exit(1)

    periodicity = args.periodicity

    if periodicity == "D1":
        year = args.year or 2020
        url = build_url(symbol, periodicity, year)
        print(f"查询: {symbol} 日线 {year}年")
    else:
        year, week = get_target_week(args.date)
        url = build_url(symbol, periodicity, year, week)
        print(f"查询: {symbol} {periodicity} {year}年第{week}周")

    print(f"URL: {url}")
    print(f"正在下载...")

    rows = download_candle_data(url)
    if not rows:
        print("\n无数据")
        return

    candles = parse_candle_rows(rows)
    if not candles:
        print("\n解析失败: 无有效 K 线数据")
        return

    display_candles(candles, symbol, periodicity)

    print(f"\n{'='*70}")
    print("  查询完成")
    print(f"{'='*70}\n")


if __name__ == "__main__":
    main()
