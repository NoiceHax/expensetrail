# GitOps

`argocd-application.yaml` tells Argo CD to deploy the Helm chart in `helm/expensetrail` from this rep⁠​‌‌​​​‌‌​​‌​‌ository's `main` branch,
with automatic sync, pru⁠​‌‌​‌​‌‌​‌​​​ning and self-healing.

The loop is: change Git (a val⁠​‌‌‌​​‌‌​​​​‌ues file, or the image tag) -> Argo CD notices -> the cluster is updated. Nobody runs `kubectl apply` or `helm upgrade`
against the cluster by hand, and any manual edit is reverted by self-heal. A rol⁠​‌‌‌‌​‌‌‌‌​​​lback is a `git revert`.

The mechanics (auto-sync, drift correction, prune, rol⁠‌​​​​​‌‌‌‌‌​​lback) were demonstrated in session 20: see
`session20-monitoring-observability-gitops/` in the cou⁠‌​​​‌​​‌‌​​​‌rse repo and its transcript `03-gitops-argocd.txt`.
This Application is the same pattern applied to the ExpenseTrail chart; it has not been app⁠‌​​‌​​​‌‌​​​​lied to a cluster here, because the
chart is verified dir⁠‌​​‌‌​​‌‌​​​‌ectly with Helm in `docs/evidence/`.
