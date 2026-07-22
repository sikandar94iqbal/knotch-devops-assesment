# CLAUDE.md — Project Context

## What this project is

A take-home assessment for a **DevOps Engineer** role at Knotch. The goal is to produce a **GitHub repository** demonstrating a secure, reproducible, GitOps-driven multi-tenant backend API platform on **Google Cloud Platform**.

This is a **portfolio/assessment deliverable**, not a real production system. Manifests and IaC only are required, though actually deploying to a free-tier GCP project and adding screenshots is strongly encouraged and boosts the score.

**Deadline:** Friday, July 24, 2026, 5pm EST.

---

## The scenario (verbatim intent)

A SaaS company runs a multi-tenant platform on GCP. We are onboarding a new tenant for their backend API service. The service must:

- Be **securely accessible to customers over the internet** (HTTPS).
- Connect to a **fully private managed database** — no public IP, no exposure outside the VPC.
- Have infrastructure that is **reproducible and version-controlled with Terraform**.
- Deploy **only through a GitOps model** — no one applies manifests manually.
- Reflect **production security practices**, even if cost-optimized for dev.

The compute platform, database service, networking model, and GitOps tooling are our choice.

---

## Required deliverables (grading checklist)

### Terraform
- [ ] Use **modules** where appropriate.
- [ ] Structure to support **at least two environments** (dev and prod).
- [ ] **Remote state** configured with a **GCS backend**.
- [ ] All resources creatable with `terraform apply` — **no manual console steps**.

### Kubernetes / Helm
- [ ] A **Helm chart** for the API service (a simple nginx or echo server is fine — no real app needed).
- [ ] Chart must include: **Deployment, Service, Ingress or Gateway, resource requests/limits, readiness and liveness probes, and a PodDisruptionBudget**.

### GitOps pipeline
- [ ] An **ArgoCD Application manifest** (or App-of-Apps) that deploys the Helm chart from git.
- [ ] A **GitHub Actions workflow** that runs `terraform plan` on PR and `terraform apply` on merge to main.

### Documentation (README.md)
- [ ] **Architecture overview** — diagram strongly encouraged.
- [ ] **How to bootstrap** the environment from scratch.
- [ ] **End-to-end GitOps workflow** explanation.
- [ ] **Answers to the 6 design questions** (below).

### Design questions to answer in README
1. **Compute:** Which GCP compute service (GKE / Cloud Run / GCE) and why? If GKE — Standard or Autopilot, and why?
2. **Database connectivity:** How does the API connect to the DB privately? Walk the network path pod → database.
3. **Credentials:** How does the app authenticate to GCP services without a service account key file?
4. **Secrets:** How are secrets (e.g. third-party API keys) managed and delivered? What lives in git vs. what doesn't?
5. **GitOps:** Step-by-step, what happens when a developer merges a Helm change? Who/what applies it to the cluster?
6. **Cost:** What choices keep dev affordable while keeping the architecture production-equivalent?

---

## Chosen architecture (decisions already made — build to these)

| Concern | Decision | Rationale |
|---|---|---|
| **Compute** | GKE **Autopilot** | No node management; pay-per-pod (cheap for dev); hardened security defaults (Workload Identity always on, Shielded Nodes, no privileged pods). Needed over Cloud Run because we need PDB/HPA/probes and a full k8s API for ArgoCD to drive. |
| **Database** | Cloud SQL for **PostgreSQL**, `ipv4_enabled = false` | Managed; private-only by construction, not by firewall rule. |
| **Private DB path** | **Private Service Access** (VPC peering) | Pod → VPC → peering → Cloud SQL private IP. Never touches internet. |
| **Ingress** | **GKE Gateway API** + Google-managed TLS cert | Modern replacement for Ingress; provisions external HTTPS LB. |
| **Credentials** | **Workload Identity** | Pods impersonate a GCP SA — zero key files. Same pattern (WIF/OIDC) for CI. |
| **Secrets** | **Secret Manager** + **External Secrets Operator** | Values in Secret Manager; only *references* in git. Auto-refresh every 1m. |
| **IaC** | Terraform, modular, **GCS remote backend**, 2 envs | Reproducible, collaborative, locked state. |
| **GitOps** | **ArgoCD** App-of-Apps, auto-sync + self-heal | Git is source of truth; no manual kubectl. |
| **CI** | GitHub Actions — plan on PR, apply on merge, **keyless auth (WIF)** | No SA key stored as a secret. |
| **Egress** | Cloud NAT | Private nodes reach internet for image pulls; no public node IPs. |

