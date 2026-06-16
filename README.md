# IPO Performance Tracker + GenAI Sentiment Diagnostics

A project built during my analytics internship at Indiabulls Securities. Tracks the performance of 30 recent Indian IPOs (2024-2025) using advanced SQL, then layers in an AI-driven sentiment analysis experiment to test whether public IPO review sentiment can predict actual returns.

## Project Overview

This project answers two questions:

1. How have recent Indian IPOs performed across sectors, and what patterns show up in the data?
2. Can an AI sentiment model, applied to public IPO review text, predict whether an IPO will perform well?

## Data

30 mainboard IPOs listed in 2024-2025, spanning 13 sectors, sourced from Chittorgarh, Moneycontrol, Business Standard, and NSE via GoogleFinance for live pricing.

Fields tracked: company name, sector, issue price, issue size, listing date, listing close, listing gain %, current price, current gain %, and a performance tier (Blockbuster / Strong / Moderate / Weak / Disaster).

## Database Schema

Three linked SQLite tables, joined on `ipo_id`:

- **ipo_master** — company_name, sector, issue_price, issue_size_cr, listing_date
- **ipo_performance** — listing_close, listing_gain_pct, current_price, current_gain_pct, performance_category
- **ipo_sentiment / ipo_net_sentiment** — sentiment_label, sentiment_score, net_sentiment_score

## SQL Techniques Used

All queries are in [`sql/queries.sql`](sql/queries.sql), covering:

- Joins and CTEs to compute sector-level outperformer detection (alpha vs sector average)
- Window functions (`RANK()`, `AVG() OVER (PARTITION BY sector)`) for sector rankings
- Anti-joins (`LEFT JOIN` + `IS NULL`) to isolate underperforming IPOs
- Self-joins for pairwise comparison of IPOs within the same sector
- CASE/IF logic for performance tier classification
- Multi-CTE chains for a sector-level summary report with dynamic ranking tags

## GenAI Sentiment Layer

The core experiment: can FinBERT (a finance-tuned sentiment model) read public IPO review text and predict whether the IPO will perform well?

**Baseline approach:** Score each company's full review summary (strengths and risks blended into one paragraph) in a single pass.

**Result:** 36.67% accuracy — worse than random chance (50%). The model systematically classified almost everything as negative, because virtually every IPO review legitimately mentions real risk factors, and FinBERT over-weights risk vocabulary regardless of overall company quality.

**Improved approach:** Decompose each summary into a strength-only sentence and a risk-only sentence, score each independently, then compute a net signed score (strength score minus risk score).

**Result:** 56.67% accuracy — a 20 percentage point improvement, beating random chance. More notably, the net sentiment score showed a clean, monotonic relationship with actual returns: IPOs in the lowest sentiment tercile averaged -17.6% returns, the middle tercile averaged +8.7%, and the highest tercile averaged +52.2%.

## Key Findings

1. Average current gain across all 30 IPOs varies sharply by sector — Telecom and Power led, Construction and Services lagged.
2. Off-the-shelf sentiment models, applied naively to risk-disclosure-heavy text, can perform worse than random chance.
3. Decomposing strength language from risk language before scoring is a simple, effective fix that meaningfully improves predictive accuracy.
4. The magnitude of net sentiment carries a real, usable signal even when the raw positive/negative label does not.

## Limitations

- Small sample size (30 companies); tercile groups of 10 are sensitive to outliers
- Only one base model (FinBERT) tested
- Strength/risk sentences were manually written from source articles, not auto-extracted from full prospectuses
- 56.67% accuracy is a meaningful improvement but not yet production-grade

## Next Steps

- Auto-extract Risk Factor sections directly from SEBI DRHP/RHP filings
- Compare FinBERT against a general-purpose sentiment model and a custom fine-tuned classifier
- Expand the sample to 100+ IPOs as the 2025-26 listing season progresses
- Apply the same SQL framework to the Nifty 50 Momentum Strategy and Pairs Trading projects

## Repo Structure

```
ipo-tracker-genai/
├── README.md
├── data/
│   └── ipo_tracker_data.csv          # Full 30-IPO dataset export
├── sql/
│   └── queries.sql                    # All SQL queries, commented
├── notebook/
│   └── ipo_sentiment_analysis.ipynb   # Colab notebook: FinBERT scoring + SQL pipeline
└── deck/
    └── IPO_Tracker_Deck.pptx          # Summary presentation
```

## Tools Used

Google Sheets (GoogleFinance for live pricing), Python (pandas, transformers/FinBERT), SQLite, and Google Colab.

---
*Aarav — Intern, Indiabulls Securities*
