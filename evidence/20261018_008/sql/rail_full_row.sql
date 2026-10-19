-- C17 diagnostic adaptation of licensed real rail data; not a source-authentic production SQL.
SELECT "Stop:Station code",
       unnest(max_by(t, "Stop:Arrival delay", 3)) AS delayed_stop
FROM train_stops AS t
WHERE "Stop:Arrival delay" IS NOT NULL
GROUP BY "Stop:Station code";
