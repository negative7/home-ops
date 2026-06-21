### Moving to new namespace:

```yaml
apiVersion: volsync.backube/v1alpha1
kind: ReplicationDestination
metadata:
  name: APP-restore
  namespace: NEW_NS
spec:
  trigger:
    manual: restore-once
  kopia:
    moverSecurityContext:
      fsGroup: 2000
      runAsGroup: 2000
      runAsUser: 2000
    moverVolumes:
      - mountPath: repository
        volumeSource:
          nfs:
            path: /mnt/tank/kopia
            server: truenas.homelab.internal
    repository: APP-volsync-secret
    username: "APP"      # old identity username
    hostname: "OLD NS"     # old identity hostname (the old namespace)
    copyMethod: Direct
    destinationPVC: PVC_NAME  # name your app's PVC actually expects

```

```bash
kubectl delete replicationdestination APP-restore -n NEW_NS
```