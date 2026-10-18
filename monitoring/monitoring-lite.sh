#!/usr/bin/env bash
# monitoring-lite.sh - Prometheus + Grafana INSIDE the minikube cluster, sized for a small machine.
#
# Instead of kube-prometheus-stack (operator + kube-state-metrics + sidecars, ~1.5 GB of images,
# ~1 GB RAM) this runs two plain Deployments in namespace "monitoring":
#   prometheus  - scrapes vaultai-api pods (/metrics) and Jenkins (/prometheus/), 6h retention
#   grafana     - provisioned datasource + one dashboard, random admin password, no public exposure
# Budget: ~450 MiB limits in total. Nothing is exposed outside the cluster; use port-forward.
# Safe to re-run. Remove everything with:  bash monitoring-lite.sh --remove
set -euo pipefail

NS=monitoring
PROM_IMG="prom/prometheus:v2.55.1"      # already on this machine from the old compose setup
GRAF_IMG="grafana/grafana:11.2.0"       # same; the 13.x distroless image is 1.4 GB and was too slow
AM_IMG="prom/alertmanager:v0.27.0"       # Alertmanager (email alerts)
NODE=minikube

if [ "${1:-}" = "--remove" ]; then
  kubectl delete namespace "$NS" --ignore-not-found
  kubectl delete clusterrole,clusterrolebinding prometheus-pod-reader --ignore-not-found
  exit 0
fi

echo "== preflight =="
kubectl get nodes >/dev/null || { echo "kubectl cannot reach the cluster (is minikube running?)"; exit 1; }
cap=$(docker inspect "$NODE" --format '{{.HostConfig.Memory}}')
if [ "$cap" -lt $((2900*1024*1024)) ]; then
  echo "minikube memory cap is only $((cap/1024/1024)) MiB. Run ./stabilize.sh first."; exit 1
fi
echo "minikube cap: $((cap/1024/1024)) MiB - ok"

echo "== images (loaded from this machine's Docker into minikube; no big pulls inside the cluster) =="
for img in "$PROM_IMG" "$GRAF_IMG" "$AM_IMG"; do
  docker image inspect "$img" >/dev/null 2>&1 || docker pull "$img"
  if docker exec "$NODE" docker image inspect "$img" >/dev/null 2>&1; then
    echo "already in minikube: $img"
  else
    echo "loading $img ..."
    docker save "$img" | docker exec -i "$NODE" docker load
    docker exec "$NODE" docker image inspect "$img" >/dev/null   # fail loudly if the load did not stick
  fi
done

JIP=$(docker inspect jenkins --format '{{(index .NetworkSettings.Networks "minikube").IPAddress}}' 2>/dev/null || true)
if [ -z "$JIP" ]; then
  echo "WARNING: could not find Jenkins on the minikube network - the jenkins scrape job is skipped."
  echo "         (fix: docker network connect minikube jenkins, then re-run)"
fi

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

cat > "$W/prometheus.yml" <<'EOF'
global:
  scrape_interval: 30s
  evaluation_interval: 30s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager.monitoring.svc:9093']

rule_files:
  - /etc/prometheus/alert_rules.yml

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ['localhost:9090']

  # App pods, discovered through the Kubernetes API (staging and prod, any replica count).
  - job_name: vaultai-api
    metrics_path: /metrics/
    kubernetes_sd_configs:
      - role: pod
        namespaces:
          names: [vaultai-staging, vaultai-prod]
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        regex: vaultai-api
        action: keep
      - source_labels: [__meta_kubernetes_pod_phase]
        regex: Running
        action: keep
      - source_labels: [__meta_kubernetes_pod_ip]
        target_label: __address__
        replacement: '$1:8000'
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
EOF
if [ -n "$JIP" ]; then cat >> "$W/prometheus.yml" <<EOF

  # The CI server itself (Jenkins 'Prometheus metrics' plugin).
  - job_name: jenkins
    metrics_path: /prometheus/
    static_configs:
      - targets: ['${JIP}:8080']
EOF
fi

