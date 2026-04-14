"""
ToolBox Pro - FXCM ForexConnect API Demo Script
用法: python demo.py -l 用户名 -p 密码 -c Demo|Real
"""

import argparse
import sys

try:
    from forexconnect import ForexConnect
except ImportError:
    print("请先安装 forexconnect: pip install forexconnect")
    sys.exit(1)


def parse_args():
    parser = argparse.ArgumentParser(description="FXCM 账户信息查询工具")
    parser.add_argument("-l", "--login", required=True, help="FXCM 用户名")
    parser.add_argument("-p", "--password", required=True, help="FXCM 密码")
    parser.add_argument("-c", "--connection", default="Demo",
                        choices=["Demo", "Real"], help="连接类型 (默认: Demo)")
    parser.add_argument("-u", "--url", default="http://www.fxcorporate.com/Hosts.jsp",
                        help="服务器 URL")
    return parser.parse_args()


def session_status_changed(session, status):
    print(f"  [状态] {status}")


def query_accounts(fx):
    print("\n{'='*40}")
    print("  账户信息")
    print("{'='*40}")
    accounts = fx.get_table_reader(ForexConnect.ACCOUNTS)
    count = 0
    for account in accounts:
        count += 1
        print(f"  账户ID:      {account.account_id}")
        try:
            print(f"  余额:        {account.balance}")
        except AttributeError:
            pass
        try:
            print(f"  净值:        {account.equity}")
        except AttributeError:
            pass
        try:
            print(f"  已用保证金:  {account.used_margin}")
        except AttributeError:
            pass
        try:
            print(f"  可用保证金:  {account.usable_margin}")
        except AttributeError:
            pass
        try:
            print(f"  日盈亏:      {account.day_pl}")
        except AttributeError:
            pass
        try:
            print(f"  总盈亏:      {account.gross_pl}")
        except AttributeError:
            pass
        print("  ---")
    if count == 0:
        print("  (无账户数据)")
    return count


def query_trades(fx):
    print(f"\n{'='*40}")
    print("  持仓信息")
    print(f"{'='*40}")
    trades = fx.get_table_reader(ForexConnect.TRADES)
    count = 0
    for trade in trades:
        count += 1
        try:
            print(f"  交易ID:  {trade.trade_id}")
        except AttributeError:
            pass
        try:
            print(f"  币对:    {trade.instrument}")
        except AttributeError:
            pass
        try:
            print(f"  方向:    {trade.buy_sell}")
        except AttributeError:
            pass
        try:
            print(f"  手数:    {trade.amount}")
        except AttributeError:
            pass
        try:
            print(f"  开仓价:  {trade.open_rate}")
        except AttributeError:
            pass
        try:
            print(f"  盈亏:    {trade.gross_pl}")
        except AttributeError:
            pass
        print("  ---")
    if count == 0:
        print("  (无持仓)")
    return count


def query_orders(fx):
    print(f"\n{'='*40}")
    print("  挂单信息")
    print(f"{'='*40}")
    try:
        orders = fx.get_table_reader(ForexConnect.ORDERS)
        count = 0
        for order in orders:
            count += 1
            try:
                print(f"  订单ID:  {order.order_id}")
                print(f"  币对:    {order.instrument}")
                print(f"  类型:    {order.type}")
                print(f"  状态:    {order.status}")
            except AttributeError:
                pass
            print("  ---")
        if count == 0:
            print("  (无挂单)")
    except Exception as e:
        print(f"  查询挂单失败: {e}")


def main():
    args = parse_args()

    print(f"\nFXCM ForexConnect Demo")
    print(f"连接类型: {args.connection}")
    print(f"服务器:   {args.url}")
    print(f"用户:     {args.login}")
    print(f"正在连接...")

    with ForexConnect() as fx:
        try:
            fx.login(
                args.login,
                args.password,
                args.url,
                args.connection,
                "",  # session_id
                "",  # pin
                session_status_changed
            )
            print("登录成功!\n")

            query_accounts(fx)
            query_trades(fx)
            query_orders(fx)

            print(f"\n{'='*40}")
            print("  查询完成")
            print(f"{'='*40}")

        except Exception as e:
            print(f"\n错误: {e}")
            sys.exit(1)
        finally:
            try:
                fx.logout()
                print("\n已登出。")
            except Exception:
                pass


if __name__ == "__main__":
    main()
