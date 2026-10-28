SELECT SUM(list_sum(list_transform(topk, lambda x: x.dep_delay))) AS result
FROM (SELECT arg_max(struct_pack(dep_delay := t."Stop:Departure delay", station_name := t."Stop:Station name", platform := t."Stop:Actual platform", service_date := t."Service:Date", train_id := t."Service:RDT-ID", train_type := t."Service:Type", company := t."Service:Company", arrival_time := t."Stop:Arrival time", departure_time := t."Stop:Departure time"), t."Stop:Arrival delay" * 10000000 + t.rowid, 3) AS topk
FROM train_stops AS t WHERE t."Stop:Arrival delay" IS NOT NULL
GROUP BY t."Stop:Station code");