cat > "$W/alert_rules.yml" <<'EOF'
groups:
  - name: vaultai-alerts
    rules:
      - alert: VaultAIAPIDown
        expr: up{job="vaultai-api"} == 0
        for: 1m
        labels: {severity: critical}
        annotations:
          summary: "VaultAI API pod {{ $labels.pod }} is down"
          description: "Prometheus could not scrape {{ $labels.namespace }}/{{ $labels.pod }} for 1 minute."
      - alert: VaultAIHighErrorRate
        expr: |
          sum(rate(vaultai_http_requests_total{status=~"5.."}[5m]))
          / sum(rate(vaultai_http_requests_total[5m])) > 0.05
        for: 2m
        labels: {severity: warning}
        annotations:
          summary: "VaultAI API error rate above 5%"
          description: "More than 5% of requests returned 5xx over the last 5 minutes."
      - alert: VaultAIHighLatency
        expr: |
          histogram_quantile(0.95,
            sum(rate(vaultai_http_request_duration_seconds_bucket[5m])) by (le)) > 3
        for: 2m
        labels: {severity: warning}
        annotations:
          summary: "VaultAI API p95 latency above 3s"
          description: "95th percentile latency has been above 3 seconds for 2+ minutes."
      - alert: JenkinsDown
        expr: up{job="jenkins"} == 0
        for: 2m
        labels: {severity: critical}
        annotations:
          summary: "Jenkins is not answering scrapes"
          description: "The CI server has been unreachable for 2 minutes - commits will not build."
      - alert: VaultAIAPIMissing
        expr: absent(up{job="vaultai-api", namespace="vaultai-prod"})
        for: 1m
        labels: {severity: critical}
        annotations:
          summary: "No VaultAI API pods are running in production"
          description: "Prometheus sees no vaultai-api targets in vaultai-prod. The API is scaled to zero or crashing."
EOF

cat > "$W/datasource.yaml" <<'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    uid: prometheus
    type: prometheus
    access: proxy
    url: http://prometheus.monitoring.svc:9090
    isDefault: true
    editable: false
EOF

cat > "$W/provider.yaml" <<'EOF'
apiVersion: 1
providers:
  - name: vaultai
    type: file
    disableDeletion: true
    allowUiUpdates: false
    options:
      path: /etc/grafana/dashboards-json
EOF

cat > "$W/vaultai.json" <<'EOF'
{
  "uid": "vaultai-overview",
  "title": "VaultAI - App and CI/CD pipeline",
  "schemaVersion": 39,
  "version": 1,
  "refresh": "30s",
  "time": {"from": "now-1h", "to": "now"},
  "panels": [
    {"id": 1, "type": "stat", "title": "Scrape targets (1 = UP)",
     "gridPos": {"h": 5, "w": 8, "x": 0, "y": 0},
     "datasource": {"type": "prometheus", "uid": "prometheus"},
     "targets": [{"refId": "A", "expr": "up", "legendFormat": "{{job}} {{pod}}", "instant": true}],
     "fieldConfig": {"defaults": {"min": 0, "max": 1,
       "mappings": [{"type": "value", "options": {"0": {"text": "DOWN"}, "1": {"text": "UP"}}}],
       "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": null}, {"color": "green", "value": 1}]}}, "overrides": []},
     "options": {"colorMode": "background", "textMode": "value_and_name"}},
    {"id": 2, "type": "stat", "title": "Jenkins up",
     "gridPos": {"h": 5, "w": 4, "x": 8, "y": 0},
     "datasource": {"type": "prometheus", "uid": "prometheus"},
     "targets": [{"refId": "A", "expr": "default_jenkins_up", "instant": true}],
     "fieldConfig": {"defaults": {"mappings": [{"type": "value", "options": {"0": {"text": "DOWN"}, "1": {"text": "UP"}}}],
       "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": null}, {"color": "green", "value": 1}]}}, "overrides": []},
     "options": {"colorMode": "background"}},
    {"id": 3, "type": "stat", "title": "Builds recorded (per job)",
     "gridPos": {"h": 5, "w": 12, "x": 12, "y": 0},
     "datasource": {"type": "prometheus", "uid": "prometheus"},
     "targets": [{"refId": "A", "expr": "default_jenkins_builds_duration_milliseconds_summary_count", "legendFormat": "{{jenkins_job}}", "instant": true}],
     "options": {"textMode": "value_and_name"}},
    {"id": 4, "type": "timeseries", "title": "Average build duration (seconds)",
     "gridPos": {"h": 8, "w": 12, "x": 0, "y": 5},
     "datasource": {"type": "prometheus", "uid": "prometheus"},
     "targets": [{"refId": "A", "expr": "(default_jenkins_builds_duration_milliseconds_summary_sum / default_jenkins_builds_duration_milliseconds_summary_count) / 1000", "legendFormat": "{{jenkins_job}}"}],
     "fieldConfig": {"defaults": {"unit": "s"}, "overrides": []}},
    {"id": 5, "type": "timeseries", "title": "API requests per second, by status",
     "gridPos": {"h": 8, "w": 12, "x": 12, "y": 5},
     "datasource": {"type": "prometheus", "uid": "prometheus"},
     "targets": [{"refId": "A", "expr": "sum by (status) (rate(vaultai_http_requests_total[5m]))", "legendFormat": "{{status}}"}],
     "fieldConfig": {"defaults": {"unit": "reqps"}, "overrides": []}},
    {"id": 6, "type": "timeseries", "title": "API p95 latency",
     "gridPos": {"h": 8, "w": 12, "x": 0, "y": 13},
     "datasource": {"type": "prometheus", "uid": "prometheus"},
     "targets": [{"refId": "A", "expr": "histogram_quantile(0.95, sum by (le) (rate(vaultai_http_request_duration_seconds_bucket[5m])))", "legendFormat": "p95"}],
     "fieldConfig": {"defaults": {"unit": "s"}, "overrides": []}},
    {"id": 7, "type": "timeseries", "title": "API 5xx error ratio",
     "gridPos": {"h": 8, "w": 12, "x": 12, "y": 13},
     "datasource": {"type": "prometheus", "uid": "prometheus"},
     "targets": [{"refId": "A", "expr": "sum(rate(vaultai_http_requests_total{status=~\"5..\"}[5m])) / sum(rate(vaultai_http_requests_total[5m]))", "legendFormat": "5xx ratio"}],
     "fieldConfig": {"defaults": {"unit": "percentunit", "min": 0}, "overrides": []}}
  ]
}
EOF
python3 -m json.tool "$W/vaultai.json" >/dev/null   # catch typos before anything is applied

