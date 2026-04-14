"""
ToolBox Pro - FXCM REST API Demo Script (基于 fxcmpy)
用法: python demo.py -t YOUR_ACCESS_TOKEN -s demo|real

安装依赖: pip install fxcmpy
获取 Access Token:
  1. 注册 FXCM Demo 账户: https://www.fxcm.com/uk/forex-trading-demo/
  2. 登录 Trading Station Web: https://tradingstation.fxcm.com/
  3. 点击 User Account → Token Management → 生成 Token
  4. Demo 账户默认已开通 REST API;
     Live 账户需发邮件至 api@fxcm.com 申请开通
"""

import argparse
import sys

try:
    import fxcmpy
except ImportError:
    print("请先安装 fxcmpy: pip install fxcmpy")
    sys.exit(1)


def parse_args():
    parser = argparse.ArgumentParser(description="FXCM 账户信息查询工具")
    parser.add_argument("-t", "--token", required=True,
                        help="FXCM Access Token (从 Trading Station 获取)")
    parser.add_argument("-s", "--server", default="demo",
                        choices=["demo", "real"], help="服务器类型 (默认: demo)")
    return parser.parse_args()


def query_accounts(con):
    print(f"\n{'='*40}")
    print("  账户信息")
    print(f"{'='*40}")
    accounts = con.get_accounts()
    if accounts.empty:
        print("  (无账户数据)")
        return 0
    for _, row in accounts.iterrows():
        print(f"  账户ID:      {row.get('accountId', 'N/A')}")
        print(f"  余额:        {row.get('balance', 'N/A')}")
        print(f"  净值:        {row.get('equity', 'N/A')}")
        print(f"  已用保证金:  {row.get('usableMargin', 'N/A')}")
        print(f"  日盈亏:      {row.get('dayPL', 'N/A')}")
        print(f"  总盈亏:      {row.get('grossPL', 'N/A')}")
        print("  ---")
    return len(accounts)


def query_trades(con):
    print(f"\n{'='*40}")
    print("  持仓信息")
    print(f"{'='*40}")
    trades = con.get_open_positions()
    if trades.empty:
        print("  (无持仓)")
        return 0
    for _, row in trades.iterrows():
        print(f"  交易ID:  {row.get('tradeId', 'N/A')}")
        print(f"  币对:    {row.get('currency', 'N/A')}")
        print(f"  方向:    {row.get('isBuy', 'N/A')}")
        print(f"  手数:    {row.get('amountK', 'N/A')}K")
        print(f"  开仓价:  {row.get('open', 'N/A')}")
        print(f"  盈亏:    {row.get('grossPL', 'N/A')}")
        print("  ---")
    return len(trades)


def query_orders(con):
    print(f"\n{'='*40}")
    print("  挂单信息")
    print(f"{'='*40}")
    try:
        orders = con.get_orders()
        if orders.empty:
            print("  (无挂单)")
            return 0
        for _, row in orders.iterrows():
            print(f"  订单ID:  {row.get('orderId', 'N/A')}")
            print(f"  币对:    {row.get('currency', 'N/A')}")
            print(f"  类型:    {row.get('type', 'N/A')}")
            print(f"  状态:    {row.get('status', 'N/A')}")
            print("  ---")
        return len(orders)
    except Exception as e:
        print(f"  查询挂单失败: {e}")
        return 0


def main():
    args = parse_args()

    print(f"\nFXCM REST API Demo (fxcmpy)")
    print(f"服务器: {args.server}")
    print(f"正在连接...")

    try:
        con = fxcmpy.fxcmpy(access_token=args.token, server=args.server)
        print("登录成功!\n")

        query_accounts(con)
        query_trades(con)
        query_orders(con)

        print(f"\n{'='*40}")
        print("  查询完成")
        print(f"{'='*40}")

    except Exception as e:
        print(f"\n错误: {e}")
        sys.exit(1)
    finally:
        try:
            con.close()
            print("\n已断开连接。")
        except Exception:
            pass


if __name__ == "__main__":
    main()
