-- ============================================================
-- IPO Performance Tracker + GenAI Sentiment Diagnostics
-- SQL Queries
-- Database: SQLite
-- Tables: ipo_master, ipo_performance, ipo_sentiment, ipo_net_sentiment
-- ============================================================


-- ============================================================
-- Query 1: Performance Categorization with JOIN + CASE WHEN
-- Joins company info with performance data and tags each IPO
-- into a tier based on its current gain percentage.
-- ============================================================
SELECT m.company_name, m.sector, p.current_gain_pct,
CASE 
    WHEN p.current_gain_pct > 50 THEN 'Blockbuster'
    WHEN p.current_gain_pct >= 20 THEN 'Strong'
    WHEN p.current_gain_pct >= 0 THEN 'Moderate'
    WHEN p.current_gain_pct >= -20 THEN 'Weak'
    ELSE 'Disaster'
END AS category
FROM ipo_master m
JOIN ipo_performance p ON m.ipo_id = p.ipo_id
ORDER BY p.current_gain_pct DESC;


-- ============================================================
-- Query 2: Window Functions - Rank IPOs Within Each Sector
-- Uses RANK() and AVG() with PARTITION BY to rank each company
-- within its own sector and show the sector's average gain
-- alongside it, without collapsing rows like GROUP BY would.
-- ============================================================
SELECT m.company_name, m.sector, p.current_gain_pct,
RANK() OVER (PARTITION BY m.sector ORDER BY p.current_gain_pct DESC) AS sector_rank,
ROUND(AVG(p.current_gain_pct) OVER (PARTITION BY m.sector), 2) AS sector_avg_gain
FROM ipo_master m
JOIN ipo_performance p ON m.ipo_id = p.ipo_id
ORDER BY m.sector, sector_rank;


-- ============================================================
-- Query 3: CTE - Find IPOs That Beat Their Sector Average
-- Calculates each sector's average gain in a CTE, then joins
-- back to find IPOs whose gain exceeds their own sector's
-- average ("alpha" - excess return vs sector peers).
-- ============================================================
WITH sector_avg AS (
    SELECT m.sector, AVG(p.current_gain_pct) AS avg_gain
    FROM ipo_master m
    JOIN ipo_performance p ON m.ipo_id = p.ipo_id
    GROUP BY m.sector
)
SELECT m.company_name, m.sector, p.current_gain_pct, 
       ROUND(s.avg_gain, 2) AS sector_avg,
       ROUND(p.current_gain_pct - s.avg_gain, 2) AS alpha
FROM ipo_master m
JOIN ipo_performance p ON m.ipo_id = p.ipo_id
JOIN sector_avg s ON m.sector = s.sector
WHERE p.current_gain_pct > s.avg_gain
ORDER BY alpha DESC;


-- ============================================================
-- Query 4: Anti-Join - Find Underperforming IPOs
-- Uses a CTE to first identify "outperformer" IPOs (those above
-- their sector average), then LEFT JOINs back to the full table
-- and filters for IS NULL - i.e. companies with NO match in the
-- outperformers list. This is the anti-join pattern: it returns
-- rows from ipo_master that have no corresponding match in the
-- outperformers CTE.
-- ============================================================
WITH outperformers AS (
    SELECT m.ipo_id
    FROM ipo_master m
    JOIN ipo_performance p ON m.ipo_id = p.ipo_id
    JOIN (
        SELECT sector, AVG(current_gain_pct) AS avg_gain
        FROM ipo_master m2
        JOIN ipo_performance p2 ON m2.ipo_id = p2.ipo_id
        GROUP BY sector
    ) s ON m.sector = s.sector
    WHERE p.current_gain_pct > s.avg_gain
)
SELECT m.company_name, m.sector, p.current_gain_pct, p.performance_category
FROM ipo_master m
JOIN ipo_performance p ON m.ipo_id = p.ipo_id
LEFT JOIN outperformers o ON m.ipo_id = o.ipo_id
WHERE o.ipo_id IS NULL
ORDER BY p.current_gain_pct ASC;


