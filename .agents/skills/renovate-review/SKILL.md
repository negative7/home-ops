---
name: renovate-review
description: Review Renovate dependency update PRs in this Flux/Talos home-ops repository (Helm OCI charts, container tags and digests, Talos/Kubernetes upgrades, docker-compose hosts, mise tools, Renovate presets). Establish what changes on deployment and whether this repository relies on the old behavior before recommending a merge.
---

<!-- markdownlint-disable MD013 -->

# Review a Renovate PR in home-ops

Determine **what changes on deployment and whether this repository relies on the old behavior**. Flux reconciles `kubernetes/` changes shortly after merge, and doco-cd redeploys `docker/<host>/` changes. `AGENTS.md` stays authoritative for repository conventions; this skill only adds the dependency-update review procedure. Do not restate or override it, and do not flag a documented convention as a finding.

## 1. Identify the update and its footprint

- List every dependency with its old and new version, tag or digest. Renovate groups (see `.renovate/groups.json5`) bundle several upgrades; judge each one.
- Distinguish the kinds of change: OCI chart tag (`ocirepository.yaml`, pinned by `ref.tag`, never by `@sha256:`), container image tag/digest (HelmRelease values, manifests, `docker/` compose files), Talos/Kubernetes version (tuppr), mise tools (`.mise.toml`), Forgejo workflows (`.forgejo/workflows/`), Ansible, and Renovate presets (`.renovaterc.json5`, `.renovate/`).
- Apps live under `kubernetes/apps/<namespace>/<app>/` (a `ks.yaml` plus `app/`); shared pieces live under `kubernetes/components/`. Trace every consumer of a changed component before judging impact. Docker hosts are `docker/lviv` and `docker/odesa`, bootstrapped from `ansible/<host>/`.
- A digest-only refresh of an unchanged tag needs only a compact review: that the digest changed, plus consistent upstream metadata. Do not invent breaking changes for it.

## 2. Check Renovate holds and policy

Before any other judgment, check that the PR does not violate a hold or policy set in `.renovaterc.json5` and `.renovate/`:

- `.renovate/apps/cloudnative-pg.json5` disables major bumps of `ghcr.io/cloudnative-pg/postgresql`. A Postgres major needs a planned upgrade; a PR that crosses a major is a violation.
- `.renovaterc.json5` sets `pinDigests: false` for `kubernetes/apps/dev/forgejo/app/**` and `kubernetes/talos/**`. A digest pin there breaks image refs (the forgejo chart appends `-rootless`, which broke the image name once). Flag any such pin.
- `.renovate/autoMerge.json5` excludes core infrastructure (forgejo, cilium, coredns, cloudnative-pg, postgres, kanidm/kaniop, miroir, kopiur, flux, siderolabs, Kubernetes components, envoy, spegel, multus, cert-manager, trust-manager, external-secrets, 1password, tuppr) from patch automerge. A PR touching these needs real review even when it is a patch.
- A stale PR may predate a rule change. Re-read the current config rather than trusting the PR's labels (`type/major|minor|patch`).

## 3. Use rendered evidence first

This repo runs konflate (`kubernetes/apps/flux-system/konflate`). Prefer render evidence already in the review corpus or exposed by configured read-only tools over reading the one-line git diff:

- Look at affected resources, image changes, removals, immutable-field changes, RBAC, `suspend`/`prune` changes and render errors.
- Chart defaults, templates, selectors and labels can change the rendered manifests while the git diff looks trivial.
- If there is no render for the PR, say **unverified**. Never say "unchanged" or "safe" without one.
- Renders may omit CRDs and Secret data. Their absence is not evidence of no change, and one unrelated render error is not proof the upgraded chart fails.
- Use only tools actually available to you. This skill grants no shell, cluster or write access, and you must not claim to have run anything you did not.

## 4. Verify upstream changes

Start from the PR's release notes, but inspect upstream when they are absent or truncated, for major or 0.x-minor bumps, for jumps across several versions, and for anything with material runtime change. `AGENTS.md` expects real upstream evidence, not only the Renovate description.