echo "== applying =="
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
# Pod Security: 'restricted' is enforced for this namespace - everything below complies.
kubectl label namespace "$NS" pod-security.kubernetes.io/enforce=restricted --overwrite >/dev/null

kubectl -n "$NS" create configmap prometheus-config \
  --from-file=prometheus.yml="$W/prometheus.yml" --from-file=alert_rules.yml="$W/alert_rules.yml" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create configmap grafana-datasource --from-file=datasource.yaml="$W/datasource.yaml" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create configmap grafana-provider --from-file=provider.yaml="$W/provider.yaml" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create configmap grafana-dashboards --from-file=vaultai.json="$W/vaultai.json" \
  --dry-run=client -o yaml | kubectl apply -f -

# Random Grafana admin password, created once and kept across re-runs.
if ! kubectl -n "$NS" get secret grafana-admin >/dev/null 2>&1; then
  kubectl -n "$NS" create secret generic grafana-admin \
    --from-literal=password="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)"
fi

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata: {name: prometheus, namespace: monitoring}
automountServiceAccountToken: true
---
# Read-only access to pod metadata, needed for service discovery. Nothing else.
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: {name: prometheus-pod-reader}
rules:
  - apiGroups: [""]
    resources: [pods]
    verbs: [get, list, watch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: {name: prometheus-pod-reader}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: prometheus-pod-reader}
subjects:
  - {kind: ServiceAccount, name: prometheus, namespace: monitoring}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: prometheus, namespace: monitoring, labels: {app: prometheus}}
spec:
  replicas: 1
  strategy: {type: Recreate}
  selector: {matchLabels: {app: prometheus}}
  template:
    metadata: {labels: {app: prometheus}}
    spec:
      serviceAccountName: prometheus
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
        runAsGroup: 65534
        fsGroup: 65534
        seccompProfile: {type: RuntimeDefault}
      containers:
        - name: prometheus
          image: prom/prometheus:v2.55.1
          imagePullPolicy: IfNotPresent
          args:
            - --config.file=/etc/prometheus/prometheus.yml
            - --storage.tsdb.path=/prometheus
            - --storage.tsdb.retention.time=6h
            - --storage.tsdb.retention.size=300MB
          env:
            - {name: GOMEMLIMIT, value: 256MiB}   # make the Go GC stay under the container limit
          ports: [{name: web, containerPort: 9090}]
          resources:
            requests: {cpu: 100m, memory: 160Mi}
            limits: {cpu: 300m, memory: 320Mi}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: {drop: [ALL]}
          readinessProbe:
            httpGet: {path: /-/ready, port: web}
            periodSeconds: 15
            timeoutSeconds: 5
            failureThreshold: 6
          livenessProbe:
            httpGet: {path: /-/healthy, port: web}
            initialDelaySeconds: 30
            periodSeconds: 20
            timeoutSeconds: 5
            failureThreshold: 6
          volumeMounts:
            - {name: config, mountPath: /etc/prometheus, readOnly: true}
            - {name: data, mountPath: /prometheus}
      volumes:
        - {name: config, configMap: {name: prometheus-config}}
        - {name: data, emptyDir: {sizeLimit: 400Mi}}
