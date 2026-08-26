# Course Audit

## Scope

This audit compares the narrative curriculum with the executable chapter
overlays and README lessons. The implementation is intentionally cumulative,
but several concepts were previously implied rather than taught explicitly.

## Findings And Remediation

| Finding | Risk for learners | Remediation |
|---|---|---|
| No shared diagram notation | Solid, blocked, and control-plane paths could be confused | Added `GLOSSARY.md` and a legend to every chapter diagram |
| No visual checkpoint per chapter | The topology change was difficult to see between stages | Added `diagram.dot`, `diagram.svg`, and `diagram.png` to every chapter |
| NAT was described as a rule instead of a packet transformation | Learners could confuse routing, forwarding, and source translation | Added a before/after packet walk and return-flow explanation to `GLOSSARY.md` and chapter 10 |
| Expected command output was underspecified | A learner could run a command without knowing what proves success | Added expected observations, interpretation prompts, and negative results to the chapter notes |
| Docker bridge versus VPC behavior was not bounded | Learners could assume the lab is a cloud VPC implementation | Added an explicit limits section to `GLOSSARY.md` |
| Firewall layers were easy to conflate | `iptables FORWARD`, container `INPUT`, and PostgreSQL `pg_hba.conf` have different jobs | Added a layer table to `GLOSSARY.md` and chapter 08/13 notes |
| DNS and service discovery were treated as one feature | IP reachability, Docker DNS, and upstream DNS have different failure modes | Added a three-hop DNS model and troubleshooting matrix |
| Runtime state and persistent state were not consistently separated | Manual routes and firewall rules can disappear on recreation | Added a persistence checklist to chapter 16 and the glossary |
| Failure experiments lacked recovery guidance | A learner could leave the shared lab in a broken state | Added before/after commands and a reset rule to chapter 17 |
| Fixed CIDRs can conflict with unrelated Docker networks | Docker may reject a valid lab before the lesson starts | Added a preflight command and warning to the root README |

## Remaining Deliberate Limitations

- The lab models routing and filtering inside containers; it is not a
  production VPC, cloud firewall, or managed database.
- The credentials are intentionally static local-lab credentials and must not
  be reused elsewhere.
- The runner requires the chapter overlays to be loaded in order. Running an
  overlay file directly is not a supported workflow.
- Live network validation still depends on Docker capabilities, available
  CIDRs, image access, and a Linux-capable Docker engine.