-- ============================================================
-- Query 5: Listing Gain vs Current Gain - Momentum Check
-- Compares each IPO's listing-day gain against its current gain
-- to flag whether the stock kept rising after listing or cooled
-- off from its initial pop.
-- ============================================================
SELECT m.company_name, m.sector,
       p.listing_gain_pct,
       p.current_gain_pct,
       ROUND(p.current_gain_pct - p.listing_gain_pct, 2) AS change_since_listing,
       CASE
           WHEN p.current_gain_pct > p.listing_gain_pct THEN 'Gained Further'
           WHEN p.current_gain_pct < p.listing_gain_pct THEN 'Cooled Down'
           ELSE 'No Change'
       END AS trend
FROM ipo_master m
JOIN ipo_performance p ON m.ipo_id = p.ipo_id
ORDER BY change_since_listing DESC;


-- ============================================================
-- Query 6: Multi-CTE Sector Summary Report
-- Chains two CTEs together: the first computes per-sector stats
-- (count, avg/best/worst gain), the second ranks all sectors
-- against each other and tags the top 3 and bottom 3 using a
-- correlated subquery inside CASE WHEN.
-- ============================================================
WITH sector_stats AS (
    SELECT m.sector, 
           COUNT(*) AS total_ipos,
           ROUND(AVG(p.current_gain_pct), 2) AS avg_gain,
           ROUND(MAX(p.current_gain_pct), 2) AS best_gain,
           ROUND(MIN(p.current_gain_pct), 2) AS worst_gain
    FROM ipo_master m
    JOIN ipo_performance p ON m.ipo_id = p.ipo_id
    GROUP BY m.sector
),
ranked_sectors AS (
    SELECT *,
    RANK() OVER (ORDER BY avg_gain DESC) AS sector_rank
    FROM sector_stats
)
SELECT sector, total_ipos, avg_gain, best_gain, worst_gain,
       sector_rank,
       CASE 
           WHEN sector_rank <= 3 THEN 'Top Performing Sector'
           WHEN sector_rank > (SELECT COUNT(*) FROM sector_stats) - 3 THEN 'Bottom Performing Sector'
           ELSE 'Mid-Range'
       END AS sector_tag
FROM ranked_sectors
ORDER BY sector_rank;


-- ============================================================
-- Query 7: Self-Join - Pairwise Comparison Within Sector
-- Uses a CTE to avoid repeating the same JOIN twice, then
-- self-joins the CTE to itself (aliased a and b) to compare
-- every IPO against every other IPO in the same sector.
-- The condition a.ipo_id < b.ipo_id avoids duplicate pairs
-- (A-vs-B and B-vs-A) and self-comparison (A-vs-A).
-- ============================================================
WITH ipo_data AS (
    SELECT m.ipo_id, m.company_name, m.sector, p.current_gain_pct
    FROM ipo_master m 
    JOIN ipo_performance p ON m.ipo_id = p.ipo_id
)
SELECT a.company_name AS company_a, 
       b.company_name AS company_b,
       a.sector,
       a.current_gain_pct AS gain_a,
       b.current_gain_pct AS gain_b,
       ROUND(a.current_gain_pct - b.current_gain_pct, 2) AS gain_diff
FROM ipo_data a
JOIN ipo_data b
ON a.sector = b.sector AND a.ipo_id < b.ipo_id
ORDER BY a.sector, gain_diff DESC;


-- ============================================================
-- Query 8: Sentiment Accuracy Check (Baseline FinBERT)
-- Joins the baseline single-paragraph FinBERT sentiment table
-- to actual returns, and tags each prediction as Matched or
-- Mismatched based on whether the sentiment direction agreed
-- with the actual return direction.
-- ============================================================
SELECT m.company_name, m.sector,
       s.sentiment_label, s.sentiment_score,
       p.current_gain_pct,
       CASE
           WHEN s.sentiment_label = 'positive' AND p.current_gain_pct > 0 THEN 'Sentiment Matched'
           WHEN s.sentiment_label = 'negative' AND p.current_gain_pct < 0 THEN 'Sentiment Matched'
           ELSE 'Sentiment Mismatched'
       END AS accuracy_check
FROM ipo_master m
JOIN ipo_performance p ON m.ipo_id = p.ipo_id
JOIN ipo_sentiment s ON m.ipo_id = s.ipo_id
ORDER BY s.sentiment_score DESC;


