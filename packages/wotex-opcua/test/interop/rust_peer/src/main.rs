// SPDX-License-Identifier: Apache-2.0

use std::{
    env, fs,
    net::TcpListener,
    path::{Path, PathBuf},
    process::ExitCode,
    time::Duration,
};

use opcua::{
    crypto::SecurityPolicy,
    nodes::{MethodBuilder, ObjectBuilder, VariableBuilder},
    server::{
        diagnostics::NamespaceMetadata,
        node_manager::memory::{simple_node_manager, SimpleNodeManager},
        Limits, ServerBuilder, ServerUserToken, ANONYMOUS_USER_TOKEN_ID,
    },
    types::{
        type_loader::ByteStringBody, Array, ByteString, DataTypeId, DateTime, ExtensionObject,
        Guid, MessageSecurityMode, NodeId, ObjectId, ObjectTypeId, StatusCode, Variant,
        VariantScalarTypeId,
    },
};
use tokio::io::AsyncReadExt;

const NAMESPACE_URI: &str = "urn:wotex:rust-fixture";
const APPLICATION_URI: &str = "urn:wotex:fixture:server";
const USERNAME_TOKEN_ID: &str = "USERNAME";
const CERTIFICATE_TOKEN_ID: &str = "CERTIFICATE";
const USERNAME: &str = "operator";
const PASSWORD: &str = "correct horse";

#[derive(Clone, Copy)]
enum FixtureVariant {
    Default,
    ExpiredLeaf,
    WrongHost,
    WrongApplicationUri,
    UntrustedCa,
    RevokedLeaf,
    ExpiredCrl,
    MismatchedPrivateKey,
    NoneDowngrade,
    UnsupportedUserToken,
    ShortSecureChannel,
    BadWriteSession,
    ServerLoss,
    LostBrowse,
    LostBrowseNext,
    LostBrowseRelease,
    BadBrowseRelease,
    MissingBrowseReleaseResult,
    ExtraBrowseReleaseResult,
    ReferencedBrowseRelease,
    ContinuedBrowseRelease,
    DiagnosedBrowseRelease,
    BadBrowseReleaseService,
    MissingBrowseResult,
    ExtraBrowseResult,
    OversizedBrowsePage,
    OversizedBrowseContinuation,
    DiagnosedBrowse,
    MissingBrowseNextResult,
    ExtraBrowseNextResult,
    OversizedBrowseNextPage,
    OversizedBrowseNextContinuation,
    DiagnosedBrowseNext,
    UncertainBrowse,
    BadBrowse,
    BadBrowseService,
    UncertainBrowseNext,
    BadBrowseNext,
    BadBrowseNextService,
    EmptyBrowsePage,
    EmptyBrowseNextPage,
    RemoteBrowseReference,
    RemoteBrowseNextReference,
    UnknownNamespaceBrowseReference,
    UnknownNamespaceBrowseNextReference,
    RemoteBrowseTypeDefinition,
    RemoteBrowseNextTypeDefinition,
    UnknownLocalBrowseNode,
    UnknownLocalBrowseNextNode,
    UnknownLocalBrowseReferenceType,
    UnknownLocalBrowseNextReferenceType,
    UnknownLocalBrowseTypeDefinition,
    UnknownLocalBrowseNextTypeDefinition,
    DuplicateBrowseReference,
    DuplicateBrowseNextReference,
    NamedBrowseReference,
    NamedBrowseNextReference,
    UnspecifiedBrowseNodeClass,
    UnspecifiedBrowseNextNodeClass,
    NullEmptyBrowseName,
    NullEmptyBrowseNextName,
    NullBrowseTypeDefinition,
    NullBrowseNextTypeDefinition,
    AggregateBrowseBytes,
    InvalidSubscriptionPublishingInterval,
    InvalidSubscriptionKeepalive,
    InvalidSubscriptionLifetime,
    MissingMonitoredItemResult,
    ExtraMonitoredItemResult,
    BadMonitoredItemStatus,
    ZeroMonitoredItemId,
    InvalidMonitoredItemSamplingInterval,
    InvalidMonitoredItemQueueSize,
    DiagnosedMonitoredItem,
    BadMonitoredItemService,
    MissingDeleteMonitoredItemResult,
    ExtraDeleteMonitoredItemResult,
    BadDeleteMonitoredItemStatus,
    DiagnosedDeleteMonitoredItem,
    BadDeleteMonitoredItemService,
    MissingDeleteSubscriptionResult,
    ExtraDeleteSubscriptionResult,
    BadDeleteSubscriptionStatus,
    DiagnosedDeleteSubscription,
    BadDeleteSubscriptionService,
    DuplicatePublish,
    ConflictingDuplicatePublish,
    OversizedPublishGap,
    ZeroPublishSequence,
    UnknownPublishClientHandle,
    StatusChangePublish,
    BadPublishAcknowledgement,
}

