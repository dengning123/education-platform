# Capibara Summer Trading Toolkit

进攻冲冠军版工具包：美股动量筛选、组合净值/回撤跟踪、周报自动草稿。

比赛设定：eToro 模拟盘 $100k · 美股主战场 · 期末总资产排名。

## Education platform database

The isolated Supabase/PostgreSQL education-planning backend is in
[`education-platform/`](education-platform/README.md). It does not modify the
trading toolkit.

## 快速开始

```bash
cd ~/capibara-summer-trading
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 1) 动量选股（找本周进攻标的）

```bash
python scripts/screen_momentum.py
python scripts/screen_momentum.py --top 20 --min-r21 0.03
python scripts/screen_momentum.py --demo   # 离线演示/检查脚本
```

结果会打印 Top 股票，并保存到 `data/screener_latest.csv`。

### 2) 更新并查看组合净值 / 最大回撤

每天把 eToro 账户总资产记入 `data/portfolio_history.csv`，或：

```bash
python scripts/track_portfolio.py --append 2026-07-16 102500 --cash 20000 --notes "held NVDA AVGO"
python scripts/track_portfolio.py
```

成交明细写入 `data/trades.csv`（字段见示例文件）。

首次建仓可以用 AI 半导体初始化脚本生成成交和持仓快照：

```bash
cp data/fill_prices.example.csv data/fill_prices.csv
# 填入 eToro 的实际成交价后运行
python scripts/record_initial_portfolio.py --prices data/fill_prices.csv --overwrite
```

如果不传 `--prices`，脚本会尝试用 Yahoo Finance 最新复权收盘价做参考价。

### 3) 下载股市数据表格（CSV）

```bash
# 下载当前持仓行情，生成表格
python scripts/download_market_data.py --portfolio

# 下载候选池（股票较多，更容易被限流）
python scripts/download_market_data.py --universe --period 3mo

# 指定股票
python scripts/download_market_data.py NVDA AVGO AMD SMH --period 6mo
```

输出目录：`data/market/`
- `latest_snapshot.csv`：每只股票最新价 + 1日/5日/21日涨跌幅（适合直接打开）
- `latest_history.csv`：历史 OHLCV 长表（date, symbol, open, high, low, close, volume）

用 Excel / Numbers / Google Sheets 打开这些 CSV 即可。

### 3b) 接近实时 / 实时报价表

先说清楚：

- `yfinance` **不是真正实时**，通常有延迟
- 更接近实时：注册 [Finnhub](https://finnhub.io/) 免费 key，用 `--source finnhub`
- 交易所级真实时：需要付费行情（Polygon / Alpaca SIP 等）

```bash
# 当前持仓（4 只）
python scripts/live_quotes.py --portfolio --source finnhub --once

# 项目候选池全部（universe_us.csv，约 40 只）
python scripts/live_quotes.py --universe --source finnhub --once

# 先下载美股代码清单，再拉“更多/接近全部”报价（免费版约 60 次/分钟，会较慢）
python scripts/download_us_symbols.py --common-stock-only
python scripts/live_quotes.py --symbols-file data/market/us_symbols.csv --source finnhub --once --sleep 1.05

# 每 30 秒刷新持仓
python scripts/live_quotes.py --portfolio --source finnhub --interval 30
```

输出：
- `data/market/live_quotes.csv`：持仓最新报价
- `data/market/live_quotes_universe.csv`：候选池报价
- `data/market/live_quotes_all.csv`：大批量清单报价
- `data/market/us_symbols.csv`：美股代码清单
- `data/market/live_quotes_log.csv`：刷新历史

说明：真正“全世界所有股票”不现实；免费 API 有次数限制。建议先用 `--universe`，需要更大范围再用 `us_symbols.csv`。

决策前把实时行情和持仓合并：

```bash
python scripts/live_quotes.py --universe --source finnhub --once
python scripts/decision_snapshot.py
```

输出：`data/market/decision_snapshot.xlsx`（含建议动作，再去 eToro 操作）

### 4) 查看股票价格图

```bash
python scripts/plot_prices.py NVDA AVGO AMD SMH
python scripts/plot_prices.py --period 1y       # 默认读取 trades.csv 当前持仓
python scripts/plot_prices.py NVDA AVGO --raw  # 显示原始复权收盘价，不做归一化
```

图片会输出到 `charts/`。

### 5) 期货 / 风险对冲（投资项目核心模块）

```bash
# 专业风控：beta、净敞口、对冲比率、NQ/ES/SMH/QQQ sizing、压力测试
python scripts/hedge_risk.py
python scripts/hedge_risk.py --target-ratio 0.4 --hedge-index smh
python scripts/hedge_risk.py --demo-beta   # 行情限流时用默认 beta