---
apiVersion: v1
kind: Service
metadata: {name: prometheus, namespace: monitoring}
spec:
  selector: {app: prometheus}
  ports: [{name: web, port: 9090, targetPort: web}]
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: grafana, namespace: monitoring, labels: {app: grafana}}
spec:
  replicas: 1
  strategy: {type: Recreate}
  selector: {matchLabels: {app: grafana}}
  template:
    metadata: {labels: {app: grafana}}
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 472
        runAsGroup: 472
        fsGroup: 472
        seccompProfile: {type: RuntimeDefault}
      containers:
        - name: grafana
          image: grafana/grafana:11.2.0
          imagePullPolicy: IfNotPresent
          env:
            - {name: GF_SECURITY_ADMIN_USER, value: admin}
            - name: GF_SECURITY_ADMIN_PASSWORD
              valueFrom: {secretKeyRef: {name: grafana-admin, key: password}}
            - {name: GF_USERS_ALLOW_SIGN_UP, value: "false"}
            - {name: GF_AUTH_ANONYMOUS_ENABLED, value: "false"}
            - {name: GF_ANALYTICS_REPORTING_ENABLED, value: "false"}
            - {name: GF_ANALYTICS_CHECK_FOR_UPDATES, value: "false"}
            - {name: GOMEMLIMIT, value: 200MiB}
          ports: [{name: web, containerPort: 3000}]
          resources:
            requests: {cpu: 50m, memory: 96Mi}
            limits: {cpu: 200m, memory: 256Mi}
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: {drop: [ALL]}
          readinessProbe:
            httpGet: {path: /api/health, port: web}
            initialDelaySeconds: 15
            periodSeconds: 15
            timeoutSeconds: 5
            failureThreshold: 10
          livenessProbe:
            httpGet: {path: /api/health, port: web}
            initialDelaySeconds: 60
            periodSeconds: 20
            timeoutSeconds: 5
            failureThreshold: 10
          volumeMounts:
            - {name: data, mountPath: /var/lib/grafana}
            - {name: datasource, mountPath: /etc/grafana/provisioning/datasources, readOnly: true}
            - {name: provider, mountPath: /etc/grafana/provisioning/dashboards, readOnly: true}
            - {name: dashboards, mountPath: /etc/grafana/dashboards-json, readOnly: true}
      volumes:
        - {name: data, emptyDir: {sizeLimit: 200Mi}}
        - {name: datasource, configMap: {name: grafana-datasource}}
        - {name: provider, configMap: {name: grafana-provider}}
        - {name: dashboards, configMap: {name: grafana-dashboards}}
---
apiVersion: v1
kind: Service
metadata: {name: grafana, namespace: monitoring}
spec:
  selector: {app: grafana}
  ports: [{name: web, port: 3000, targetPort: web}]
EOF

# ---- Alertmanager: email notifications (restricted Pod Security profile, SMTP password from a Secret) ----
if ! kubectl -n "$NS" get secret alertmanager-smtp >/dev/null 2>&1; then
  [ -t 0 ] || { echo "Secret alertmanager-smtp is missing. Run this script from a terminal to create it."; exit 1; }
  read -r -p "Gmail address for alerts: " AM_ADDR
  read -rsp "Gmail app password (16 characters, no spaces): " AM_PW; echo
  kubectl -n "$NS" create secret generic alertmanager-smtp \
    --from-literal=smtp_user="$AM_ADDR" --from-literal=smtp_password="$AM_PW"
  unset AM_PW
fi
ADDR=$(kubectl -n "$NS" get secret alertmanager-smtp -o jsonpath='{.data.smtp_user}' | base64 -d)