impl FixtureVariant {
    fn parse(value: &str) -> Result<Self, String> {
        match value {
            "default" => Ok(Self::Default),
            "expired_leaf" => Ok(Self::ExpiredLeaf),
            "wrong_host" => Ok(Self::WrongHost),
            "wrong_application_uri" => Ok(Self::WrongApplicationUri),
            "untrusted_ca" => Ok(Self::UntrustedCa),
            "revoked_leaf" => Ok(Self::RevokedLeaf),
            "expired_crl" => Ok(Self::ExpiredCrl),
            "mismatched_private_key" => Ok(Self::MismatchedPrivateKey),
            "none_downgrade" => Ok(Self::NoneDowngrade),
            "unsupported_user_token" => Ok(Self::UnsupportedUserToken),
            "short_secure_channel" => Ok(Self::ShortSecureChannel),
            "bad_write_session" => Ok(Self::BadWriteSession),
            "server_loss" => Ok(Self::ServerLoss),
            "lost_browse" => Ok(Self::LostBrowse),
            "lost_browse_next" => Ok(Self::LostBrowseNext),
            "lost_browse_release" => Ok(Self::LostBrowseRelease),
            "bad_browse_release" => Ok(Self::BadBrowseRelease),
            "missing_browse_release_result" => Ok(Self::MissingBrowseReleaseResult),
            "extra_browse_release_result" => Ok(Self::ExtraBrowseReleaseResult),
            "referenced_browse_release" => Ok(Self::ReferencedBrowseRelease),
            "continued_browse_release" => Ok(Self::ContinuedBrowseRelease),
            "diagnosed_browse_release" => Ok(Self::DiagnosedBrowseRelease),
            "bad_browse_release_service" => Ok(Self::BadBrowseReleaseService),
            "missing_browse_result" => Ok(Self::MissingBrowseResult),
            "extra_browse_result" => Ok(Self::ExtraBrowseResult),
            "oversized_browse_page" => Ok(Self::OversizedBrowsePage),
            "oversized_browse_continuation" => Ok(Self::OversizedBrowseContinuation),
            "diagnosed_browse" => Ok(Self::DiagnosedBrowse),
            "missing_browse_next_result" => Ok(Self::MissingBrowseNextResult),
            "extra_browse_next_result" => Ok(Self::ExtraBrowseNextResult),
            "oversized_browse_next_page" => Ok(Self::OversizedBrowseNextPage),
            "oversized_browse_next_continuation" => Ok(Self::OversizedBrowseNextContinuation),
            "diagnosed_browse_next" => Ok(Self::DiagnosedBrowseNext),
            "uncertain_browse" => Ok(Self::UncertainBrowse),
            "bad_browse" => Ok(Self::BadBrowse),
            "bad_browse_service" => Ok(Self::BadBrowseService),
            "uncertain_browse_next" => Ok(Self::UncertainBrowseNext),
            "bad_browse_next" => Ok(Self::BadBrowseNext),
            "bad_browse_next_service" => Ok(Self::BadBrowseNextService),
            "empty_browse_page" => Ok(Self::EmptyBrowsePage),
            "empty_browse_next_page" => Ok(Self::EmptyBrowseNextPage),
            "remote_browse_reference" => Ok(Self::RemoteBrowseReference),
            "remote_browse_next_reference" => Ok(Self::RemoteBrowseNextReference),
            "unknown_namespace_browse_reference" => Ok(Self::UnknownNamespaceBrowseReference),
            "unknown_namespace_browse_next_reference" => {
                Ok(Self::UnknownNamespaceBrowseNextReference)
            }
            "remote_browse_type_definition" => Ok(Self::RemoteBrowseTypeDefinition),
            "remote_browse_next_type_definition" => Ok(Self::RemoteBrowseNextTypeDefinition),
            "unknown_local_browse_node" => Ok(Self::UnknownLocalBrowseNode),
            "unknown_local_browse_next_node" => Ok(Self::UnknownLocalBrowseNextNode),
            "unknown_local_browse_reference_type" => Ok(Self::UnknownLocalBrowseReferenceType),
            "unknown_local_browse_next_reference_type" => {
                Ok(Self::UnknownLocalBrowseNextReferenceType)
            }
            "unknown_local_browse_type_definition" => Ok(Self::UnknownLocalBrowseTypeDefinition),
            "unknown_local_browse_next_type_definition" => {
                Ok(Self::UnknownLocalBrowseNextTypeDefinition)
            }
            "duplicate_browse_reference" => Ok(Self::DuplicateBrowseReference),
            "duplicate_browse_next_reference" => Ok(Self::DuplicateBrowseNextReference),
            "named_browse_reference" => Ok(Self::NamedBrowseReference),
            "named_browse_next_reference" => Ok(Self::NamedBrowseNextReference),
            "unspecified_browse_node_class" => Ok(Self::UnspecifiedBrowseNodeClass),
            "unspecified_browse_next_node_class" => Ok(Self::UnspecifiedBrowseNextNodeClass),
            "null_empty_browse_name" => Ok(Self::NullEmptyBrowseName),
            "null_empty_browse_next_name" => Ok(Self::NullEmptyBrowseNextName),
            "null_browse_type_definition" => Ok(Self::NullBrowseTypeDefinition),
            "null_browse_next_type_definition" => Ok(Self::NullBrowseNextTypeDefinition),
            "aggregate_browse_bytes" => Ok(Self::AggregateBrowseBytes),
            "invalid_subscription_publishing_interval" => {
                Ok(Self::InvalidSubscriptionPublishingInterval)
            }
            "invalid_subscription_keepalive" => Ok(Self::InvalidSubscriptionKeepalive),
            "invalid_subscription_lifetime" => Ok(Self::InvalidSubscriptionLifetime),
            "missing_monitored_item_result" => Ok(Self::MissingMonitoredItemResult),
            "extra_monitored_item_result" => Ok(Self::ExtraMonitoredItemResult),
            "bad_monitored_item_status" => Ok(Self::BadMonitoredItemStatus),
            "zero_monitored_item_id" => Ok(Self::ZeroMonitoredItemId),
            "invalid_monitored_item_sampling_interval" => {
                Ok(Self::InvalidMonitoredItemSamplingInterval)
            }
            "invalid_monitored_item_queue_size" => Ok(Self::InvalidMonitoredItemQueueSize),
            "diagnosed_monitored_item" => Ok(Self::DiagnosedMonitoredItem),
            "bad_monitored_item_service" => Ok(Self::BadMonitoredItemService),
            "missing_delete_monitored_item_result" => Ok(Self::MissingDeleteMonitoredItemResult),
            "extra_delete_monitored_item_result" => Ok(Self::ExtraDeleteMonitoredItemResult),
            "bad_delete_monitored_item_status" => Ok(Self::BadDeleteMonitoredItemStatus),
            "diagnosed_delete_monitored_item" => Ok(Self::DiagnosedDeleteMonitoredItem),
            "bad_delete_monitored_item_service" => Ok(Self::BadDeleteMonitoredItemService),
            "missing_delete_subscription_result" => Ok(Self::MissingDeleteSubscriptionResult),
            "extra_delete_subscription_result" => Ok(Self::ExtraDeleteSubscriptionResult),
            "bad_delete_subscription_status" => Ok(Self::BadDeleteSubscriptionStatus),
            "diagnosed_delete_subscription" => Ok(Self::DiagnosedDeleteSubscription),
            "bad_delete_subscription_service" => Ok(Self::BadDeleteSubscriptionService),
            "duplicate_publish" => Ok(Self::DuplicatePublish),
            "conflicting_duplicate_publish" => Ok(Self::ConflictingDuplicatePublish),
            "oversized_publish_gap" => Ok(Self::OversizedPublishGap),
            "zero_publish_sequence" => Ok(Self::ZeroPublishSequence),
            "unknown_publish_client_handle" => Ok(Self::UnknownPublishClientHandle),
            "status_change_publish" => Ok(Self::StatusChangePublish),
            "bad_publish_acknowledgement" => Ok(Self::BadPublishAcknowledgement),
            _ => Err(format!("unsupported fixture variant: {value}")),
        }
    }

