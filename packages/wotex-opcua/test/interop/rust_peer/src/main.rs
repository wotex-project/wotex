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
        ServerBuilder, ServerUserToken, ANONYMOUS_USER_TOKEN_ID,
    },
    types::{DataTypeId, MessageSecurityMode, NodeId, ObjectId, ObjectTypeId, StatusCode, Variant},
};
use tokio::io::AsyncReadExt;

const NAMESPACE_URI: &str = "urn:wotex:rust-fixture";
const APPLICATION_URI: &str = "urn:wotex:fixture:server";
const USERNAME_TOKEN_ID: &str = "USERNAME";
const CERTIFICATE_TOKEN_ID: &str = "CERTIFICATE";
const USERNAME: &str = "operator";
const PASSWORD: &str = "correct horse";

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
    if arguments.len() != 3 {
        return Err("usage: wotex-opcua-rust-peer FIXTURE_DIRECTORY CHILDREN".to_owned());
    }
    let fixture = PathBuf::from(&arguments[1]);
    let children = arguments[2]
        .parse::<u32>()
        .map_err(|_| "CHILDREN must be an integer".to_owned())?;
    if !(1..=1000).contains(&children) {
        return Err("CHILDREN must be between 1 and 1000".to_owned());
    }

    let port = available_port()?;
    let pki = prepare_pki(&fixture)?;
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
    let (server, handle) = ServerBuilder::new()
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
        .add_endpoint(
            "basic256sha256",
            (
                "/fixture",
                SecurityPolicy::Basic256Sha256,
                MessageSecurityMode::SignAndEncrypt,
                &token_ids as &[&str],
            ),
        )
        .add_endpoint(
            "aes128_sha256_rsaoaep",
            (
                "/fixture",
                SecurityPolicy::Aes128Sha256RsaOaep,
                MessageSecurityMode::SignAndEncrypt,
                &token_ids as &[&str],
            ),
        )
        .add_endpoint(
            "aes256_sha256_rsapss",
            (
                "/fixture",
                SecurityPolicy::Aes256Sha256RsaPss,
                MessageSecurityMode::SignAndEncrypt,
                &token_ids as &[&str],
            ),
        )
        .default_endpoint("basic256sha256")
        .max_browse_continuation_points(16)
        .with_node_manager(manager_builder)
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
        let result = publish_config(&ready_fixture, &ready_endpoint, port, children).await;
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
    server_result
}

fn available_port() -> Result<u16, String> {
    TcpListener::bind(("127.0.0.1", 0))
        .and_then(|listener| listener.local_addr())
        .map(|address| address.port())
        .map_err(|error| format!("cannot reserve fixture port: {error}"))
}

fn prepare_pki(fixture: &Path) -> Result<PathBuf, String> {
    let pki = fixture.join("rust-pki");
    for directory in ["own", "private", "trusted", "rejected"] {
        fs::create_dir_all(pki.join(directory))
            .map_err(|error| format!("cannot create Rust peer PKI: {error}"))?;
    }
    copy(fixture.join("server.der"), pki.join("own/server.der"))?;
    copy(fixture.join("server.pem"), pki.join("private/server.pem"))?;
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
    let cancel_count = NodeId::new(namespace, "cancel_count");
    let resources = NodeId::new(namespace, "resources");
    let value = NodeId::new(namespace, "value");
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
    let resource_handle = handle.clone();
    manager.inner().add_method_callback(resources, move |_| {
        Ok(vec![
            Variant::UInt32(resource_handle.subscription_count() as u32),
            Variant::UInt32(resource_handle.monitored_item_count() as u32),
        ])
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
                NAMESPACE_URI
            );
            fs::write(fixture.join("rust-config.json"), config)
                .map_err(|error| format!("cannot write Rust peer config: {error}"))?;
            println!("rust peer ready");
            return Ok(());
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    Err("Rust peer did not start within 30 seconds".to_owned())
}
