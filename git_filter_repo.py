gitd7b75aca907380f608892cc289e616f195427b99-filter-repo## Summary

Fix a crash caused by Rust SDK logging initialization failing during app startup.

When the Rust logging subsystem cannot initialize, the app should not crash. Instead, it should log the error and continue running.

## Changes

- Guard the Rust SDK logging initialization path against failures.
- Log the initialization error instead of crashing the app.
- Keep app startup resilient when the Rust logging backend is unavailable or misconfigured.

## Testing

- Verified the app no longer crashes when Rust logging initialization fails.
- Confirmed the initialization error is logged for debugging.

## Checklist

- [x] I have added a clear description for this PR.
- [x] I have added exactly one appropriate `PR-` label.