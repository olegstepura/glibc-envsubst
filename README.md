# glibc-envsubst
Envsubst image compiled against glibc. Idea is to use this as [config management plugin](https://argo-cd.readthedocs.io/en/stable/user-guide/config-management-plugins/)
in [ArgoCD](https://github.com/argoproj/argo-cd) to post-process Kubernetes manifests replacing ENV variables after running Kustomize.

## Usage example with ArgoCD

Imagine we have this secret in kubernetes cluster:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cluster-global-vars
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: argocd
type: Opaque
data:
  CLUSTER_IP_RANGE: MTAuMTAuMTAuMzItMTAuMTAuMTAuNjQ= # base64 encoded '10.10.10.32-10.10.10.64'
```

And an app for [metallb](https://metallb.universe.tf/) using kustomize helm chart
```yaml
# kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

helmCharts:
- name: metallb
  version: 0.12.1
  repo: https://metallb.github.io/metallb
  releaseName: metallb
  valuesFile: values.yaml
```

with `values.yaml` file:
```yaml
# values.yaml
configInline:
  address-pools:
    - name: default
      protocol: layer2
      addresses:
        - ${CLUSTER_IP_RANGE}
```

Apply this patch to `argocd-repo-server` using `kubectl -n argocd patch deploy/argocd-repo-server -p "$(cat argocd-repo-server-patch.yaml)"`:
```yaml
# argocd-repo-server-patch.yaml
spec:
  template:
    spec:
      # 1. Define an emptyDir volume which will hold the custom binaries
      volumes:
      - name: custom-tools
        emptyDir: {}
      # 2. Use an init container to download/copy custom binaries into the emptyDir
      initContainers:
      - name: download-tools
        image: olegstepura/glibc-envsubst:latest
        command: [sh, -c]
        args:
        - cp /usr/bin/envsubst /custom-tools/
        volumeMounts:
        - mountPath: /custom-tools
          name: custom-tools
      # 3. Volume mount the custom binary to the bin directory (overriding the existing version)
      containers:
      - name: argocd-repo-server
        volumeMounts:
        - mountPath: /usr/local/bin/envsubst
          name: custom-tools
          subPath: envsubst
        envFrom:
          - secretRef:
              name: cluster-global-vars
```

and this patch to `argocd-cm` using `kubectl -n argocd patch cm/argocd-cm -p "$(cat argocd-cm-patch.yaml)"`:
```yaml
# argocd-cm-patch.yaml
data:
  configManagementPlugins: |-
    - name: kustomize-envsubst
      generate:
        command: ["sh", "-c"]
        args: ["kustomize build --enable-helm . | envsubst"]
```

Now when your app will be synced by argod it will run `kustomize build --enable-helm . | envsubst` piping resulting multifile yaml to envsubst
which will substitute ENV vars mounted from `cluster-global-vars` secret (and `ARGOCD_*` own ones as well) and resulting yaml with vars replaced will be applied to your cluster.