    fn name(self) -> &'static str {
        match self {
            Self::Default => "default",
            Self::ExpiredLeaf => "expired_leaf",
            Self::WrongHost => "wrong_host",
            Self::WrongApplicationUri => "wrong_application_uri",
            Self::UntrustedCa => "untrusted_ca",
            Self::RevokedLeaf => "revoked_leaf",
            Self::ExpiredCrl => "expired_crl",
            Self::MismatchedPrivateKey => "mismatched_private_key",
            Self::NoneDowngrade => "none_downgrade",
            Self::UnsupportedUserToken => "unsupported_user_token",
            Self::ShortSecureChannel => "short_secure_channel",
            Self::BadWriteSession => "bad_write_session",
            Self::ServerLoss => "server_loss",
            Self::LostBrowse => "lost_browse",
            Self::LostBrowseNext => "lost_browse_next",
            Self::LostBrowseRelease => "lost_browse_release",
            Self::BadBrowseRelease => "bad_browse_release",
            Self::MissingBrowseReleaseResult => "missing_browse_release_result",
            Self::ExtraBrowseReleaseResult => "extra_browse_release_result",
            Self::ReferencedBrowseRelease => "referenced_browse_release",
            Self::ContinuedBrowseRelease => "continued_browse_release",
            Self::DiagnosedBrowseRelease => "diagnosed_browse_release",
            Self::BadBrowseReleaseService => "bad_browse_release_service",
            Self::MissingBrowseResult => "missing_browse_result",
            Self::ExtraBrowseResult => "extra_browse_result",
            Self::OversizedBrowsePage => "oversized_browse_page",
            Self::OversizedBrowseContinuation => "oversized_browse_continuation",
            Self::DiagnosedBrowse => "diagnosed_browse",
            Self::MissingBrowseNextResult => "missing_browse_next_result",
            Self::ExtraBrowseNextResult => "extra_browse_next_result",
            Self::OversizedBrowseNextPage => "oversized_browse_next_page",
            Self::OversizedBrowseNextContinuation => "oversized_browse_next_continuation",
            Self::DiagnosedBrowseNext => "diagnosed_browse_next",
            Self::UncertainBrowse => "uncertain_browse",
            Self::BadBrowse => "bad_browse",
            Self::BadBrowseService => "bad_browse_service",
            Self::UncertainBrowseNext => "uncertain_browse_next",
            Self::BadBrowseNext => "bad_browse_next",
            Self::BadBrowseNextService => "bad_browse_next_service",
            Self::EmptyBrowsePage => "empty_browse_page",
            Self::EmptyBrowseNextPage => "empty_browse_next_page",
            Self::RemoteBrowseReference => "remote_browse_reference",
            Self::RemoteBrowseNextReference => "remote_browse_next_reference",
            Self::UnknownNamespaceBrowseReference => "unknown_namespace_browse_reference",
            Self::UnknownNamespaceBrowseNextReference => "unknown_namespace_browse_next_reference",
            Self::RemoteBrowseTypeDefinition => "remote_browse_type_definition",
            Self::RemoteBrowseNextTypeDefinition => "remote_browse_next_type_definition",
            Self::UnknownLocalBrowseNode => "unknown_local_browse_node",
            Self::UnknownLocalBrowseNextNode => "unknown_local_browse_next_node",
            Self::UnknownLocalBrowseReferenceType => "unknown_local_browse_reference_type",
            Self::UnknownLocalBrowseNextReferenceType => "unknown_local_browse_next_reference_type",
            Self::UnknownLocalBrowseTypeDefinition => "unknown_local_browse_type_definition",
            Self::UnknownLocalBrowseNextTypeDefinition => {
                "unknown_local_browse_next_type_definition"
            }
            Self::DuplicateBrowseReference => "duplicate_browse_reference",
            Self::DuplicateBrowseNextReference => "duplicate_browse_next_reference",
            Self::NamedBrowseReference => "named_browse_reference",
            Self::NamedBrowseNextReference => "named_browse_next_reference",
            Self::UnspecifiedBrowseNodeClass => "unspecified_browse_node_class",
            Self::UnspecifiedBrowseNextNodeClass => "unspecified_browse_next_node_class",
            Self::NullEmptyBrowseName => "null_empty_browse_name",
            Self::NullEmptyBrowseNextName => "null_empty_browse_next_name",
            Self::NullBrowseTypeDefinition => "null_browse_type_definition",
            Self::NullBrowseNextTypeDefinition => "null_browse_next_type_definition",
            Self::AggregateBrowseBytes => "aggregate_browse_bytes",
            Self::InvalidSubscriptionPublishingInterval => {
                "invalid_subscription_publishing_interval"
            }
            Self::InvalidSubscriptionKeepalive => "invalid_subscription_keepalive",
            Self::InvalidSubscriptionLifetime => "invalid_subscription_lifetime",
            Self::MissingMonitoredItemResult => "missing_monitored_item_result",
            Self::ExtraMonitoredItemResult => "extra_monitored_item_result",
            Self::BadMonitoredItemStatus => "bad_monitored_item_status",
            Self::ZeroMonitoredItemId => "zero_monitored_item_id",
            Self::InvalidMonitoredItemSamplingInterval => {
                "invalid_monitored_item_sampling_interval"
            }
            Self::InvalidMonitoredItemQueueSize => "invalid_monitored_item_queue_size",
            Self::DiagnosedMonitoredItem => "diagnosed_monitored_item",
            Self::BadMonitoredItemService => "bad_monitored_item_service",
            Self::MissingDeleteMonitoredItemResult => "missing_delete_monitored_item_result",
            Self::ExtraDeleteMonitoredItemResult => "extra_delete_monitored_item_result",
            Self::BadDeleteMonitoredItemStatus => "bad_delete_monitored_item_status",
            Self::DiagnosedDeleteMonitoredItem => "diagnosed_delete_monitored_item",
            Self::BadDeleteMonitoredItemService => "bad_delete_monitored_item_service",
            Self::MissingDeleteSubscriptionResult => "missing_delete_subscription_result",
            Self::ExtraDeleteSubscriptionResult => "extra_delete_subscription_result",
            Self::BadDeleteSubscriptionStatus => "bad_delete_subscription_status",
            Self::DiagnosedDeleteSubscription => "diagnosed_delete_subscription",
            Self::BadDeleteSubscriptionService => "bad_delete_subscription_service",
            Self::DuplicatePublish => "duplicate_publish",
            Self::ConflictingDuplicatePublish => "conflicting_duplicate_publish",
            Self::OversizedPublishGap => "oversized_publish_gap",
            Self::ZeroPublishSequence => "zero_publish_sequence",
            Self::UnknownPublishClientHandle => "unknown_publish_client_handle",
            Self::StatusChangePublish => "status_change_publish",
            Self::BadPublishAcknowledgement => "bad_publish_acknowledgement",
        }
    }

    fn certificate_stem(self) -> &'static str {
        match self {
            Self::ExpiredLeaf => "expired",
            Self::WrongHost => "wronghost",
            _ => "server",
        }
    }

    fn config_name(self) -> String {
        match self {
            Self::Default => "rust-config.json".to_owned(),
            _ => format!("rust-config-{}.json", self.name()),
        }
    }

    fn result_name(self) -> String {
        format!("rust-result-{}.json", self.name())
    }
}

#[tokio::main(flavor = "multi_thread")]
async fn main() -> ExitCode {
    match run().await {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("{message}");
            ExitCode::from(70)
        }
    }
}

async fn run() -> Result<(), String> {
    let arguments = env::args().collect::<Vec<_>>();
    if arguments.len() == 2 && arguments[1] == "--version" {
        println!("wotex-opcua-rust-peer 1");
        return Ok(());
    }
    if !(3..=4).contains(&arguments.len()) {
        return Err("usage: wotex-opcua-rust-peer FIXTURE_DIRECTORY CHILDREN [VARIANT]".to_owned());
    }
    let fixture = PathBuf::from(&arguments[1]);
    let children = arguments[2]
        .parse::<u32>()
        .map_err(|_| "CHILDREN must be an integer".to_owned())?;
    if !(1..=1000).contains(&children) {
        return Err("CHILDREN must be between 1 and 1000".to_owned());
    }
    let variant = FixtureVariant::parse(arguments.get(3).map_or("default", String::as_str))?;

    configure_browse_fault(&fixture, variant)?;
    configure_subscription_fault(variant);
    configure_write_fault(variant);

    let port = available_port()?;
    let pki = prepare_pki(&fixture, variant)?;
    let endpoint = format!("opc.tcp://127.0.0.1:{port}/fixture");
    let manager_builder = simple_node_manager(
        NamespaceMetadata {
            namespace_uri: NAMESPACE_URI.to_owned(),
            ..Default::default()
        },
        "wotex-rust-peer",
    );
    let user_certificate = fixture.join("user.der");
    let token_ids = [
        ANONYMOUS_USER_TOKEN_ID,
        USERNAME_TOKEN_ID,
        CERTIFICATE_TOKEN_ID,
    ];
    let anonymous_token = [ANONYMOUS_USER_TOKEN_ID];
    let mut limits = Limits::default();
    limits.subscriptions.max_subscriptions_per_session = 64;
    let mut builder = ServerBuilder::new()
        .application_name("Wotex async-opcua fixture")
        .application_uri(APPLICATION_URI)
        .product_uri("urn:wotex:async-opcua-fixture")
        .certificate_path("own/server.der")
        .private_key_path("private/server.pem")
        .pki_dir(pki)
        // Fixture-only: async-opcua validates the exact copied client leaf but
        // does not build trust from the C peer's CA filename convention.
        .trust_client_certs(true)
        .host("127.0.0.1")
        .port(port)
        .discovery_urls(vec!["/fixture".to_owned()])
        .add_user_token(
            USERNAME_TOKEN_ID,
            ServerUserToken::user_pass(USERNAME, PASSWORD),
        )
        .add_user_token(
            CERTIFICATE_TOKEN_ID,
            ServerUserToken::x509("certificate", &user_certificate),
        )
        .limits(limits)
        .max_browse_continuation_points(128)
        .with_node_manager(manager_builder);

    if matches!(variant, FixtureVariant::ShortSecureChannel) {
        builder = builder.max_secure_channel_token_lifetime_ms(1000);
    }

    if matches!(variant, FixtureVariant::NoneDowngrade) {
        builder = builder
            .add_endpoint(
                "none",
                (
                    "/fixture",
                    SecurityPolicy::None,
                    MessageSecurityMode::None,
                    &anonymous_token as &[&str],
                ),
            )
            .default_endpoint("none");
    } else {
        let endpoint_tokens = if matches!(variant, FixtureVariant::UnsupportedUserToken) {
            &anonymous_token as &[&str]
        } else {
            &token_ids as &[&str]
        };
        builder = builder
            .add_endpoint(
                "basic256sha256",
                (
                    "/fixture",
                    SecurityPolicy::Basic256Sha256,
                    MessageSecurityMode::SignAndEncrypt,
                    endpoint_tokens,
                ),
            )
            .add_endpoint(
                "aes128_sha256_rsaoaep",
                (
                    "/fixture",
                    SecurityPolicy::Aes128Sha256RsaOaep,
                    MessageSecurityMode::SignAndEncrypt,
                    endpoint_tokens,
                ),
            )
            .add_endpoint(
                "aes256_sha256_rsapss",
                (
                    "/fixture",
                    SecurityPolicy::Aes256Sha256RsaPss,
                    MessageSecurityMode::SignAndEncrypt,
                    endpoint_tokens,
                ),
            )
            .default_endpoint("basic256sha256");
    }

    let (server, handle) = builder
        .build()
        .map_err(|error| format!("cannot build Rust peer: {error}"))?;

    let namespace = handle
        .get_namespace_index(NAMESPACE_URI)
        .ok_or_else(|| "fixture namespace was not registered".to_owned())?;
    let manager = handle
        .node_managers()
        .get_of_type::<SimpleNodeManager>()
        .ok_or_else(|| "fixture node manager is unavailable".to_owned())?;
    populate(&manager, &handle, namespace, children)?;

    let ready_handle = handle.clone();
    let ready_fixture = fixture.clone();
    let ready_endpoint = endpoint.clone();
    let ready = tokio::spawn(async move {
        let result = publish_config(&ready_fixture, &ready_endpoint, port, children, variant).await;
        if result.is_err() {
            ready_handle.cancel();
        }
        result
    });
    let stop_handle = handle.clone();
    tokio::spawn(async move {
        let mut input = Vec::new();
        let _ = tokio::io::stdin().read_to_end(&mut input).await;
        stop_handle.cancel();
    });

    let server_result = server.run().await.map_err(|error| error.to_string());
    let ready_result = ready
        .await
        .map_err(|error| format!("readiness task failed: {error}"))?;
    ready_result?;
    publish_result(&fixture, variant, handle.application_request_count())?;
    server_result
}