cat > "$W/alertmanager.yml" <<EOF
global:
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: '${ADDR}'
  smtp_auth_username: '${ADDR}'
  smtp_auth_password_file: /etc/alertmanager-smtp/smtp_password
  smtp_require_tls: true
route:
  receiver: email-alert
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 1m
  repeat_interval: 1h
receivers:
  - name: email-alert
    email_configs:
      - to: '${ADDR}'
        send_resolved: true
EOF
kubectl -n "$NS" create configmap alertmanager-config --from-file=alertmanager.yml="$W/alertmanager.yml" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: alertmanager, namespace: monitoring, labels: {app: alertmanager}}
spec:
  replicas: 1
  strategy: {type: Recreate}
  selector: {matchLabels: {app: alertmanager}}
  template:
    metadata: {labels: {app: alertmanager}}
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
        runAsGroup: 65534
        fsGroup: 65534
        seccompProfile: {type: RuntimeDefault}
      containers:
        - name: alertmanager
          image: prom/alertmanager:v0.27.0
          imagePullPolicy: IfNotPresent
          args:
            - --config.file=/etc/alertmanager/alertmanager.yml
            - --storage.path=/alertmanager
          ports: [{name: web, containerPort: 9093}]
          resources:
            requests: {cpu: 50m, memory: 64Mi}
            limits: {cpu: 150m, memory: 128Mi}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: {drop: [ALL]}
          readinessProbe:
            httpGet: {path: /-/ready, port: web}
            periodSeconds: 15
            timeoutSeconds: 5
          livenessProbe:
            httpGet: {path: /-/healthy, port: web}
            initialDelaySeconds: 20
            periodSeconds: 20
            timeoutSeconds: 5
          volumeMounts:
            - {name: config, mountPath: /etc/alertmanager, readOnly: true}
            - {name: smtp-secret, mountPath: /etc/alertmanager-smtp, readOnly: true}
            - {name: data, mountPath: /alertmanager}
      volumes:
        - {name: config, configMap: {name: alertmanager-config}}
        - name: smtp-secret
          secret:
            secretName: alertmanager-smtp
            items: [{key: smtp_password, path: smtp_password}]
        - {name: data, emptyDir: {sizeLimit: 50Mi}}
---
apiVersion: v1
kind: Service
metadata: {name: alertmanager, namespace: monitoring}
spec:
  selector: {app: alertmanager}
  ports: [{name: web, port: 9093, targetPort: web}]
EOF

# Config files are read at start-up: restart so a re-run with new config takes effect.
kubectl -n "$NS" rollout restart deployment/prometheus deployment/grafana deployment/alertmanager >/dev/null

echo "== waiting for pods =="
if ! kubectl -n "$NS" rollout status deployment/prometheus --timeout=240s \
   || ! kubectl -n "$NS" rollout status deployment/grafana --timeout=300s; then
  echo; echo "NOT READY. Diagnostics:"
  kubectl -n "$NS" get pods -o wide
  kubectl -n "$NS" get events --sort-by=.lastTimestamp | tail -12
  echo "Undo everything with: bash monitoring-lite.sh --remove"
  exit 1
fi

echo "== waiting 45s for the first scrapes =="
sleep 45
kubectl -n "$NS" exec deploy/prometheus -- wget -qO- http://localhost:9090/api/v1/targets \
 | python3 -c '
import json, sys
t = json.load(sys.stdin)["data"]["activeTargets"]
print(f"{len(t)} targets")
for x in sorted(t, key=lambda x: (x["labels"].get("job",""), x["labels"].get("pod",""))):
    print("  %-12s %-34s %-5s %s" % (x["labels"].get("job"), x["labels"].get("pod", x["scrapeUrl"]), x["health"].upper(), x["lastError"][:70]))
'

cat <<EOM

DONE. Pods:
$(kubectl -n "$NS" get pods)

Open the UIs (each in its own terminal, leave it running):
  kubectl port-forward -n monitoring svc/grafana 3000:3000        -> http://localhost:3000
  kubectl port-forward -n monitoring svc/prometheus 9090:9090     -> http://localhost:9090/targets

Grafana login:  admin / $(kubectl -n "$NS" get secret grafana-admin -o jsonpath='{.data.password}' | base64 -d)
Dashboard:      Dashboards -> "VaultAI - App and CI/CD pipeline"
Alert rules:    http://localhost:9090/alerts   (no Alertmanager: they show firing/pending but send nothing)
EOM
