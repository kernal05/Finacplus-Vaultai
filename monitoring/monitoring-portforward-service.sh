#!/usr/bin/env bash
# Keeps Grafana (localhost:3000) and Prometheus (localhost:9090) reachable in the background.
# Two systemd services; they start with WSL, and restart themselves if the pod restarts
# or minikube is not up yet. Remove with:  bash monitoring-portforward-service.sh --remove
set -euo pipefail

SVCS=(grafana:3000 prometheus:9090)

if [ "${1:-}" = "--remove" ]; then
  for s in "${SVCS[@]}"; do n=${s%%:*}
    sudo systemctl disable --now "monitoring-pf-$n" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/monitoring-pf-$n.service"
  done
  sudo systemctl daemon-reload; echo removed; exit 0
fi

KUBECTL=$(command -v kubectl)
for s in "${SVCS[@]}"; do n=${s%%:*}; p=${s##*:}
  sudo tee "/etc/systemd/system/monitoring-pf-$n.service" >/dev/null <<EOF
[Unit]
Description=kubectl port-forward for $n (monitoring namespace)
After=network-online.target docker.service
StartLimitIntervalSec=0

[Service]
User=$USER
Environment=KUBECONFIG=$HOME/.kube/config
ExecStart=$KUBECTL port-forward -n monitoring --address 127.0.0.1 svc/$n $p:$p
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
done
sudo systemctl daemon-reload
for s in "${SVCS[@]}"; do n=${s%%:*}; sudo systemctl enable --now "monitoring-pf-$n"; done
sleep 4
for s in "${SVCS[@]}"; do n=${s%%:*}; p=${s##*:}
  printf '%-11s service: %-8s http: ' "$n" "$(systemctl is-active monitoring-pf-$n)"
  curl -s -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:$p/" || true
done
echo "Grafana    http://localhost:3000   (admin / password from: kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.password}' | base64 -d; echo)"
echo "Prometheus http://localhost:9090/targets"