fn available_port() -> Result<u16, String> {
    TcpListener::bind(("127.0.0.1", 0))
        .and_then(|listener| listener.local_addr())
        .map(|address| address.port())
        .map_err(|error| format!("cannot reserve fixture port: {error}"))
}

fn configure_browse_fault(fixture: &Path, variant: FixtureVariant) -> Result<(), String> {
    if matches!(variant, FixtureVariant::AggregateBrowseBytes) {
        env::set_var("WOTEX_OPCUA_RUST_BROWSE_PAGE_CAP", "4");
        env::set_var("WOTEX_OPCUA_RUST_BROWSE_NAME_BYTES", "26000");
        return Ok(());
    }

    if matches!(
        variant,
        FixtureVariant::RemoteBrowseNextReference
            | FixtureVariant::UnknownNamespaceBrowseNextReference
            | FixtureVariant::RemoteBrowseNextTypeDefinition
            | FixtureVariant::UnknownLocalBrowseNextNode
            | FixtureVariant::UnknownLocalBrowseNextReferenceType
            | FixtureVariant::UnknownLocalBrowseNextTypeDefinition
            | FixtureVariant::DuplicateBrowseNextReference
            | FixtureVariant::NamedBrowseNextReference
            | FixtureVariant::UnspecifiedBrowseNextNodeClass
            | FixtureVariant::NullEmptyBrowseNextName
            | FixtureVariant::NullBrowseNextTypeDefinition
            | FixtureVariant::BadBrowseNextService
    ) {
        env::set_var("WOTEX_OPCUA_RUST_BROWSE_PAGE_CAP", "5");
    }

    match variant {
        FixtureVariant::BadBrowseService => {
            env::set_var("WOTEX_OPCUA_RUST_BAD_BROWSE_SERVICE", "1");
            return Ok(());
        }

        FixtureVariant::BadBrowseNextService => {
            env::set_var("WOTEX_OPCUA_RUST_BAD_BROWSE_NEXT_SERVICE", "1");
            return Ok(());
        }

        _ => {}
    }

    let malformed_browse_next = match variant {
        FixtureVariant::MissingBrowseNextResult => Some("missing_result"),
        FixtureVariant::ExtraBrowseNextResult => Some("extra_result"),
        FixtureVariant::OversizedBrowseNextPage => Some("oversized_page"),
        FixtureVariant::OversizedBrowseNextContinuation => Some("oversized_continuation"),
        FixtureVariant::DiagnosedBrowseNext => Some("diagnostic"),
        FixtureVariant::UncertainBrowseNext => Some("uncertain"),
        FixtureVariant::BadBrowseNext => Some("bad"),
        FixtureVariant::EmptyBrowseNextPage => Some("empty_page"),
        FixtureVariant::RemoteBrowseNextReference => Some("remote_reference"),
        FixtureVariant::UnknownNamespaceBrowseNextReference => Some("unknown_namespace_reference"),
        FixtureVariant::RemoteBrowseNextTypeDefinition => Some("remote_type_definition"),
        FixtureVariant::UnknownLocalBrowseNextNode => Some("unknown_local_node"),
        FixtureVariant::UnknownLocalBrowseNextReferenceType => Some("unknown_local_reference_type"),
        FixtureVariant::UnknownLocalBrowseNextTypeDefinition => {
            Some("unknown_local_type_definition")
        }
        FixtureVariant::DuplicateBrowseNextReference => Some("duplicate_reference"),
        FixtureVariant::NamedBrowseNextReference => Some("named_reference"),
        FixtureVariant::UnspecifiedBrowseNextNodeClass => Some("unspecified_node_class"),
        FixtureVariant::NullEmptyBrowseNextName => Some("null_empty_browse_name"),
        FixtureVariant::NullBrowseNextTypeDefinition => Some("null_type_definition"),
        _ => None,
    };
    if let Some(shape) = malformed_browse_next {
        env::set_var("WOTEX_OPCUA_RUST_MALFORMED_BROWSE_NEXT", shape);
        return Ok(());
    }

    let malformed_browse = match variant {
        FixtureVariant::MissingBrowseResult => Some("missing_result"),
        FixtureVariant::ExtraBrowseResult => Some("extra_result"),
        FixtureVariant::OversizedBrowsePage => Some("oversized_page"),
        FixtureVariant::OversizedBrowseContinuation => Some("oversized_continuation"),
        FixtureVariant::DiagnosedBrowse => Some("diagnostic"),
        FixtureVariant::UncertainBrowse => Some("uncertain"),
        FixtureVariant::BadBrowse => Some("bad"),
        FixtureVariant::EmptyBrowsePage => Some("empty_page"),
        FixtureVariant::RemoteBrowseReference => Some("remote_reference"),
        FixtureVariant::UnknownNamespaceBrowseReference => Some("unknown_namespace_reference"),
        FixtureVariant::RemoteBrowseTypeDefinition => Some("remote_type_definition"),
        FixtureVariant::UnknownLocalBrowseNode => Some("unknown_local_node"),
        FixtureVariant::UnknownLocalBrowseReferenceType => Some("unknown_local_reference_type"),
        FixtureVariant::UnknownLocalBrowseTypeDefinition => Some("unknown_local_type_definition"),
        FixtureVariant::DuplicateBrowseReference => Some("duplicate_reference"),
        FixtureVariant::NamedBrowseReference => Some("named_reference"),
        FixtureVariant::UnspecifiedBrowseNodeClass => Some("unspecified_node_class"),
        FixtureVariant::NullEmptyBrowseName => Some("null_empty_browse_name"),
        FixtureVariant::NullBrowseTypeDefinition => Some("null_type_definition"),
        _ => None,
    };
    if let Some(shape) = malformed_browse {
        env::set_var("WOTEX_OPCUA_RUST_MALFORMED_BROWSE", shape);
        return Ok(());
    }

    let malformed_release = match variant {
        FixtureVariant::MissingBrowseReleaseResult => Some("missing_result"),
        FixtureVariant::ExtraBrowseReleaseResult => Some("extra_result"),
        FixtureVariant::ReferencedBrowseRelease => Some("reference"),
        FixtureVariant::ContinuedBrowseRelease => Some("continuation"),
        FixtureVariant::DiagnosedBrowseRelease => Some("diagnostic"),
        _ => None,
    };
    if let Some(shape) = malformed_release {
        env::set_var("WOTEX_OPCUA_RUST_MALFORMED_BROWSE_RELEASE", shape);
        return Ok(());
    }

    if matches!(variant, FixtureVariant::BadBrowseReleaseService) {
        env::set_var("WOTEX_OPCUA_RUST_BAD_BROWSE_RELEASE_SERVICE", "1");
        return Ok(());
    }

    let (variable, marker_name) = match variant {
        FixtureVariant::LostBrowse => {
            ("WOTEX_OPCUA_RUST_EXIT_AFTER_BROWSE", "rust-browse-received")
        }
        FixtureVariant::LostBrowseNext => (
            "WOTEX_OPCUA_RUST_EXIT_AFTER_BROWSE_NEXT",
            "rust-browse-next-received",
        ),
        FixtureVariant::LostBrowseRelease => (
            "WOTEX_OPCUA_RUST_EXIT_AFTER_BROWSE_RELEASE",
            "rust-browse-release-received",
        ),
        FixtureVariant::BadBrowseRelease => (
            "WOTEX_OPCUA_RUST_BAD_BROWSE_RELEASE",
            "rust-browse-release-failed",
        ),
        _ => return Ok(()),
    };
    let marker = fixture.join(marker_name);
    match fs::remove_file(&marker) {
        Ok(()) => {}
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(format!("cannot remove Browse fault marker: {error}")),
    }
    env::set_var(variable, marker);
    Ok(())
}