- **OCI chart:** find the source via the app's `ocirepository.yaml`. For `ghcr.io/home-operations/charts-mirror/<chart>`, use that mirror's metadata to find the real chart. If `appVersion` changed, read the application's release notes too.
- **Container image:** resolve upstream from the image owner or `org.opencontainers.image.source`. For `ghcr.io/home-operations/*`, check `home-operations/containers`.
- Follow issues and PRs that a changelog only references by number. Look for raised minimums, removed fields, changed auth/storage/network defaults, one-way migrations and relevant security advisories.
- State evidence gaps honestly as **Unknown / needs verification**.

## 5. Repository-specific caveats

- **Talos / Kubernetes (tuppr):** versions live in annotated `version:` fields in `kubernetes/apps/system-upgrade/tuppr/upgrades/` (`talosupgrade.yaml`, `kubernetesupgrade.yaml`). tuppr upgrades node by node, gated on Kopiur jobs and Miroir volume health. Check that the target Talos release supports the target Kubernetes version against the published Talos support matrix; a patch bump alone is not proof. Check `.mise.toml` `talosctl`/`kubectl` stay in step, and that `kubernetes/talos/` machine config (extensions, installer image, kernel args, volume config) still fits the release.
- **Miroir / DRBD:** Miroir (`miroir-system`) replicates `miroir-replicated` (3 replicas) and `miroir-local` volumes. Treat operator, DRBD or kernel-module changes, and any Talos upgrade that reboots nodes, as data-safety risks. Look for storage class, volume config or CRD changes, and remember that a reboot can leave DRBD out of sync even when disks look UpToDate.
- **Cilium:** datapath, kube-proxy replacement, veth/runtime, Hubble and policy-engine changes affect every workload. Check CiliumNetworkPolicies and Gateway/LB IP pool consumers in this repo, and treat a policy-semantics change as high risk.
- **CNPG / Postgres:** the shared `postgres` cluster is in `kubernetes/apps/database/postgres/`. Operator bumps and the barman-cloud plugin affect WAL archiving to Garage S3. Operand major bumps are blocked by Renovate (see section 2); minor bumps must keep the `-standard-trixie` image variant and the extensions (pgvector, VectorChord) working. Apps use TLS-only `pg_hba`.
- **Charts with templated CRDs:** a chart that templates its CRDs can delete them on a chart switch or uninstall, even with `keepCRDs`. Check whether a chart switch or CRD-handling change is in the diff, and whether instances of those CRDs exist here.
- **Flux, external-secrets, 1Password, cert-manager, Envoy Gateway, Kanidm/kaniop, Kopiur:** these are shared infrastructure many apps depend on. Search `dependsOn`, `healthChecks`, components and `postBuild` consumers before calling an upgrade low risk.
- **Docker hosts (`docker/lviv`, `docker/odesa`):** doco-cd applies these directly. Check compose env, volumes, networks and healthchecks for the changed image, and Ansible roles under `ansible/` for the same host.
- **Workflows and presets:** read the upstream release or compare, then check how `.forgejo/workflows/` or `.renovate/` actually uses the changed inputs, outputs or rules.

## 6. Search for exposure

Search the actual consumers of anything removed or renamed, not only whether the new value is set explicitly: ServiceMonitors, alerts and dashboards, NetworkPolicies/CiliumNetworkPolicies, HTTPRoutes, PDBs, Flux `dependsOn`/`healthChecks`, `values`/`valuesFrom`/`postRenderers`, service DNS and CRD instances. For `app-template` or other shared chart changes, check all HelmReleases that use it, since chart defaults can change even when this repo's values do not.

## 7. Verdict

- A finding names the changed line, the affected consumer or path, the concrete failure mode, and the rendered or upstream evidence. Do not guess replacement values; confirm them upstream.
- Escalate: Renovate hold violations, unsupported Talos/Kubernetes pairings, CRD or schema incompatibilities, storage or data-loss mutations, security relaxations, unexpected `suspend`/`prune`, and selector or name renames that break live consumers.
- A breaking change with no consumer in this repository is a brief observation, not a blocker.
- Without render evidence, the recommendation is at best "unverified". Never write "safe".
- Keep ordinary patch and digest PRs compact: recommendation, what changed, and any real caveat. No fabricated tool results, comparisons or post-merge checks.
