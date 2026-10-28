SELECT SUM(q) AS result FROM (SELECT t."Stop:Departure delay" AS q,
ROW_NUMBER() OVER (PARTITION BY t."Stop:Station code"
ORDER BY t."Stop:Arrival delay" * 10000000 + t.rowid DESC) AS rn FROM train_stops AS t
WHERE t."Stop:Arrival delay" IS NOT NULL) WHERE rn <= 3;