fn configure_subscription_fault(variant: FixtureVariant) {
    let subscription_shape = match variant {
        FixtureVariant::InvalidSubscriptionPublishingInterval => Some("publishing_interval"),
        FixtureVariant::InvalidSubscriptionKeepalive => Some("keepalive"),
        FixtureVariant::InvalidSubscriptionLifetime => Some("lifetime"),
        _ => None,
    };
    if let Some(shape) = subscription_shape {
        env::set_var("WOTEX_OPCUA_RUST_MALFORMED_SUBSCRIPTION", shape);
    }

    let item_shape = match variant {
        FixtureVariant::MissingMonitoredItemResult => Some("missing_result"),
        FixtureVariant::ExtraMonitoredItemResult => Some("extra_result"),
        FixtureVariant::BadMonitoredItemStatus => Some("bad_status"),
        FixtureVariant::ZeroMonitoredItemId => Some("zero_id"),
        FixtureVariant::InvalidMonitoredItemSamplingInterval => Some("sampling_interval"),
        FixtureVariant::InvalidMonitoredItemQueueSize => Some("queue_size"),
        FixtureVariant::DiagnosedMonitoredItem => Some("diagnostic"),
        _ => None,
    };
    if let Some(shape) = item_shape {
        env::set_var("WOTEX_OPCUA_RUST_MALFORMED_MONITORED_ITEM", shape);
    }

    if matches!(variant, FixtureVariant::BadMonitoredItemService) {
        env::set_var("WOTEX_OPCUA_RUST_BAD_MONITORED_ITEM_SERVICE", "1");
    }

    let delete_item_shape = match variant {
        FixtureVariant::MissingDeleteMonitoredItemResult => Some("missing_result"),
        FixtureVariant::ExtraDeleteMonitoredItemResult => Some("extra_result"),
        FixtureVariant::BadDeleteMonitoredItemStatus => Some("bad_status"),
        FixtureVariant::DiagnosedDeleteMonitoredItem => Some("diagnostic"),
        _ => None,
    };
    if let Some(shape) = delete_item_shape {
        env::set_var("WOTEX_OPCUA_RUST_MALFORMED_DELETE_MONITORED_ITEM", shape);
    }
    if matches!(variant, FixtureVariant::BadDeleteMonitoredItemService) {
        env::set_var("WOTEX_OPCUA_RUST_BAD_DELETE_MONITORED_ITEM_SERVICE", "1");
    }

    let delete_subscription_shape = match variant {
        FixtureVariant::MissingDeleteSubscriptionResult => Some("missing_result"),
        FixtureVariant::ExtraDeleteSubscriptionResult => Some("extra_result"),
        FixtureVariant::BadDeleteSubscriptionStatus => Some("bad_status"),
        FixtureVariant::DiagnosedDeleteSubscription => Some("diagnostic"),
        _ => None,
    };
    if let Some(shape) = delete_subscription_shape {
        env::set_var("WOTEX_OPCUA_RUST_MALFORMED_DELETE_SUBSCRIPTION", shape);
    }
    if matches!(variant, FixtureVariant::BadDeleteSubscriptionService) {
        env::set_var("WOTEX_OPCUA_RUST_BAD_DELETE_SUBSCRIPTION_SERVICE", "1");
    }

    let publish_fault = match variant {
        FixtureVariant::DuplicatePublish => Some("duplicate"),
        FixtureVariant::ConflictingDuplicatePublish => Some("conflicting_duplicate"),
        FixtureVariant::OversizedPublishGap => Some("oversized_gap"),
        FixtureVariant::ZeroPublishSequence => Some("zero_sequence"),
        FixtureVariant::UnknownPublishClientHandle => Some("unknown_client_handle"),
        FixtureVariant::StatusChangePublish => Some("status_change"),
        FixtureVariant::BadPublishAcknowledgement => Some("bad_acknowledgement"),
        _ => None,
    };
    if let Some(fault) = publish_fault {
        env::set_var("WOTEX_OPCUA_RUST_PUBLISH_FAULT", fault);
    }
}

fn configure_write_fault(variant: FixtureVariant) {
    if matches!(variant, FixtureVariant::BadWriteSession) {
        env::set_var("WOTEX_OPCUA_RUST_BAD_WRITE_SESSION", "1");
    }
}

fn scalar_array(
    name: &str,
    value_type: VariantScalarTypeId,
    values: Vec<Variant>,
) -> Result<Variant, String> {
    Array::new(value_type, values)
        .map(|array| Variant::Array(Box::new(array)))
        .map_err(|error| format!("cannot construct {name}: {error:?}"))
}

fn prepare_pki(fixture: &Path, variant: FixtureVariant) -> Result<PathBuf, String> {
    let pki = fixture.join(format!("rust-pki-{}", variant.name()));
    for directory in ["own", "private", "trusted", "rejected"] {
        fs::create_dir_all(pki.join(directory))
            .map_err(|error| format!("cannot create Rust peer PKI: {error}"))?;
    }
    let certificate = variant.certificate_stem();
    copy(
        fixture.join(format!("{certificate}.der")),
        pki.join("own/server.der"),
    )?;
    copy(
        fixture.join(format!("{certificate}.pem")),
        pki.join("private/server.pem"),
    )?;
    copy(fixture.join("client.der"), pki.join("trusted/client.der"))?;
    Ok(pki)
}

fn copy(source: PathBuf, destination: PathBuf) -> Result<(), String> {
    fs::copy(&source, &destination)
        .map(|_| ())
        .map_err(|error| {
            format!(
                "cannot copy {} to {}: {error}",
                source.display(),
                destination.display()
            )
        })
}

