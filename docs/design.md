# Design: hardened Ubuntu 24.04 golden image

Status: draft · Owner: Kenneth Chinedu · Date: 2026-11-01

## Context
Servers launch from the stock Canonical Ubuntu 24.04 AMI and are hardened by hand, or not at all.
Every instance differs a little, nobody can say which CIS controls are applied, and the gap between
boot and hardening leaves each new instance on default settings while it is already reachable.

## Goals
- One pipeline that builds an AWS AMI from the stock Ubuntu 24.04 AMI, applies a documented subset
  of CIS Level 1 (Server) with Ansible, and publishes the AMI only if an independent scan passes.
- Every control is accounted for in `docs/controls.md`: applied, or excepted with a reason.
- The role is idempotent: a second run reports `changed=0`.
- The build runs on every merge to `main` and weekly, so OS patches reach the image without anyone
  logging in to a server.
- No long-lived cloud credentials: GitHub Actions reaches AWS through OIDC.

## Non-goals
- Other distributions (RHEL, Amazon Linux) and other clouds (Azure comes later as a second Packer source).
- CIS Level 2.
- Claiming "CIS compliant". The README states coverage as a number.
- Runtime drift detection on running instances (AWS Config / InSpec, out of scope here).
- Environment-specific configuration: hostname, app config, secrets. Those happen at boot, never in the image.

## Design
```
push to main / weekly schedule
  → lint (ansible-lint, yamllint, packer fmt + validate)
  → Molecule: converge twice, second run must be changed=0
  → Packer (GHA, OIDC role in AWS):
        temp EC2 from the latest Canonical Ubuntu 24.04 AMI
        → Ansible role cis_ubuntu2404
        → OpenSCAP scan, SCAP Security Guide CIS L1 Server profile
        → score below threshold or a regression on an applied control: fail, no AMI
        → AMI tagged with version + git SHA, scan report attached to the run
```
- **One role, one file per benchmark section**, one on/off variable per control in `defaults/main.yml`,
  so a user can switch off a control their workload can't take and the exception is visible.
- **Own drop-in files rather than editing vendor files.** sshd settings go in
  `/etc/ssh/sshd_config.d/00-cis-hardening.conf`. sshd takes the first value it reads and reads
  drop-ins alphabetically, so `00-` beats `50-cloud-init.conf`. The filename is not trusted alone:
  the role checks the setting sshd actually uses (`sshd -T`) after writing.
- **Audit is separate from remediation.** Ansible changes the system; OpenSCAP, written by other
  people, judges it. Ansible reporting `ok` is not evidence.
- **Bake the baseline, configure at boot.** Everything identical across environments is in the image;
  user-data only handles what differs per environment.

## Alternatives considered
- **Configure at boot only (Ansible from user-data).** Rejected: a failed run leaves a half-hardened
  instance serving traffic, every scale-out waits for hardening, boot depends on package mirrors, and
  instances built on different days differ.
- **Use ansible-lockdown's UBUNTU24-CIS role.** Mature and broad, the right choice for a team that
  only needs the result. Rejected here because the point is to understand each control; it stays as a
  reference to compare against.
- **Edit `sshd_config` or `50-cloud-init.conf` in place.** Rejected: the package owns `sshd_config`
  and upgrades can replace or conflict with edits; cloud-init rewrites its file at first boot of each
  instance; editing someone else's file with regexes is fragile.
- **Grade with our own tests only (goss/InSpec).** Rejected as the gate: tests written by the same
  person as the role share its blind spots. Own tests stay as fast feedback in Molecule.

## Risks
| Risk | Mitigation |
|---|---|
| A bad sshd config locks everyone out | validate with `sshd -t` before the file is put in place; Packer still connects to prove SSH works |
| A control breaks cloud-init or SSM agent | launch a test instance from each new AMI and check SSH + SSM before publishing |
| Another drop-in overrides ours silently | `sshd -T` check in the role; the OpenSCAP scan catches it independently |
| A `Match` block re-enables a setting for some users or addresses; plain `sshd -T` shows only the global value | role ships no `Match` blocks; check with `sshd -T -C user=…,addr=…` for any that exist |
| Scan profile version differs from the benchmark version used | pin the SCAP Security Guide version; record both versions in the report |
| Docker-based Molecule can't test kernel, mounts, systemd | Molecule for logic and idempotence only; the real proof is the scan on the EC2 build |
| AMI and snapshot costs grow | keep the last N versions, deregister older AMIs and delete their snapshots |

## Test plan
1. Idempotence: Molecule converges twice; the second run must be `changed=0`.
2. Gate red then green: remove the `PermitRootLogin no` task, build fails on the scan; restore it, build passes.
3. Override caught: plant `10-legacy.conf` with `PermitRootLogin yes` in a test; role or scan must fail.
4. Before/after score: scan the stock AMI and the hardened AMI with the same profile; both numbers go in the README.
5. Boot check: launch from the new AMI, confirm SSH and SSM work, then terminate.
