"""Relève les chiffres du compte rendu séance 3 (Cloud Monitoring + file de messages morts).

Usage : python3 docs/seance-3/metrics.py [minutes]   (fenêtre = les N dernières minutes, 30 par défaut)
"""
import base64, datetime as dt, json, subprocess, sys, urllib.parse, urllib.request

P, TEAM = "advanced-cloud-ai", "team-really-cool"
SUB, DEAD, SVC = f"{TEAM}-tx-push", f"{TEAM}-tx-dead-pull", f"{TEAM}-fraud-api"

minutes = int(sys.argv[1]) if len(sys.argv) > 1 else 30
end = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
start = end - dt.timedelta(minutes=minutes)
iso = lambda t: t.strftime("%Y-%m-%dT%H:%M:%SZ")
token = subprocess.check_output(["gcloud", "auth", "print-access-token"], text=True).strip()


def query(metric, res, aligner, reducer=None, period=60):
    """Renvoie {instant: valeur} pour une série agrégée."""
    params = {
        "filter": f'metric.type="{metric}" AND {res}',
        "interval.startTime": iso(start), "interval.endTime": iso(end),
        "aggregation.alignmentPeriod": f"{period}s", "aggregation.perSeriesAligner": aligner,
    }
    if reducer:
        params["aggregation.crossSeriesReducer"] = reducer
    url = f"https://monitoring.googleapis.com/v3/projects/{P}/timeSeries?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    out = {}
    for ts in json.load(urllib.request.urlopen(req)).get("timeSeries", []):
        for p in ts["points"]:
            v = p["value"]
            val = float(v.get("int64Value", v.get("doubleValue", 0)))
            k = p["interval"]["endTime"]
            out[k] = out.get(k, 0) + val
    return out


sub = f'resource.labels.subscription_id="{SUB}"'
topic = 'resource.labels.topic_id="ff-replay"'
run = f'resource.labels.service_name="{SVC}"'

cols = {
    "publié/s": query("pubsub.googleapis.com/topic/send_message_operation_count", topic, "ALIGN_RATE", "REDUCE_SUM"),
    "livré ok/s": query("pubsub.googleapis.com/subscription/push_request_count",
                        sub + ' AND metric.labels.response_class="ack"', "ALIGN_RATE", "REDUCE_SUM"),
    "en attente": query("pubsub.googleapis.com/subscription/num_undelivered_messages", sub, "ALIGN_MAX", "REDUCE_SUM"),
    "âge max (s)": query("pubsub.googleapis.com/subscription/oldest_unacked_message_age", sub, "ALIGN_MAX", "REDUCE_MAX"),
    "instances": query("run.googleapis.com/container/instance_count", run, "ALIGN_MAX", "REDUCE_SUM"),
    "p50 (ms)": query("run.googleapis.com/request_latencies", run, "ALIGN_DELTA", "REDUCE_PERCENTILE_50"),
    "p99 (ms)": query("run.googleapis.com/request_latencies", run, "ALIGN_DELTA", "REDUCE_PERCENTILE_99"),
}

print(f"Fenêtre {iso(start)} → {iso(end)} (UTC), minute par minute\n")
print(f"{'minute':8}" + "".join(f"{c:>13}" for c in cols))
for k in sorted(set().union(*cols.values())):
    print(f"{k[11:16]:8}" + "".join(f"{cols[c][k]:>13.1f}" if k in cols[c] else f"{'-':>13}" for c in cols))

span = minutes * 60
p50 = query("run.googleapis.com/request_latencies", run, "ALIGN_DELTA", "REDUCE_PERCENTILE_50", span)
p99 = query("run.googleapis.com/request_latencies", run, "ALIGN_DELTA", "REDUCE_PERCENTILE_99", span)
mx = lambda c: max(cols[c].values(), default=0)
print(f"\nMax en attente : {mx('en attente'):.0f}   âge max : {mx('âge max (s)'):.0f} s   "
      f"instances au pic : {mx('instances'):.0f} (max 3)   publié max : {mx('publié/s'):.0f}/s   "
      f"livré max : {mx('livré ok/s'):.0f}/s")
print(f"Latence sur la fenêtre : p50 {max(p50.values(), default=0):.0f} ms, p99 {max(p99.values(), default=0):.0f} ms")

# File de messages morts : lecture sans acquittement, le message reste disponible.
print("\nFile de messages morts :")
msgs = json.loads(subprocess.check_output(
    ["gcloud", "pubsub", "subscriptions", "pull", DEAD, "--project", P, "--limit", "10", "--format", "json"], text=True))
for m in msgs:
    msg = m["message"]
    try:
        tx_id = json.loads(base64.b64decode(msg.get("data", ""))).get("TX_ID")
    except (ValueError, AttributeError):
        tx_id = "(données illisibles)"
    # premier rejet journalisé par le service, pour mesurer le délai jusqu'à la file
    first = subprocess.run(
        ["gcloud", "logging", "read", f'resource.labels.service_name="{SVC}" AND jsonPayload.message="rejected" '
         f'AND jsonPayload.tx_id="{tx_id}"', "--project", P, "--order", "asc", "--limit", "1",
         "--freshness", "1d", "--format", "value(timestamp)"], capture_output=True, text=True).stdout.strip()
    print(f"  tx_id={tx_id}  arrivé dans la file : {msg['publishTime']}  premier rejet : {first or '?'}  "
          f"tentatives : {msg.get('attributes', {}).get('CloudPubSubDeadLetterSourceDeliveryCount', '?')}")
if not msgs:
    print("  vide (le message met 1 à 3 min à arriver : 5 tentatives, 10 à 60 s d'attente)")