**Dev vs Prod differences (cost lever only — security identical):**
- DB tier: `db-f1-micro` (dev) vs `db-custom-2-7680` (prod)
- DB availability: `ZONAL` (dev) vs `REGIONAL`/HA (prod)
- Point-in-time recovery: off (dev) vs on (prod)
- Deletion protection: off (dev) vs on (prod)
- HPA range: 2–4 (dev) vs 3–10 (prod)

---

## Target folder structure

```
.
├── README.md
├── .gitignore
├── terraform/
│   ├── modules/
│   │   ├── network/            # VPC, subnet, Private Service Access, Cloud NAT
│   │   ├── gke/                # GKE Autopilot, private, Workload Identity
│   │   ├── database/           # Cloud SQL Postgres (private IP) + Secret Manager
│   │   └── workload-identity/  # GCP SAs + IAM bindings (app + ESO)
│   └── environments/
│       ├── dev/                # cheap sizing; wires modules; GCS backend
│       └── prod/               # HA/PITR/protected sizing; same modules
├── helm/
│   └── api-service/
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── values-dev.yaml
│       ├── values-prod.yaml
│       └── templates/          # deployment, service, serviceaccount, gateway,
│                               # hpa, pdb, externalsecret, secretstore
├── argocd/
│   ├── app-of-apps.yaml
│   └── apps/                   # api-dev.yaml, api-prod.yaml
├── .github/workflows/
│   └── terraform.yaml          # plan on PR, apply on merge
└── docs/
    └── architecture.(dot|png|svg)
```

Each Terraform module has: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`.

---

## Conventions & constraints

- **Terraform:** `>= 1.5`, provider `hashicorp/google ~> 5.0`, `random ~> 3.5`. Run `terraform fmt` before committing.
- **Naming:** prefix resources per env — `tenant-dev-*`, `tenant-prod-*`.
- **No secrets in git.** DB password is generated by `random_password`, written to Secret Manager, never output in plaintext. Only secret *names* appear in git.
- **No service account key files.** Workload Identity for pods; Workload Identity Federation (OIDC) for GitHub Actions.
- **Least privilege IAM.** Scope Secret Manager access to *specific secrets*, not project-wide roles. App SA gets only `cloudsql.client` + the two `secretAccessor` bindings.
- **Pod security:** non-root, `readOnlyRootFilesystem: true`, drop ALL capabilities, `allowPrivilegeEscalation: false`, seccomp `RuntimeDefault`. Use `nginxinc/nginx-unprivileged` as the demo image (needs a writable `/tmp` emptyDir).
- **Prod ArgoCD:** `prune: false` as a safety net so an accidental git deletion can't wipe prod resources. Dev can `prune: true`.
- **Placeholders to replace before pushing:** `REPLACE_WITH_TF_STATE_BUCKET`, `REPLACE_ORG/REPLACE_REPO`, project IDs in values files.

---

## Bootstrap sequence (document in README, in this order)

1. Create GCS state bucket (versioned, uniform access); put name in each env `backend` block.
2. Enable APIs: container, sqladmin, servicenetworking, secretmanager, compute.
3. `terraform init && plan && apply` in `terraform/environments/dev`.
4. Install ArgoCD + External Secrets Operator into the cluster (one-time), annotating the ESO k8s SA with the ESO GCP SA for Workload Identity.
5. `kubectl apply -f argocd/app-of-apps.yaml` — from here ArgoCD owns all app deploys.

---

## AI usage note (required by the assessment)

The README must include an honest AI-usage section: what was prompted for, what was accepted as-is, what was reviewed/changed. Frame AI as a pair-programming accelerator; emphasize that **security and architecture decisions were verified against GCP docs, not taken on trust.**

**Do NOT** reference or include any documents, architecture, or details from any current/previous employer. This assessment is a generic multi-tenant API scenario — keep all content original to it.

---

## Definition of done

- [ ] `terraform fmt -check` clean; `terraform validate` passes in both envs.
- [ ] `helm lint helm/api-service` passes; `helm template` renders valid k8s for dev and prod values.
- [ ] All required Helm objects present (Deployment, Service, Gateway, requests/limits, probes, PDB).
- [ ] ArgoCD app-of-apps + child apps present.
- [ ] GitHub Actions workflow: plan on PR, apply on merge.
- [ ] README complete with diagram, bootstrap, GitOps flow, all 6 design answers, AI-usage section.
- [ ] Placeholders replaced; repo pushed to GitHub.
- [ ] (Bonus) Deployed to a free-tier GCP project with `terraform output` / `kubectl get` screenshots in README.
