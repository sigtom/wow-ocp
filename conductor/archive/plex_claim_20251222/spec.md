# Specification: Plex Server Claiming Procedure

## Overview
This track executes a time-sensitive procedure to claim the Plex Media Server. It involves temporarily bypassing standard GitOps flows to inject a short-lived `PLEX_CLAIM` token.

## Functional Requirements
- **Preparation:** Update Plex Deployment to support `PLEX_CLAIM` env var from a Secret.
- **Operational Sequence:**
    1.  Pause ArgoCD Sync for `plex` app.
    2.  Scale Plex deployment to 0.
    3.  (User Action) Delete `Preferences.xml` from storage.
    4.  (User Action) Update `.env` with fresh `PLEX_CLAIM`.
    5.  Generate and **Directly Apply** the `plex-claim` Secret to the cluster.
    6.  Scale Plex deployment to 1.
- **Post-Operation:** Commit the SealedSecret to Git to restore GitOps state.

## Non-Functional Requirements
- **Speed:** The "Apply" step must happen immediately after token generation.
- **Safety:** Ensure `Preferences.xml` is gone before starting.

## Acceptance Criteria
- [ ] Plex deployment is configured to read `PLEX_CLAIM` from a secret.
- [ ] Fresh token is applied to the cluster.
- [ ] Plex starts up and successfully claims the server.
- [ ] GitOps state is reconciled (SealedSecret committed).
