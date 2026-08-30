# Agent instructions for implementing this repository
#
# Authoritative specification:
#   docs/IMPLEMENTATION_PLAN.md
#
# Architectural review (mise + Tailscale sidecar) overrides earlier conflicting sections.
#
# Rules (from plan §52):
# 1. Do not assume APIs, download URLs, package names, or commands without confirmation.
# 2. Research current official docs before installing integrations that may have changed.
# 3. Prefer manufacturer official sources and Orca official docs/repo.
# 4. Do not replace a missing integration with a similarly named third-party package.
# 5. Make incremental changes; build/test after each phase.
# 6. When something is not officially available, keep it optional and document.
# 7. Do not break working agents for an optional one.
# 8. Keep the container lean.
# 9. No Ubuntu, no Alpine.
# 10. No FUSE, no --privileged for Orca.
# 11. No Docker socket by default.
# 12. No secrets in the image.
#
# Phase order: plan §90 (A base → B mise → C Orca → D Tailscale → E agents → F update → G optional → H security).
