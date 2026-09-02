# Governance

## Roles

- Maintainers review contracts, releases, security reports, and repository
  administration.
- Contributors propose changes through issues and pull requests.
- Consumers provide implementation experience and compatibility reports.

## Decisions

Routine changes require one maintainer approval and green CI. Wire-incompatible
changes, governance changes, and stable-release commitments require two
maintainer approvals and a recorded public rationale.

## Releases

Each release is independently versioned. Release evidence includes the source
revision, archive digest, dependency lock digest, supported Elixir/OTP matrix,
specification versions, vector digests, and verification commands. A release is
withheld when evidence is incomplete.

## Security and access

Maintainer and package-publisher accounts use multi-factor authentication and
least privilege. Security fixes may be prepared privately until coordinated
disclosure. Administrative access is reviewed when maintainers change.

## Project continuity

If active maintenance ends, maintainers publish the status, stop compatibility
claims that can no longer be supported, and provide source and release evidence
needed for consumers to migrate or continue maintenance.