fn populate(
    manager: &SimpleNodeManager,
    handle: &opcua::server::ServerHandle,
    namespace: u16,
    children: u32,
) -> Result<(), String> {
    let paged = NodeId::new(namespace, "paged");
    let fixture = NodeId::new(namespace, "fixture");
    let continuation_points = NodeId::new(namespace, "continuation_points");
    let browse_next_count = NodeId::new(namespace, "browse_next_count");
    let cancel_count = NodeId::new(namespace, "cancel_count");
    let create_counts = NodeId::new(namespace, "create_counts");
    let delete_counts = NodeId::new(namespace, "delete_counts");
    let republish_fault = NodeId::new(namespace, "republish_fault");
    let read_missing_value_fault = NodeId::new(namespace, "read_missing_value_fault");
    let read_status_fault = NodeId::new(namespace, "read_status_fault");
    let resources = NodeId::new(namespace, "resources");
    let secure_channel_renewals = NodeId::new(namespace, "secure_channel_renewals");
    let write_count = NodeId::new(namespace, "write_count");
    let value = NodeId::new(namespace, "value");
    let extension_object_value = NodeId::new(namespace, "extension_object_value");
    let int_array = NodeId::new(namespace, "int_array");
    let double_array = NodeId::new(namespace, "double_array");
    let int16_matrix = NodeId::new(namespace, "int16_matrix");
    let add = NodeId::new(namespace, "add");
    let slow = NodeId::new(namespace, "slow");

    {
        let mut address_space = manager.address_space().write();
        if !address_space.add_folder(
            &paged,
            "Paged",
            "Paged",
            &NodeId::from(ObjectId::ObjectsFolder),
        ) {
            return Err("cannot add paged folder".to_owned());
        }
        for index in 1..=children {
            let child = NodeId::new(namespace, format!("child{index}"));
            if !VariableBuilder::new(&child, format!("Child{index}"), format!("Child{index}"))
                .data_type(DataTypeId::UInt32)
                .value(index)
                .organized_by(paged.clone())
                .insert(&mut *address_space)
            {
                return Err(format!("cannot add child {index}"));
            }
        }
        if !ObjectBuilder::new(&fixture, "Fixture", "Fixture")
            .has_type_definition(ObjectTypeId::BaseObjectType)
            .organized_by(ObjectId::ObjectsFolder)
            .insert(&mut *address_space)
        {
            return Err("cannot add fixture object".to_owned());
        }
        if !VariableBuilder::new(&value, "Value", "Value")
            .data_type(DataTypeId::Double)
            .value(41.5_f64)
            .writable()
            .component_of(fixture.clone())
            .insert(&mut *address_space)
        {
            return Err("cannot add writable value".to_owned());
        }
        let extension_object = ExtensionObject::new(ByteStringBody::new(
            ByteString::from(vec![0, 255, 1, 2]),
            NodeId::new(namespace, "opaque_encoding"),
        ));
        if !VariableBuilder::new(
            &extension_object_value,
            "ExtensionObjectValue",
            "ExtensionObjectValue",
        )
        .data_type(DataTypeId::Structure)
        .value(Variant::ExtensionObject(extension_object))
        .component_of(fixture.clone())
        .insert(&mut *address_space)
        {
            return Err("cannot add opaque ExtensionObject value".to_owned());
        }
        if !VariableBuilder::new(&int_array, "IntArray", "IntArray")
            .data_type(DataTypeId::Int32)
            .value(vec![-2_147_483_648_i32, 0, 7])
            .writable()
            .component_of(fixture.clone())
            .insert(&mut *address_space)
        {
            return Err("cannot add writable Int32 array".to_owned());
        }
        if !VariableBuilder::new(&double_array, "DoubleArray", "DoubleArray")
            .data_type(DataTypeId::Double)
            .value(vec![1.5_f64, -0.0_f64])
            .writable()
            .component_of(fixture.clone())
            .insert(&mut *address_space)
        {
            return Err("cannot add writable Double array".to_owned());
        }
        let matrix = Array::new_multi(
            VariantScalarTypeId::Int16,
            [1_i16, 2, 3, 4, 5, 6]
                .into_iter()
                .map(Variant::Int16)
                .collect::<Vec<_>>(),
            vec![2, 3],
        )
        .map_err(|error| format!("cannot construct Int16 matrix: {error:?}"))?;
        if !VariableBuilder::new(&int16_matrix, "Int16Matrix", "Int16Matrix")
            .data_type(DataTypeId::Int16)
            .value(matrix)
            .writable()
            .component_of(fixture.clone())
            .insert(&mut *address_space)
        {
            return Err("cannot add writable Int16 matrix".to_owned());
        }
        let guid = "00112233-4455-6677-8899-aabbccddeeff"
            .parse::<Guid>()
            .map_err(|error| format!("cannot construct fixture Guid: {error}"))?;
        let scalar_values = [
            (
                "null_value",
                "NullValue",
                DataTypeId::BaseDataType,
                Variant::Empty,
            ),
            (
                "boolean_value",
                "BooleanValue",
                DataTypeId::Boolean,
                Variant::Boolean(true),
            ),
            (
                "sbyte_value",
                "SByteValue",
                DataTypeId::SByte,
                Variant::SByte(i8::MIN),
            ),
            (
                "byte_value",
                "ByteValue",
                DataTypeId::Byte,
                Variant::Byte(u8::MAX),
            ),
            (
                "int16_value",
                "Int16Value",
                DataTypeId::Int16,
                Variant::Int16(i16::MIN),
            ),
            (
                "uint16_value",
                "UInt16Value",
                DataTypeId::UInt16,
                Variant::UInt16(u16::MAX),
            ),
            (
                "int32_value",
                "Int32Value",
                DataTypeId::Int32,
                Variant::Int32(i32::MIN),
            ),
            (
                "uint32_value",
                "UInt32Value",
                DataTypeId::UInt32,
                Variant::UInt32(u32::MAX),
            ),
            (
                "int64_value",
                "Int64Value",
                DataTypeId::Int64,
                Variant::Int64(i64::MIN),
            ),
            (
                "uint64_value",
                "UInt64Value",
                DataTypeId::UInt64,
                Variant::UInt64(u64::MAX),
            ),
            (
                "float_value",
                "FloatValue",
                DataTypeId::Float,
                Variant::Float(-0.0_f32),
            ),
            (
                "string_value",
                "StringValue",
                DataTypeId::String,
                Variant::String("x\0é".into()),
            ),
            (
                "datetime_value",
                "DateTimeValue",
                DataTypeId::DateTime,
                Variant::DateTime(Box::new(DateTime::from(132_541_920_000_000_001_i64))),
            ),
            (
                "guid_value",
                "GuidValue",
                DataTypeId::Guid,
                Variant::Guid(Box::new(guid.clone())),
            ),
            (
                "bytestring_value",
                "ByteStringValue",
                DataTypeId::ByteString,
                Variant::ByteString(ByteString::from(vec![0, 255, 1])),
            ),
            (
                "nodeid_value",
                "NodeIdValue",
                DataTypeId::NodeId,
                Variant::NodeId(Box::new(fixture.clone())),
            ),
            (
                "status_code_value",
                "StatusCodeValue",
                DataTypeId::StatusCode,
                Variant::StatusCode(StatusCode::from(0x4000_0000)),
            ),
        ];
        for (identifier, name, data_type, scalar) in scalar_values {
            let node = NodeId::new(namespace, identifier);
            if !VariableBuilder::new(&node, name, name)
                .data_type(data_type)
                .value(scalar)
                .component_of(fixture.clone())
                .insert(&mut *address_space)
            {
                return Err(format!("cannot add {name}"));
            }
        }
        let second_guid = "ffeeddcc-bbaa-9988-7766-554433221100"
            .parse::<Guid>()
            .map_err(|error| format!("cannot construct second fixture Guid: {error}"))?;
        let array_values = [
            (
                "boolean_array",
                "BooleanArray",
                DataTypeId::Boolean,
                scalar_array(
                    "Boolean array",
                    VariantScalarTypeId::Boolean,
                    vec![Variant::Boolean(true), Variant::Boolean(false)],
                )?,
                true,
            ),
            (
                "sbyte_array",
                "SByteArray",
                DataTypeId::SByte,
                scalar_array(
                    "SByte array",
                    VariantScalarTypeId::SByte,
                    vec![Variant::SByte(i8::MIN), Variant::SByte(i8::MAX)],
                )?,
                true,
            ),
            (
                "byte_array",
                "ByteArray",
                DataTypeId::Byte,
                scalar_array(
                    "Byte array",
                    VariantScalarTypeId::Byte,
                    vec![Variant::Byte(0), Variant::Byte(u8::MAX)],
                )?,
                true,
            ),
            (
                "int16_array",
                "Int16Array",
                DataTypeId::Int16,
                scalar_array(
                    "Int16 array",
                    VariantScalarTypeId::Int16,
                    vec![Variant::Int16(i16::MIN), Variant::Int16(i16::MAX)],
                )?,
                true,
            ),
            (
                "uint16_array",
                "UInt16Array",
                DataTypeId::UInt16,
                scalar_array(
                    "UInt16 array",
                    VariantScalarTypeId::UInt16,
                    vec![Variant::UInt16(0), Variant::UInt16(u16::MAX)],
                )?,
                true,
            ),
            (
                "uint32_array",
                "UInt32Array",
                DataTypeId::UInt32,
                scalar_array(
                    "UInt32 array",
                    VariantScalarTypeId::UInt32,
                    vec![Variant::UInt32(0), Variant::UInt32(u32::MAX)],
                )?,
                true,
            ),
            (
                "int64_array",
                "Int64Array",
                DataTypeId::Int64,
                scalar_array(
                    "Int64 array",
                    VariantScalarTypeId::Int64,
                    vec![Variant::Int64(i64::MIN), Variant::Int64(i64::MAX)],
                )?,
                true,
            ),
            (
                "uint64_array",
                "UInt64Array",
                DataTypeId::UInt64,
                scalar_array(
                    "UInt64 array",
                    VariantScalarTypeId::UInt64,
                    vec![Variant::UInt64(0), Variant::UInt64(u64::MAX)],
                )?,
                true,
            ),
            (
                "float_array",
                "FloatArray",
                DataTypeId::Float,
                scalar_array(
                    "Float array",
                    VariantScalarTypeId::Float,
                    vec![Variant::Float(-0.0_f32), Variant::Float(1.5_f32)],
                )?,
                true,
            ),
            (
                "string_array",
                "StringArray",
                DataTypeId::String,
                scalar_array(
                    "String array",
                    VariantScalarTypeId::String,
                    vec![Variant::String("x\0é".into()), Variant::String("".into())],
                )?,
                true,
            ),
            (
                "datetime_array",
                "DateTimeArray",
                DataTypeId::DateTime,
                scalar_array(
                    "DateTime array",
                    VariantScalarTypeId::DateTime,
                    vec![
                        Variant::DateTime(Box::new(DateTime::from(132_541_920_000_000_001_i64))),
                        Variant::DateTime(Box::new(DateTime::from(132_541_920_000_000_002_i64))),
                    ],
                )?,
                false,
            ),
            (
                "guid_array",
                "GuidArray",
                DataTypeId::Guid,
                scalar_array(
                    "Guid array",
                    VariantScalarTypeId::Guid,
                    vec![
                        Variant::Guid(Box::new(guid)),
                        Variant::Guid(Box::new(second_guid)),
                    ],
                )?,
                false,
            ),
            (
                "bytestring_array",
                "ByteStringArray",
                DataTypeId::ByteString,
                scalar_array(
                    "ByteString array",
                    VariantScalarTypeId::ByteString,
                    vec![
                        Variant::ByteString(ByteString::from(vec![0, 255])),
                        Variant::ByteString(ByteString::from(Vec::new())),
                    ],
                )?,
                true,
            ),
            (
                "nodeid_array",
                "NodeIdArray",
                DataTypeId::NodeId,
                scalar_array(
                    "NodeId array",
                    VariantScalarTypeId::NodeId,
                    vec![
                        Variant::NodeId(Box::new(fixture.clone())),
                        Variant::NodeId(Box::new(NodeId::new(0, 2255))),
                    ],
                )?,
                false,
            ),
            (
                "status_code_array",
                "StatusCodeArray",
                DataTypeId::StatusCode,
                scalar_array(
                    "StatusCode array",
                    VariantScalarTypeId::StatusCode,
                    vec![
                        Variant::StatusCode(StatusCode::Good),
                        Variant::StatusCode(StatusCode::from(0x4000_0000)),
                    ],
                )?,
                false,
            ),
        ];
        for (identifier, name, data_type, array, writable) in array_values {
            let node = NodeId::new(namespace, identifier);
            let variable = VariableBuilder::new(&node, name, name)
                .data_type(data_type)
                .value(array)
                .component_of(fixture.clone());
            let variable = if writable {
                variable.writable()
            } else {
                variable
            };
            if !variable.insert(&mut *address_space) {
                return Err(format!("cannot add {name}"));
            }
        }
        if !MethodBuilder::new(&add, "Add", "Add")
            .component_of(fixture.clone())
            .input_args(
                &mut *address_space,
                &NodeId::new(namespace, "add_inputs"),
                &[
                    ("Left", DataTypeId::Double).into(),
                    ("Right", DataTypeId::Double).into(),
                ],
            )
            .output_args(
                &mut *address_space,
                &NodeId::new(namespace, "add_outputs"),
                &[("Sum", DataTypeId::Double).into()],
            )
            .executable(true)
            .user_executable(true)
            .insert(&mut *address_space)
        {
            return Err("cannot add addition method".to_owned());
        }
        if !MethodBuilder::new(
            &continuation_points,
            "ContinuationPoints",
            "ContinuationPoints",
        )
        .component_of(fixture.clone())
        .output_args(
            &mut *address_space,
            &NodeId::new(namespace, "continuation_points_outputs"),
            &[("Count", DataTypeId::UInt32).into()],
        )
        .executable(true)
        .user_executable(true)
        .insert(&mut *address_space)
        {
            return Err("cannot add continuation point method".to_owned());
        }
        if !MethodBuilder::new(&cancel_count, "CancelCount", "CancelCount")
            .component_of(fixture.clone())
            .output_args(
                &mut *address_space,
                &NodeId::new(namespace, "cancel_count_outputs"),
                &[("Count", DataTypeId::UInt32).into()],
            )
            .executable(true)
            .user_executable(true)
            .insert(&mut *address_space)
        {
            return Err("cannot add cancel count method".to_owned());
        }
        if !MethodBuilder::new(&browse_next_count, "BrowseNextCount", "BrowseNextCount")
            .component_of(fixture.clone())
            .output_args(
                &mut *address_space,
                &NodeId::new(namespace, "browse_next_count_outputs"),
                &[("Count", DataTypeId::UInt32).into()],
            )
            .executable(true)
            .user_executable(true)
            .insert(&mut *address_space)
        {
            return Err("cannot add BrowseNext count method".to_owned());
        }
        if !MethodBuilder::new(&create_counts, "CreateCounts", "CreateCounts")
            .component_of(fixture.clone())
            .output_args(
                &mut *address_space,
                &NodeId::new(namespace, "create_counts_outputs"),
                &[
                    ("Subscriptions", DataTypeId::UInt32).into(),
                    ("MonitoredItems", DataTypeId::UInt32).into(),
                ],
            )
            .executable(true)
            .user_executable(true)
            .insert(&mut *address_space)
        {
            return Err("cannot add create count method".to_owned());
        }
        if !MethodBuilder::new(&delete_counts, "DeleteCounts", "DeleteCounts")
            .component_of(fixture.clone())
            .output_args(
                &mut *address_space,
                &NodeId::new(namespace, "delete_counts_outputs"),
                &[
                    ("MonitoredItems", DataTypeId::UInt32).into(),
                    ("Subscriptions", DataTypeId::UInt32).into(),
                ],
            )
            .executable(true)
            .user_executable(true)
            .insert(&mut *address_space)
        {
            return Err("cannot add delete count method".to_owned());
        }
        if !MethodBuilder::new(&republish_fault, "RepublishFault", "RepublishFault")
            .component_of(fixture.clone())
            .input_args(
                &mut *address_space,
                &NodeId::new(namespace, "republish_fault_inputs"),
                &[
                    ("Withhold", DataTypeId::UInt32).into(),
                    ("Discard", DataTypeId::Boolean).into(),
                ],
            )
            .output_args(
                &mut *address_space,
                &NodeId::new(namespace, "republish_fault_outputs"),
                &[
                    ("Withheld", DataTypeId::UInt32).into(),
                    ("Republished", DataTypeId::UInt32).into(),
                ],
            )
            .executable(true)
            .user_executable(true)
            .insert(&mut *address_space)
        {
            return Err("cannot add Republish fault method".to_owned());
        }
        if !MethodBuilder::new(&read_status_fault, "ReadStatusFault", "ReadStatusFault")
            .component_of(fixture.clone())
            .input_args(
                &mut *address_space,
                &NodeId::new(namespace, "read_status_fault_inputs"),
                &[("Status", DataTypeId::UInt32).into()],
            )
            .output_args(
                &mut *address_space,
                &NodeId::new(namespace, "read_status_fault_outputs"),
                &[("Previous", DataTypeId::UInt32).into()],
            )
            .executable(true)
            .user_executable(true)
            .insert(&mut *address_space)
        {
            return Err("cannot add Read status fault method".to_owned());
        }
        if !MethodBuilder::new(
            &read_missing_value_fault,
            "ReadMissingValueFault",
            "ReadMissingValueFault",
        )
        .component_of(fixture.clone())
        .output_args(
            &mut *address_space,
            &NodeId::new(namespace, "read_missing_value_fault_outputs"),
            &[("Previous", DataTypeId::Boolean).into()],
        )
        .executable(true)
        .user_executable(true)
        .insert(&mut *address_space)
        {
            return Err("cannot add Read missing-value fault method".to_owned());
        }
        if !MethodBuilder::new(&resources, "Resources", "Resources")
            .component_of(fixture.clone())
            .output_args(
                &mut *address_space,
                &NodeId::new(namespace, "resources_outputs"),
                &[
                    ("Subscriptions", DataTypeId::UInt32).into(),
                    ("MonitoredItems", DataTypeId::UInt32).into(),
                ],
            )
            .executable(true)
            .user_executable(true)
            .insert(&mut *address_space)
        {
            return Err("cannot add resource method".to_owned());
        }
        if !MethodBuilder::new(
            &secure_channel_renewals,
            "SecureChannelRenewals",
            "SecureChannelRenewals",
        )
        .component_of(fixture.clone())
        .output_args(
            &mut *address_space,
            &NodeId::new(namespace, "secure_channel_renewals_outputs"),
            &[("Count", DataTypeId::UInt32).into()],
        )
        .executable(true)
        .user_executable(true)
        .insert(&mut *address_space)
        {
            return Err("cannot add secure channel renewal method".to_owned());
        }
        if !MethodBuilder::new(&write_count, "WriteCount", "WriteCount")
            .component_of(fixture.clone())
            .output_args(
                &mut *address_space,
                &NodeId::new(namespace, "write_count_outputs"),
                &[("Count", DataTypeId::UInt32).into()],
            )
            .executable(true)
            .user_executable(true)
            .insert(&mut *address_space)
        {
            return Err("cannot add write count method".to_owned());
        }
        if !MethodBuilder::new(&slow, "Slow", "Slow")
            .component_of(fixture)
            .input_args(
                &mut *address_space,
                &NodeId::new(namespace, "slow_inputs"),
                &[("Milliseconds", DataTypeId::UInt32).into()],
            )
            .output_args(
                &mut *address_space,
                &NodeId::new(namespace, "slow_outputs"),
                &[("Milliseconds", DataTypeId::UInt32).into()],
            )
            .executable(true)
            .user_executable(true)
            .insert(&mut *address_space)
        {
            return Err("cannot add slow method".to_owned());
        }
    }

    let continuation_handle = handle.clone();
    manager
        .inner()
        .add_method_callback(continuation_points, move |_| {
            Ok(vec![Variant::UInt32(
                continuation_handle.browse_continuation_point_count() as u32,
            )])
        });
    let cancel_handle = handle.clone();
    manager.inner().add_method_callback(cancel_count, move |_| {
        Ok(vec![Variant::UInt32(cancel_handle.cancel_count())])
    });
    let browse_next_handle = handle.clone();
    manager
        .inner()
        .add_method_callback(browse_next_count, move |_| {
            Ok(vec![Variant::UInt32(
                browse_next_handle.browse_next_count(),
            )])
        });
    let create_handle = handle.clone();
    manager
        .inner()
        .add_method_callback(create_counts, move |_| {
            Ok(vec![
                Variant::UInt32(create_handle.create_subscription_count()),
                Variant::UInt32(create_handle.create_monitored_items_count()),
            ])
        });
    let delete_handle = handle.clone();
    manager
        .inner()
        .add_method_callback(delete_counts, move |_| {
            Ok(vec![
                Variant::UInt32(delete_handle.delete_monitored_items_count()),
                Variant::UInt32(delete_handle.delete_subscriptions_count()),
            ])
        });
    let republish_handle = handle.clone();
    manager
        .inner()
        .add_method_callback(republish_fault, move |arguments| {
            let [Variant::UInt32(withhold), Variant::Boolean(discard)] = arguments else {
                return Err(StatusCode::BadInvalidArgument);
            };
            let (withheld, republished) =
                republish_handle.configure_republish_fault(*withhold, *discard);
            Ok(vec![
                Variant::UInt32(withheld),
                Variant::UInt32(republished),
            ])
        });
    let read_status_handle = handle.clone();
    manager
        .inner()
        .add_method_callback(read_status_fault, move |arguments| {
            let [Variant::UInt32(status)] = arguments else {
                return Err(StatusCode::BadInvalidArgument);
            };
            Ok(vec![Variant::UInt32(
                read_status_handle.configure_read_status_fault(*status),
            )])
        });
    let read_missing_value_handle = handle.clone();
    manager
        .inner()
        .add_method_callback(read_missing_value_fault, move |arguments| {
            if !arguments.is_empty() {
                return Err(StatusCode::BadInvalidArgument);
            }
            Ok(vec![Variant::Boolean(
                read_missing_value_handle.configure_read_missing_value_fault(),
            )])
        });
    let resource_handle = handle.clone();
    manager.inner().add_method_callback(resources, move |_| {
        Ok(vec![
            Variant::UInt32(resource_handle.subscription_count() as u32),
            Variant::UInt32(resource_handle.monitored_item_count() as u32),
        ])
    });
    let renewal_handle = handle.clone();
    manager
        .inner()
        .add_method_callback(secure_channel_renewals, move |_| {
            Ok(vec![Variant::UInt32(
                renewal_handle.secure_channel_renewal_count(),
            )])
        });
    let write_handle = handle.clone();
    manager.inner().add_method_callback(write_count, move |_| {
        Ok(vec![Variant::UInt32(write_handle.write_request_count())])
    });
    manager.inner().add_method_callback(add, |arguments| {
        let [Variant::Double(left), Variant::Double(right)] = arguments else {
            return Err(StatusCode::BadInvalidArgument);
        };
        Ok(vec![Variant::Double(left + right)])
    });
    manager.inner().add_method_callback(slow, |arguments| {
        let [Variant::UInt32(milliseconds)] = arguments else {
            return Err(StatusCode::BadInvalidArgument);
        };
        std::thread::sleep(Duration::from_millis(u64::from(
            (*milliseconds).min(30_000),
        )));
        Ok(vec![Variant::UInt32(*milliseconds)])
    });
    Ok(())
}

