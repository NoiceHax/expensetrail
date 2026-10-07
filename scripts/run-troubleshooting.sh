#!/usr/bin/env bash
# Final troubleshooting challenge: break the deployed app on purpose, then investigate -> root cause -> fix -> verify.
# Needs the chart installed in namespace "expensetrail" (see README) and the minikube ingress addon.
set -u
NS=expensetrail
URL="http://$(minikube ip)"
HOST="Host: expensetrail.local"
k() { kubectl -n "$NS" "$@"; }
run() { echo "\$ $*"; eval "$@" 2>&1; echo; }
code() { curl -s -m 5 -o /dev/null -w '%{http_code}' -H "$HOST" "$URL$1"; }
api() { echo "\$ curl -s -o /dev/null -w '%{http_code}' -H '$HOST' $URL$1"; code "$1"; echo; echo; }
# poll until the URL returns 200 (the ingress needs a moment to notice endpoint changes)
api_ok() { echo "\$ curl -H '$HOST' $URL$1   # polled until 200 (max 45s)"; for i in $(seq 1 15); do c=$(code "$1"); [ "$c" = 200 ] && break; sleep 3; done; echo "$c (after ~$((i*3))s)"; echo; }
wait_ready() { kubectl -n "$NS" rollout status "deploy/$1" --timeout="${2:-120s}" 2>&1 | tail -1; }
not_ready_pod() { kubectl -n "$NS" get pods -l "app=$1" --no-headers | awk '$2 ~ /^0\//{print $1}' | head -1; }
events() { kubectl -n "$NS" describe pod "$1" | sed -n '/^Events:/,$p'; }

echo "################ BASELINE"
run k get pods
api /api/summary
api /

echo "################ ISSUE 1: wrong image tag (ErrImagePull / ImagePullBackOff)"
run k set image deploy/backend backend=expensetrail-backend:v-does-not-exist
sleep 25
echo "# SYMPTOM: a new pod that never starts; the old pods are untouched"; run k get pods -l app=backend
BAD=$(not_ready_pod backend); echo "# INVESTIGATE the broken pod ($BAD): its events say why"
run "kubectl -n $NS describe pod $BAD | sed -n '/^Events:/,\$p' | cut -c1-170"
echo "# the rolling update kept the old pods serving, so users saw no outage:"; api /api/summary
echo "# ROOT CAUSE: the image tag does not exist. FIX: roll the Deployment back"
run k rollout undo deploy/backend
wait_ready backend; run k get pods -l app=backend
api_ok /api/summary

echo "################ ISSUE 2: wrong database password (pods Running but never Ready)"
OLD=$(k get secret expensetrail-db -o jsonpath='{.data.password}')
BADPW=$(printf 'not-the-real-password' | base64)
echo "\$ kubectl patch secret expensetrail-db -p '{\"data\":{\"password\":\"<wrong password, base64>\"}}'"; k patch secret expensetrail-db -p "{\"data\":{\"password\":\"$BADPW\"}}"; echo
run k rollout restart deploy/backend
sleep 35
echo "# SYMPTOM: READY 0/1 on the new pod, RESTARTS 0 (the process itself is fine)"; run k get pods -l app=backend
BAD=$(not_ready_pod backend); echo "# INVESTIGATE the not-ready pod ($BAD): events"
run "kubectl -n $NS describe pod $BAD | sed -n '/^Events:/,\$p' | cut -c1-170"
echo "# ask THAT pod's app directly (not just any backend pod):"
run "kubectl -n $NS exec $BAD -- python -c \"import urllib.request,urllib.error
try: print(urllib.request.urlopen('http://localhost:8000/ready').status)
except urllib.error.HTTPError as e: print(e.code, e.read().decode())\""
echo "# and test the database login exactly as the app does:"
run "kubectl -n $NS exec $BAD -- python -c \"import os,psycopg2
try:
    psycopg2.connect(os.environ['DATABASE_URL']); print('connected')
except Exception as e: print(str(e).strip())\""
echo "# ROOT CAUSE: the Secret no longer matches the password PostgreSQL was initialised with. FIX: restore the Secret, restart"
echo "\$ kubectl patch secret expensetrail-db -p '{\"data\":{\"password\":\"<original password, base64, not printed>\"}}'"; k patch secret expensetrail-db -p "{\"data\":{\"password\":\"$OLD\"}}"; echo
run k rollout restart deploy/backend
wait_ready backend; run k get pods -l app=backend
api_ok /api/summary

echo "################ ISSUE 3: Service selector typo (no endpoints, ingress returns 503)"
run "k patch svc backend -p '{\"spec\":{\"selector\":{\"app\":\"backend-typo\"}}}'"
sleep 5
echo "# SYMPTOM"; api /api/summary
echo "# INVESTIGATE: the pods are healthy, but the Service has no endpoints"; run k get pods -l app=backend; run k get endpoints backend
run "k describe svc backend | grep -E 'Selector|Endpoints'"
run "k get pods --show-labels -l app=backend | cut -c1-120"
echo "# ROOT CAUSE: selector app=backend-typo matches no Pod labels. FIX: restore the selector"
run "k patch svc backend -p '{\"spec\":{\"selector\":{\"app\":\"backend\"}}}'"
run k get endpoints backend
api_ok /api/summary

echo "################ ISSUE 4: readiness probe pointing at a path that fails (rollout stuck)"
echo "# (my first attempt used /healthz-missing: it PASSED, because nginx's SPA fallback 'try_files \$uri /index.html' serves 200 for"
echo "#  any unknown path. A probe that really fails must go through /api, where the backend returns 404.)"
run "k patch deploy frontend --type=json -p '[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/readinessProbe/httpGet/path\",\"value\":\"/api/does-not-exist\"}]'"
sleep 30
echo "# SYMPTOM: the new pod is 0/1 while the old pods keep serving; the rollout never finishes"; run k get pods -l app=frontend; run k rollout status deploy/frontend --timeout=5s
BAD=$(not_ready_pod frontend); echo "# INVESTIGATE the not-ready pod ($BAD): events"
run "kubectl -n $NS describe pod $BAD | sed -n '/^Events:/,\$p' | cut -c1-170"
run "k get deploy frontend -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}{\"\\n\"}'"
echo "# ROOT CAUSE: the probe asks for /api/does-not-exist, which the backend answers with 404, so the pod never becomes Ready. FIX: roll back"
run k rollout undo deploy/frontend
wait_ready frontend; run k get pods -l app=frontend
api_ok /

echo "################ FINAL STATE"
run k get pods
api /api/summary
api /