-- ============================================================
-- Query 9: Accuracy Summary - Baseline Model
-- Uses a CTE to classify Matched/Mismatched, then a scalar
-- subquery to compute each group's count as a percentage
-- of the total. Result: 36.67% accuracy (worse than random).
-- ============================================================
WITH accuracy_calc AS (
    SELECT m.ipo_id,
    CASE
        WHEN s.sentiment_label = 'positive' AND p.current_gain_pct > 0 THEN 'Sentiment Matched'
        WHEN s.sentiment_label = 'negative' AND p.current_gain_pct < 0 THEN 'Sentiment Matched'
        ELSE 'Sentiment Mismatched'
    END AS accuracy_check
    FROM ipo_master m
    JOIN ipo_performance p ON m.ipo_id = p.ipo_id
    JOIN ipo_sentiment s ON m.ipo_id = s.ipo_id
)
SELECT 
    accuracy_check,
    COUNT(*) AS count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM accuracy_calc), 2) AS pct_of_total
FROM accuracy_calc
GROUP BY accuracy_check;


-- ============================================================
-- Query 10: Tercile Analysis - Baseline Model
-- Uses NTILE(3) to split IPOs into three equal groups by raw
-- FinBERT confidence score, then checks the average actual
-- return per tercile. (Run the .groupby('score_tercile').mean()
-- step in pandas after pulling this into a dataframe.)
-- ============================================================
SELECT m.company_name, s.sentiment_score, p.current_gain_pct,
       NTILE(3) OVER (ORDER BY s.sentiment_score) AS score_tercile
FROM ipo_master m
JOIN ipo_performance p ON m.ipo_id = p.ipo_id
JOIN ipo_sentiment s ON m.ipo_id = s.ipo_id;


-- ============================================================
-- Query 11: Sentiment Accuracy Check (Improved Net Model)
-- Same structure as Query 8, but uses ipo_net_sentiment (the
-- strength-minus-risk decomposed score) instead of the single-
-- paragraph baseline score.
-- ============================================================
SELECT m.company_name, m.sector,
       n.net_label, n.net_sentiment_score,
       p.current_gain_pct,
       CASE
           WHEN n.net_label = 'positive' AND p.current_gain_pct > 0 THEN 'Sentiment Matched'
           WHEN n.net_label = 'negative' AND p.current_gain_pct < 0 THEN 'Sentiment Matched'
           ELSE 'Sentiment Mismatched'
       END AS accuracy_check
FROM ipo_master m
JOIN ipo_performance p ON m.ipo_id = p.ipo_id
JOIN ipo_net_sentiment n ON m.ipo_id = n.ipo_id
ORDER BY n.net_sentiment_score DESC;


-- ============================================================
-- Query 12: Accuracy Summary - Improved Net Model
-- Same logic as Query 9, pointed at ipo_net_sentiment.
-- Result: 56.67% accuracy, a 20-point improvement over baseline.
-- ============================================================
WITH accuracy_calc_v2 AS (
    SELECT m.ipo_id,
    CASE
        WHEN n.net_label = 'positive' AND p.current_gain_pct > 0 THEN 'Sentiment Matched'
        WHEN n.net_label = 'negative' AND p.current_gain_pct < 0 THEN 'Sentiment Matched'
        ELSE 'Sentiment Mismatched'
    END AS accuracy_check
    FROM ipo_master m
    JOIN ipo_performance p ON m.ipo_id = p.ipo_id
    JOIN ipo_net_sentiment n ON m.ipo_id = n.ipo_id
)
SELECT 
    accuracy_check,
    COUNT(*) AS count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM accuracy_calc_v2), 2) AS pct_of_total
FROM accuracy_calc_v2
GROUP BY accuracy_check;


-- ============================================================
-- Query 13: Tercile Analysis - Improved Net Model
-- Same NTILE(3) approach as Query 10, but on the signed net
-- sentiment score. Result: a clean, monotonic relationship
-- between sentiment tercile and actual return (-17.6% / +8.7%
-- / +52.2% across the three terciles), unlike the inverted,
-- harder-to-explain pattern from the baseline model.
-- ============================================================
SELECT m.company_name, n.net_sentiment_score, p.current_gain_pct,
       NTILE(3) OVER (ORDER BY n.net_sentiment_score) AS score_tercile
FROM ipo_master m
JOIN ipo_performance p ON m.ipo_id = p.ipo_id
JOIN ipo_net_sentiment n ON m.ipo_id = n.ipo_id;
