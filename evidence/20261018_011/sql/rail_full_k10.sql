-- Research adaptation of public rail records, not an independently authored production query.
SELECT "Stop:Station code", unnest(max_by(t, "Stop:Arrival delay", 10)) AS delayed_stop
FROM train_stops AS t
WHERE "Stop:Arrival delay" IS NOT NULL
GROUP BY "Stop:Station code";