# 简易情景对比（辅助）
python scripts/simulate_hedge.py --move -0.05 --beta 1.2
```

- 输出建议：`data/hedge_recommendation.csv`
- 对冲账本：`data/hedge_book.csv`（理想空头已记录；eToro 模拟盘不可做空）
- 替代方案：`internship_output/platform_constraints_and_alt_hedge.md`
- 框架说明：`trading_plan.md` 第 9 节、`internship_output/futures_hedging_memo.md`

### 6) 生成每周提交日志草稿

```bash
python scripts/generate_weekly_report.py --theme "AI semis momentum"
```

输出：`logs/weekly_YYYY-MM-DD.md`（再手工补全复盘即可提交）。

### 7) 一键刷新 Finnhub 并生成现金投入计划

先在项目根目录创建不会提交到 Git 的 `.env`：

```text
FINNHUB_API_KEY=你的新FinnhubKey
```

然后运行：

```bash
source .venv/bin/activate
python scripts/daily_finnhub_update.py
```

默认按“最终投入全部现金、先投入 60%、确认后投入 40%”生成预算护栏：

- 单一个股不超过账户权益的 30%
- 半导体主题不超过账户权益的 75%
- 只生成研究清单和预算，不会自动在 eToro 下单

输出：

- `data/market/live_quotes_universe.csv`
- `data/market/decision_snapshot.csv` / `.xlsx`
- `data/market/cash_deployment_plan.md`

## 文件说明

| 路径 | 作用 |
|---|---|
| `trading_plan.md` | 进攻冲冠军交易计划（仓位/止损/节奏） |
| `templates/weekly_log.md` | 手写周报模板 |
| `data/universe_us.csv` | 美股候选池（可自行增删） |
| `data/portfolio_targets.csv` | 当前目标配置（AI 半导体开局 + 现金） |
| `data/portfolio_history.csv` | 每日净值 |
| `data/trades.csv` | 成交与论点 |
| `data/positions_snapshot.csv` | 初始化脚本生成的持仓快照 |
| `scripts/screen_momentum.py` | 动量 + 相对 SPY 强度筛选 |
| `scripts/record_initial_portfolio.py` | 按目标仓位记录首次建仓 |
| `scripts/download_market_data.py` | 下载历史/快照行情并导出 CSV |
| `scripts/live_quotes.py` | 近实时/实时报价刷新到 CSV |
| `scripts/decision_snapshot.py` | 持仓 + 实时行情 → 决策 Excel |
| `data/market/` | snapshot / history / live_quotes 表格 |
| `scripts/plot_prices.py` | 生成股票/ETF 历史价格图 |
| `scripts/hedge_risk.py` | 专业对冲风控：beta / 净敞口 / 合约 sizing / 压力测试 |
| `scripts/simulate_hedge.py` | 简易对冲情景对比 |
| `data/hedge_book.csv` | 已执行空头对冲记录 |
| `data/hedge_recommendation.csv` | 最新对冲建议输出 |
| `scripts/track_portfolio.py` | 收益/回撤/持仓快照 |
| `scripts/generate_weekly_report.py` | 周报草稿 |
| `internship_output/` | 实习产出总目录 |
| `internship_output/ai_tools_exploration.md` | **新型 AI 程序探索（必标注展示）** |
| `internship_output/live_data_decision_adjustment.md` | 实时行情 → 决策表 → 调仓（实习核心成果） |

> `data/` 里已放示例数据，方便你先跑通脚本；请改成你自己的真实模拟盘数字。

## 建议工作流（冲冠军）

1. 周一跑筛选 → 选 2–4 只美股形成主题仓  
2. 按 `trading_plan.md` 控制单笔风险与组合熔断  
3. 每日更新净值，周五出周报并提交  

## 注意

- 本工具只做研究与记账，不自动下单到 eToro。  
- 市场数据来自 Yahoo Finance（`yfinance`），可能与 eToro 报价有差异；若被限流，等几分钟重试，或先用 `--demo` 检查流程。  
- 示例成交不构成投资建议；模拟盘仍可能有点差/延迟。