async fn publish_config(
    fixture: &Path,
    endpoint: &str,
    port: u16,
    children: u32,
    variant: FixtureVariant,
) -> Result<(), String> {
    for _ in 0..300 {
        if tokio::net::TcpStream::connect(("127.0.0.1", port))
            .await
            .is_ok()
        {
            let config = format!(
                concat!(
                    "{{\"endpoint\":\"{}\",",
                    "\"namespace_uri\":\"{}\",",
                    "\"paged_node_id\":\"nsu={};s=paged\",",
                    "\"children\":{},",
                    "\"username\":\"{}\",",
                    "\"password\":\"{}\",",
                    "\"object_id\":\"nsu={};s=fixture\",",
                    "\"node_id\":\"nsu={};s=value\",",
                    "\"method_id\":\"nsu={};s=add\",",
                    "\"continuation_points_method_id\":",
                    "\"nsu={};s=continuation_points\",",
                    "\"cancel_count_method_id\":\"nsu={};s=cancel_count\",",
                    "\"republish_fault_method_id\":\"nsu={};s=republish_fault\",",
                    "\"slow_method_id\":\"nsu={};s=slow\"}}"
                ),
                endpoint,
                NAMESPACE_URI,
                NAMESPACE_URI,
                children,
                USERNAME,
                PASSWORD,
                NAMESPACE_URI,
                NAMESPACE_URI,
                NAMESPACE_URI,
                NAMESPACE_URI,
                NAMESPACE_URI,
                NAMESPACE_URI,
                NAMESPACE_URI
            );
            fs::write(fixture.join(variant.config_name()), config)
                .map_err(|error| format!("cannot write Rust peer config: {error}"))?;
            println!("rust peer ready");
            return Ok(());
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    Err("Rust peer did not start within 30 seconds".to_owned())
}

fn publish_result(
    fixture: &Path,
    variant: FixtureVariant,
    application_requests: u32,
) -> Result<(), String> {
    fs::write(
        fixture.join(variant.result_name()),
        format!("{{\"application_requests\":{application_requests}}}"),
    )
    .map_err(|error| format!("cannot write Rust peer result: {error}"))
}
