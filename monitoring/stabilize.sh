#!/usr/bin/env bash
# stabilize.sh - make the single-node minikube cluster stop starving.
#
# Why: minikube's container is capped at ~2.1 GB. With staging pods + Jenkins
# builds + image loads it sits at 80-90% of that cap, the kernel spends its time
# reclaiming memory, and HTTP probes (default timeout 1s) time out. Result:
# pods restart, rollouts hang, builds fail. Nothing is wrong with the pipeline.
#
# What this does (safe to re-run):
#   1. raises the minikube container memory cap to 3 GB (live, no restart, keeps all data)
#   2. removes leftover CRDs from the abandoned kube-prometheus-stack install
#   3. relaxes probe timeouts in k8s/base/*.yaml (1s -> 5s, tolerate 6 failures)
#      -> edits files only; YOU commit them with the next build
set -euo pipefail

REPO="${REPO:-$HOME/finacplus-vaultai}"
MEM="${MEM:-3g}"

echo "== 1/3 minikube memory cap =="
docker inspect minikube >/dev/null 2>&1 || { echo "No 'minikube' container. Run: minikube start"; exit 1; }
cur=$(docker inspect minikube --format '{{.HostConfig.Memory}}')
echo "current cap: $((cur/1024/1024)) MiB"
docker update --memory "$MEM" --memory-swap "$MEM" minikube >/dev/null
new=$(docker inspect minikube --format '{{.HostConfig.Memory}}')
echo "new cap:     $((new/1024/1024)) MiB"
echo "(A 'minikube stop/start' or WSL restart resets this - just re-run this script.)"
docker stats --no-stream minikube
free -h

echo
echo "== 2/3 leftover CRDs from the old Helm install =="
if command -v helm >/dev/null && helm list -A 2>/dev/null | grep -q '^monitoring'; then
  echo "Helm release 'monitoring' still exists - run: helm uninstall monitoring -n monitoring"; exit 1
fi
crds=$(kubectl get crd -o name 2>/dev/null | grep 'monitoring.coreos.com' || true)
if [ -n "$crds" ]; then
  echo "$crds" | xargs kubectl delete --wait=false
else
  echo "none"
fi

echo
echo "== 3/3 probe timeouts in $REPO/k8s/base =="
python3 - "$REPO/k8s/base" <<'PY'
import re, sys, pathlib
changed = 0
for f in sorted(pathlib.Path(sys.argv[1]).glob("*-deployment.yaml")):
    lines = f.read_text().split("\n")
    out, i = [], 0
    while i < len(lines):
        out.append(lines[i])
        m = re.match(r"^(\s+)periodSeconds:\s*\d+\s*$", lines[i])
        if m:
            # look at the rest of this probe (same or deeper indentation)
            ind = m.group(1)
            j, block = i + 1, []
            while j < len(lines) and lines[j].startswith(ind) and lines[j].strip():
                block.append(lines[j]); j += 1
            if not any("timeoutSeconds" in b for b in block):
                out += [f"{ind}timeoutSeconds: 5", f"{ind}failureThreshold: 6"]
                changed += 1
        i += 1
    f.write_text("\n".join(out))
print(f"probes updated: {changed} (0 means already done)")
PY
cd "$REPO" && git --no-pager diff --stat || true

cat <<'EOM'

Next:
  1. wait ~3 minutes, then check nothing is still failing probes:
       kubectl get pods -n vaultai-staging
       kubectl get events -n vaultai-staging --field-selector type=Warning --sort-by=.lastTimestamp | tail -5
     (events older than a few minutes are fine - you want NO new ones)
  2. commit the probe change together with the verification build:
       cd ~/finacplus-vaultai && git commit -am "Relax probe timeouts for small local cluster" && git push
     then in Jenkins pick 'Skip production' at the approval.
EOM
