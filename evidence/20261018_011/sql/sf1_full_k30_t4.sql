-- Unique tie-breaker makes cross-binary parallel result comparison meaningful.
SELECT l_suppkey,
       unnest(max_by(lineitem,
           date_diff('day', DATE '1992-01-01', l_shipdate)::BIGINT * 1000000000
           + l_orderkey * 10 + l_linenumber, 30)) AS row
FROM lineitem GROUP BY l_suppkey;
