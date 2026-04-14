"""
ToolBox Pro - 外汇汇率查询 Demo
用法: python demo.py [选项]

无需注册、无需 API Key，使用 Frankfurter 免费汇率 API
API 文档: https://frankfurter.dev/docs/

依赖: 仅 Python 标准库 (无需 pip install)

示例:
  python demo.py                          # 查询 USD 对主要货币的最新汇率
  python demo.py -b EUR                   # 查询 EUR 对主要货币的最新汇率
  python demo.py -b USD -t EUR,GBP,JPY    # 指定目标货币
  python demo.py -a 1000 -b USD -t CNY    # 换算 1000 USD 到 CNY
  python demo.py --history 2025-01-01 2025-01-31 -b USD -t EUR  # 历史汇率
"""

import argparse
import json
import sys
import urllib.request
import urllib.error

API_BASE = "https://api.frankfurter.dev/v1"
DEFAULT_TARGETS = "EUR,GBP,JPY,CNY,CHF,HKD,CAD,AUD"


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description="外汇汇率查询工具 (Frankfurter API)")
    parser.add_argument("-b", "--base", default="USD",
                        help="基准货币 (默认: USD)")
    parser.add_argument("-t", "--targets", default=DEFAULT_TARGETS,
                        help=f"目标货币，逗号分隔 (默认: {DEFAULT_TARGETS})")
    parser.add_argument("-a", "--amount", type=float, default=None,
                        help="换算金额 (不指定则只显示汇率)")
    parser.add_argument("--history", nargs=2, metavar=("START", "END"),
                        help="查询历史汇率，格式: YYYY-MM-DD YYYY-MM-DD")
    parser.add_argument("--list", action="store_true",
                        help="列出所有支持的货币")
    return parser.parse_args(argv)


def api_request(path):
    """发送 API 请求并返回 JSON 数据"""
    url = f"{API_BASE}/{path}"
    req = urllib.request.Request(url, headers={"User-Agent": "ToolBoxPro/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        print(f"\nAPI 错误: HTTP {e.code}")
        if e.code == 422:
            print("  可能原因: 不支持的货币代码")
        sys.exit(1)
    except urllib.error.URLError as e:
        print(f"\n网络错误: {e.reason}")
        print("  请检查网络连接")
        sys.exit(1)


def list_currencies():
    """列出所有支持的货币"""
    data = api_request("currencies")
    print(f"\n支持的货币 (共 {len(data)} 种):")
    print(f"{'='*50}")
    for code, name in sorted(data.items()):
        print(f"  {code}  {name}")


def query_latest(base, targets, amount=None):
    """查询最新汇率"""
    path = f"latest?base={base}&symbols={targets}"
    data = api_request(path)

    print(f"\n最新汇率 (基准: {data.get('base', base)})")
    print(f"日期: {data.get('date', 'N/A')}")
    print(f"{'='*50}")

    rates = data.get("rates", {})
    if not rates:
        print("  (无数据)")
        return rates

    for currency, rate in sorted(rates.items()):
        line = f"  {base}/{currency}: {rate}"
        if amount is not None:
            converted = amount * rate
            line += f"    |  {amount:,.2f} {base} = {converted:,.2f} {currency}"
        print(line)

    return rates


def query_history(base, targets, start_date, end_date):
    """查询历史汇率"""
    path = f"{start_date}..{end_date}?base={base}&symbols={targets}"
    data = api_request(path)

    print(f"\n历史汇率 (基准: {data.get('base', base)})")
    print(f"期间: {data.get('start_date', start_date)} ~ {data.get('end_date', end_date)}")
    print(f"{'='*50}")

    rates = data.get("rates", {})
    if not rates:
        print("  (无数据)")
        return rates

    for date in sorted(rates.keys()):
        print(f"\n  [{date}]")
        for currency, rate in sorted(rates[date].items()):
            print(f"    {base}/{currency}: {rate}")

    return rates


def main(argv=None):
    args = parse_args(argv)

    print(f"\n外汇汇率查询工具 (Frankfurter API)")
    print(f"数据来源: 欧洲央行 (ECB)")

    if args.list:
        list_currencies()
    elif args.history:
        query_history(args.base, args.targets, args.history[0], args.history[1])
    else:
        query_latest(args.base, args.targets, args.amount)

    print(f"\n{'='*50}")
    print("  查询完成")
    print(f"{'='*50}\n")


if __name__ == "__main__":
    main()
