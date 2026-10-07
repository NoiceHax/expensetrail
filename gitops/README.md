# GitOps

`argocd-application.yaml` tells Argo CD to deploy the Helm chart in `helm/expensetrail` from this repository's `main` branch,
with automatic sync, pruning and self-healing.

The loop is: change Git (a values file, or the image tag) -> Argo CD notices -> the cluster is updated. Nobody runs `kubectl apply` or `helm upgrade`
against the cluster by hand, and any manual edit is reverted by self-heal. A rollback is a `git revert`.

The mechanics (auto-sync, drift correction, prune, rollback) were demonstrated in session 20: see
`session20-monitoring-observability-gitops/` in the course repo and its transcript `03-gitops-argocd.txt`.
This Application is the same pattern applied to the ExpenseTrail chart; it has not been applied to a cluster here, because the
chart is verified directly with Helm in `docs/evidence/`.
