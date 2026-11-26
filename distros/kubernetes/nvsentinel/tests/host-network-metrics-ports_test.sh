#!/bin/bash
# Copyright (c) 2026, NVIDIA CORPORATION.  All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifests=$(helm template nvsentinel "$chart_dir" \
  --set global.dcgm.mode=external-hostengine \
  --set global.gpuHealthMonitor.enabled=true \
  --set global.metadataCollector.enabled=true "$@")

# Find the named port rather than relying on the ordering of containers or ports.
metrics_port() {
  local port
  if ! port=$(DAEMONSET="$1" yq -r '
    select(.kind == "DaemonSet" and .metadata.name == strenv(DAEMONSET))
    | select(.spec.template.spec.hostNetwork == true)
    | .spec.template.spec.containers[].ports[]
    | select(.name == "metrics")
    | .containerPort
  ' <<< "$manifests") || [[ ! "$port" =~ ^[1-9][0-9]*$ ]]; then
    printf 'FAIL: expected one metrics port on host-network DaemonSet %s\n' "$1" >&2
    return 1
  fi
  printf '%s\n' "$port"
}

collector_port=$(metrics_port metadata-collector)
for monitor in gpu-health-monitor-dcgm-3.x gpu-health-monitor-dcgm-4.x; do
  monitor_port=$(metrics_port "$monitor")
  if [[ "$collector_port" == "$monitor_port" ]]; then
    printf 'FAIL: metadata-collector and %s share host metrics port %s\n' \
      "$monitor" "$collector_port" >&2
    exit 1
  fi
done

echo 'PASS: metadata-collector and GPU health monitors use distinct host metrics ports'
