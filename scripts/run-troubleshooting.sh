#!/usr/bin/env bash
# Final troubleshooting challenge: break the deployed app on purpose, then investigate -> root cause -> fix -> verify.
# Needs the chart installed in namespace "expensetrail" (see README) and an ingress controller.
set -u
NS=expensetrail
URL="http://$(minikube ip)"
HOST="Host: expensetrail.local"
k() { kubectl -n "$NS" "$@"; }
run() { echo "\$ $*"; eval "$@" 2>&1; echo; }
api() { echo "\$ curl -s -o /dev/null -w '%{http_code}' -H '$HOST' $URL$1"; curl -s -m 5 -o /dev/null -w '%{http_code}\n' -H "$HOST" "$URL$1"; echo; }
wait_ready() { kubectl -n "$NS" rollout status "deploy/$1" --timeout="${2:-120s}" 2>&1 | tail -1; }

echo "################ BASELINE"
run k get pods
api /api/summary
api /

echo "################ ISSUE 1: wrong image tag (ErrImagePull / ImagePullBackOff)"
run k set image deploy/backend backend=expensetrail-backend:v-does-not-exist
sleep 20
echo "# SYMPTOM"; run k get pods -l app=backend
echo "# INVESTIGATE"; run "k describe pod -l app=backend | grep -E 'Failed|Back-off|Error' | head -4"
echo "# the rolling update keeps the old pods serving, so users see no outage:"; api /api/summary
echo "# ROOT CAUSE: the image tag does not exist. FIX: roll the Deployment back"
run k rollout undo deploy/backend
wait_ready backend; run k get pods -l app=backend

echo "################ ISSUE 2: wrong database password (pods Running but never Ready)"
OLD=$(k get secret expensetrail-db -o jsonpath='{.data.password}')
run "k patch secret expensetrail-db -p '{\"data\":{\"password\":\"$(printf 'not-the-real-password' | base64)\"}}'"
run k rollout restart deploy/backend
sleep 30
echo "# SYMPTOM: READY 0/1 on the new pod, RESTARTS 0 (the process itself is fine)"; run k get pods -l app=backend
echo "# INVESTIGATE: describe shows readiness failing"; run "k describe pod -l app=backend | grep -E 'Readiness probe failed' | head -2"
echo "# ask the app directly:"; run "k exec deploy/backend -- python -c \"import urllib.request,urllib.error
try: urllib.request.urlopen('http://localhost:8000/ready')
except urllib.error.HTTPError as e: print(e.code, e.read().decode())\""
echo "# test the database login the way the app does it:"
run "k exec deploy/backend -- python -c \"import os,psycopg2
try: psycopg2.connect(os.environ['DATABASE_URL'])
except Exception as e: print(str(e).strip())\""
echo "# ROOT CAUSE: the Secret no longer matches the password PostgreSQL was initialised with. FIX: restore the Secret, restart"
run "k patch secret expensetrail-db -p '{\"data\":{\"password\":\"$OLD\"}}'"
run k rollout restart deploy/backend
wait_ready backend; run k get pods -l app=backend; api /api/summary

echo "################ ISSUE 3: Service selector typo (no endpoints, ingress returns 503)"
run "k patch svc backend -p '{\"spec\":{\"selector\":{\"app\":\"backend-typo\"}}}'"
sleep 3
echo "# SYMPTOM"; api /api/summary
echo "# INVESTIGATE: pods are healthy, but the Service has no endpoints"; run k get pods -l app=backend; run k get endpoints backend
run "k describe svc backend | grep -E 'Selector|Endpoints'"
run "k get pods --show-labels -l app=backend | cut -c1-120"
echo "# ROOT CAUSE: selector app=backend-typo matches no Pod labels. FIX: restore the selector"
run "k patch svc backend -p '{\"spec\":{\"selector\":{\"app\":\"backend\"}}}'"
sleep 3; run k get endpoints backend; api /api/summary

echo "################ ISSUE 4: wrong readiness probe path on the frontend (rollout stuck)"
run "k patch deploy frontend --type=json -p '[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/readinessProbe/httpGet/path\",\"value\":\"/healthz-missing\"}]'"
sleep 25
echo "# SYMPTOM: a new pod is 0/1 while old pods still serve"; run k get pods -l app=frontend; run k rollout status deploy/frontend --timeout=5s
echo "# INVESTIGATE"; run "k describe pod -l app=frontend | grep -E 'Readiness probe failed' | head -2"
run "k get deploy frontend -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}{\"\\n\"}'"
echo "# ROOT CAUSE: nginx has no /healthz-missing (404), so the pod never becomes Ready. FIX: roll back"
run k rollout undo deploy/frontend
wait_ready frontend; run k get pods -l app=frontend; api /

echo "################ FINAL STATE"
run k get pods
api /api/summary
api /
