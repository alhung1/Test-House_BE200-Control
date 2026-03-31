# Deployment Notes

This toolkit is created in development first and is intended to be reviewed and validated locally before any later move to `192.168.22.8`.

Deployment to `192.168.22.8` is:

- manual
- deferred until after validation
- not automated by this repository

There is no automatic deployment mechanism in this toolkit.

## Current Intent

The local development/controller concept is `192.168.22.30`.

The later deployment target, after manual validation succeeds, is `192.168.22.8`.

The toolkit is intentionally designed so that the same reviewed files can be copied manually later without introducing any copy script or run script that targets `192.168.22.8`.

## What Should Eventually Be Copied

When you decide the toolkit is ready for deployment, the files to copy manually are:

- `setup-local-remoting.ps1`
- `setup-remote-remoting.ps1`
- `test-remoting.ps1`
- `discover-be200-advanced-properties.ps1`
- `export-be200-config-template.ps1`
- `validate-be200-config.ps1`
- `apply-be200-config.ps1`
- `invoke-be200-action.ps1`
- `export-be200-before-after-report.ps1`
- `internal\BE200Toolkit.Common.psm1`
- `README.md`
- `VALIDATION_GUIDE.md`
- `DEPLOYMENT_NOTES.md`

You may also choose to copy:

- the `tests\` folder if you want the same local verification assets on the eventual controller

You do not need to copy:

- old local output artifacts unless you want them for reference

## What Must Be Revalidated After Moving From 192.168.22.30 Concept To 192.168.22.8

After the toolkit is manually copied to `192.168.22.8`, revalidate:

- local remoting setup on `192.168.22.8`
- TrustedHosts on `192.168.22.8`
- credential path behavior on `192.168.22.8`
- reachability from `192.168.22.8` to `192.168.22.221` through `192.168.22.228`
- discovery behavior from `192.168.22.8`
- validation, apply, and action output paths on `192.168.22.8`
- transcript generation on `192.168.22.8`

Also confirm again that:

- the remote management path is still separate from the BE200 test adapter function
- BE200 operations only affect the exact allowlisted BE200 adapter names
- no layer-3 network commands were introduced during any local customization

## What This Toolkit Does Not Do

This toolkit does not:

- copy files to `192.168.22.8`
- schedule itself on `192.168.22.8`
- auto-run setup on `192.168.22.8`
- auto-run discovery on `192.168.22.8`
- auto-run apply on `192.168.22.8`
- auto-run BE200 actions on `192.168.22.8`

## Manual Deployment Principle

The deployment decision should happen only after you manually confirm that the toolkit behaves correctly in the local development workflow.

If validation is incomplete, keep the toolkit local and continue refining it there rather than moving it to `192.168.22.8`.
