# Security policy

## Reporting

Send suspected vulnerabilities privately to `hello@wotex.io`. Do not include
raw credentials, customer data, or live endpoint details in a public issue.

An acknowledgement will identify the maintainer handling the report. A public
advisory is issued after a fix and affected-version assessment are ready.

## Supported versions

No stable version is currently published. The default branch receives security
fixes, but source availability is not a support commitment.

## Security boundary

The runner executes a consumer-supplied executable. It does not provide an
operating-system sandbox. The consumer must run untrusted subjects inside an
appropriate process, container, virtual-machine, network, and filesystem
isolation boundary.

The library reduces accidental exposure by:

- invoking executables directly without a shell;
- requiring an absolute executable path;
- verifying the subject archive digest before execution;
- bounding time, stdout, argument, environment, and protocol values;
- never sending expected results to the target;
- storing observation digests instead of raw observations in reports; and
- rejecting free-form target diagnostics.

Do not put secrets in claims, vectors, target environment values, or reports.
