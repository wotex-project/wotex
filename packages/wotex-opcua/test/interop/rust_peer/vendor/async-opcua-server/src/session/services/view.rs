use std::{collections::HashMap, fs};

use opcua_core::trace_write_lock;
use tracing::{debug_span, error, info};
use tracing_futures::Instrument;

use crate::{
    node_manager::{
        resolve_external_references, BrowseNode, BrowsePathItem, ExternalReferencesContPoint,
        NodeManagers, RegisterNodeItem, RequestContext,
    },
    session::{controller::Response, message_handler::Request},
};
use opcua_types::{
    BrowseNextRequest, BrowseNextResponse, BrowsePathResult, BrowsePathTarget, BrowseRequest,
    BrowseResponse, BrowseResult, ByteString, DiagnosticInfo, ExpandedNodeId, NodeClass,
    ReferenceDescription, RegisterNodesRequest, RegisterNodesResponse, ResponseHeader, StatusCode,
    UAString,
    TranslateBrowsePathsToNodeIdsRequest,
    TranslateBrowsePathsToNodeIdsResponse, UnregisterNodesRequest, UnregisterNodesResponse,
};

pub(crate) async fn browse(
    node_managers: NodeManagers,
    request: Request<BrowseRequest>,
) -> Response {
    let mut context: RequestContext = request.context();
    let nodes_to_browse = take_service_items!(
        request,
        request.request.nodes_to_browse,
        request.info.operational_limits.max_nodes_per_browse
    );
    if !request.request.view.view_id.is_null() || !request.request.view.timestamp.is_null() {
        info!("Browse request ignored because view was specified (views not supported)");
        return service_fault!(request, StatusCode::BadViewIdUnknown);
    }

    let mut max_references_per_node = if request.request.requested_max_references_per_node == 0 {
        request
            .info
            .operational_limits
            .max_references_per_browse_node
    } else {
        request
            .info
            .operational_limits
            .max_references_per_browse_node
            .min(request.request.requested_max_references_per_node as usize)
    };
    let page_cap = std::env::var("WOTEX_OPCUA_RUST_BROWSE_PAGE_CAP")
        .ok()
        .and_then(|value| value.parse::<usize>().ok());
    if let Some(page_cap) = page_cap {
        max_references_per_node = max_references_per_node.min(page_cap);
    }

    let mut nodes: Vec<_> = nodes_to_browse
        .into_iter()
        .enumerate()
        .map(|(idx, r)| BrowseNode::new(r, max_references_per_node, idx))
        .collect();

    let mut results: Vec<_> = (0..nodes.len()).map(|_| None).collect();
    let node_manager_count = node_managers.len();

    for (node_manager_index, node_manager) in node_managers.iter().enumerate() {
        context.current_node_manager_index = node_manager_index;

        if let Err(e) = node_manager
            .browse(&context, &mut nodes)
            .instrument(debug_span!("Browse", node_manager = %node_manager.name()))
            .await
        {
            for node in &mut nodes {
                if node_manager.owns_node(node.node_id()) {
                    node.set_status(e);
                }
            }
        }
        // Iterate over the current nodes, removing unfinished ones, and storing
        // continuation points when relevant.
        // This does not preserve ordering, for efficiency, so node managers should
        // not rely on ordering at all.
        // We store the input index to make sure the results are correctly ordered.
        let mut i = 0;
        let mut session = request.session.write();
        while let Some(n) = nodes.get(i) {
            if n.is_completed() {
                let (result, input_index) = nodes.swap_remove(i).into_result(
                    node_manager_index,
                    node_manager_count,
                    &mut session,
                );
                results[input_index] = Some(result);
            } else {
                i += 1;
            }
        }

        if nodes.is_empty() {
            break;
        }
    }

    // Process external references

    // Any remaining nodes may have an external ref continuation point, process these before proceeding.
    {
        let type_tree = context.get_type_tree_for_user();
        for node in nodes.iter_mut() {
            if let Some(mut p) = node.take_continuation_point::<ExternalReferencesContPoint>() {
                while node.remaining() > 0 {
                    let Some(rf) = p.items.pop_front() else {
                        break;
                    };
                    node.add(type_tree.get(), rf);
                }

                if !p.items.is_empty() {
                    node.set_next_continuation_point(p);
                }
            }
        }
    }

    // Gather a unique list of all references
    let mut external_refs = HashMap::new();
    for (rf, mask) in nodes
        .iter()
        .flat_map(|n| n.get_external_refs().map(|r| (r, n.result_mask())))
    {
        // OR together the masks, so that if (for some reason) a user requests different
        // masks for two nodes but they return a reference to the same node, we use the widest
        // available mask...
        external_refs
            .entry(rf)
            .and_modify(|m| *m |= mask)
            .or_insert(mask);
    }

    // Actually resolve the references
    let external_refs: Vec<_> = external_refs.into_iter().collect();
    let node_meta = resolve_external_references(&context, &node_managers, &external_refs).await;
    let node_map: HashMap<_, _> = node_meta
        .iter()
        .filter_map(|n| n.as_ref())
        .map(|n| (&n.node_id.node_id, n))
        .collect();

    // Finally, process all remaining nodes, including external references
    {
        let mut session = request.session.write();
        let type_tree = context.get_type_tree_for_user();
        for mut node in nodes {
            node.resolve_external_references(type_tree.get(), &node_map);

            let (result, input_index) =
                node.into_result(node_manager_count - 1, node_manager_count, &mut session);
            results[input_index] = Some(result);
        }
    }

    // Cannot be None here, since we are guaranteed to always empty out nodes.
    let mut results = results.into_iter().map(Option::unwrap).collect();

    // The disposable Wotex fixture records that the server allocated a
    // continuation, then exits before its initial Browse response is sent.
    if let Ok(marker) = std::env::var("WOTEX_OPCUA_RUST_EXIT_AFTER_BROWSE") {
        let continuations = request
            .session
            .read()
            .browse_continuation_point_count();
        if fs::write(marker, format!("{continuations}\n")).is_ok() {
            std::process::exit(84);
        }
        std::process::exit(85);
    }

    let diagnostic_infos = malformed_browse(&mut results);
    let mut response_header = ResponseHeader::new_good(request.request_handle);
    if std::env::var_os("WOTEX_OPCUA_RUST_BAD_BROWSE_SERVICE").is_some() {
        response_header.service_result = StatusCode::BadUnexpectedError;
    }

    Response {
        message: BrowseResponse {
            response_header,
            results: Some(results),
            diagnostic_infos,
        }
        .into(),
        request_id: request.request_id,
    }
}

fn malformed_browse(results: &mut Vec<BrowseResult>) -> Option<Vec<DiagnosticInfo>> {
    malformed_browse_response("WOTEX_OPCUA_RUST_MALFORMED_BROWSE", results)
}

fn malformed_browse_response(
    variable: &str,
    results: &mut Vec<BrowseResult>,
) -> Option<Vec<DiagnosticInfo>> {
    let name_bytes = std::env::var("WOTEX_OPCUA_RUST_BROWSE_NAME_BYTES")
        .ok()
        .and_then(|value| value.parse::<usize>().ok());
    if let Some(name_bytes) = name_bytes {
        for reference in results[0].references.get_or_insert_default() {
            reference.browse_name.name = "x".repeat(name_bytes).into();
        }
    }

    match std::env::var(variable).as_deref() {
        Ok("missing_result") => results.clear(),
        Ok("extra_result") => results.push(BrowseResult {
            status_code: StatusCode::Good,
            continuation_point: ByteString::null(),
            references: None,
        }),
        Ok("oversized_page") => results[0]
            .references
            .get_or_insert_default()
            .push(ReferenceDescription::default()),
        Ok("oversized_continuation") => {
            results[0].continuation_point = ByteString::from(vec![0; 4097]);
        }
        Ok("diagnostic") => return Some(vec![DiagnosticInfo::default()]),
        Ok("uncertain") => results[0].status_code = StatusCode::from(0x4000_0000),
        Ok("bad") => results[0].status_code = StatusCode::BadUnexpectedError,
        Ok("empty_page") => results[0].references = None,
        Ok("remote_reference") => {
            if let Some(reference) = results[0]
                .references
                .as_mut()
                .and_then(|references| references.first_mut())
            {
                reference.node_id.server_index = 1;
            }
        }
        Ok("unknown_namespace_reference") => {
            if let Some(reference) = results[0]
                .references
                .as_mut()
                .and_then(|references| references.first_mut())
            {
                reference.node_id.namespace_uri = "urn:wotex:unknown".into();
            }
        }
        Ok("remote_type_definition") => {
            if let Some(reference) = results[0]
                .references
                .as_mut()
                .and_then(|references| references.first_mut())
            {
                reference.type_definition.namespace_uri = "urn:wotex:unknown-type".into();
                reference.type_definition.server_index = 1;
            }
        }
        Ok("unknown_local_node") => {
            if let Some(reference) = results[0]
                .references
                .as_mut()
                .and_then(|references| references.first_mut())
            {
                reference.node_id.node_id.namespace = 1000;
            }
        }
        Ok("unknown_local_reference_type") => {
            if let Some(reference) = results[0]
                .references
                .as_mut()
                .and_then(|references| references.first_mut())
            {
                reference.reference_type_id.namespace = 1000;
            }
        }
        Ok("unknown_local_type_definition") => {
            if let Some(reference) = results[0]
                .references
                .as_mut()
                .and_then(|references| references.first_mut())
            {
                reference.type_definition.node_id.namespace = 1000;
            }
        }
        Ok("duplicate_reference") => {
            if let Some(references) = results[0].references.as_mut() {
                if references.len() > 1 {
                    references[1] = references[0].clone();
                }
            }
        }
        Ok("named_reference") => {
            if let Some(reference) = results[0]
                .references
                .as_mut()
                .and_then(|references| references.first_mut())
            {
                reference.browse_name.namespace_index = u16::MAX;
                reference.browse_name.name = "Namn".into();
                reference.display_name.locale = "sv-SE".into();
                reference.display_name.text = "Fjärr".into();
            }
        }
        Ok("unspecified_node_class") => {
            if let Some(reference) = results[0]
                .references
                .as_mut()
                .and_then(|references| references.first_mut())
            {
                reference.node_class = NodeClass::Unspecified;
            }
        }
        Ok("null_empty_browse_name") => {
            if let Some(references) = results[0].references.as_mut() {
                if references.len() > 1 {
                    references[0].browse_name.namespace_index = 17;
                    references[0].browse_name.name = UAString::null();
                    references[1].browse_name.namespace_index = 18;
                    references[1].browse_name.name = "".into();
                }
            }
        }
        Ok("null_type_definition") => {
            if let Some(reference) = results[0]
                .references
                .as_mut()
                .and_then(|references| references.first_mut())
            {
                reference.type_definition = ExpandedNodeId::null();
            }
        }
        _ => {}
    }
    None
}

pub(crate) async fn browse_next(
    node_managers: NodeManagers,
    request: Request<BrowseNextRequest>,
) -> Response {
    request.info.record_browse_next_request();
    let mut context = request.context();
    let nodes_to_browse = take_service_items!(
        request,
        request.request.continuation_points,
        request.info.operational_limits.max_nodes_per_browse
    );
    let mut results: Vec<_> = (0..nodes_to_browse.len()).map(|_| None).collect();

    let mut nodes = {
        let mut session = trace_write_lock!(request.session);
        let mut nodes = Vec::with_capacity(nodes_to_browse.len());
        for (idx, point) in nodes_to_browse.into_iter().enumerate() {
            let point = session.remove_browse_continuation_point(&point);
            if let Some(point) = point {
                nodes.push(BrowseNode::from_continuation_point(point, idx));
            } else {
                results[idx] = Some(BrowseResult {
                    status_code: StatusCode::BadContinuationPointInvalid,
                    continuation_point: ByteString::null(),
                    references: None,
                });
            }
        }
        nodes
    };

    // The disposable Wotex fixture uses this opt-in hook to prove the client
    // closes a Session when a BrowseNext request reached the server but its
    // response was lost. The continuation has already been consumed above.
    if !request.request.release_continuation_points {
        if let Ok(marker) = std::env::var("WOTEX_OPCUA_RUST_EXIT_AFTER_BROWSE_NEXT") {
            if fs::write(marker, b"received\n").is_ok() {
                std::process::exit(86);
            }
            std::process::exit(87);
        }
    } else if let Ok(marker) = std::env::var("WOTEX_OPCUA_RUST_EXIT_AFTER_BROWSE_RELEASE") {
        if fs::write(marker, b"received\n").is_ok() {
            std::process::exit(88);
        }
        std::process::exit(89);
    }

    let mut results = if request.request.release_continuation_points {
        results
            .into_iter()
            .map(|r| r.unwrap_or_else(browse_release_result))
            .collect()
    } else {
        let node_manager_count = node_managers.len();

        let mut batch_nodes = Vec::with_capacity(nodes.len());

        for (node_manager_index, node_manager) in node_managers.iter().enumerate() {
            context.current_node_manager_index = node_manager_index;
            let mut i = 0;
            // Get all the nodes with a continuation point at the current node manager.
            // We collect these as we iterate through the node managers.
            while let Some(n) = nodes.get(i) {
                if n.start_node_manager == node_manager_index {
                    batch_nodes.push(nodes.swap_remove(i));
                } else {
                    i += 1;
                }
            }

            if let Err(e) = node_manager
                .browse(&context, &mut batch_nodes)
                .instrument(debug_span!("BrowseNext", node_manager = %node_manager.name()))
                .await
            {
                for node in &mut nodes {
                    if node_manager.owns_node(node.node_id()) {
                        node.set_status(e);
                    }
                }
            }
            // Iterate over the current nodes, removing unfinished ones, and storing
            // continuation points when relevant.
            // This does not preserve ordering, for efficiency, so node managers should
            // not rely on ordering at all.
            // We store the input index to make sure the results are correctly ordered.
            let mut i = 0;
            let mut session = request.session.write();
            while let Some(n) = batch_nodes.get(i) {
                if n.is_completed() {
                    let (result, input_index) = batch_nodes.swap_remove(i).into_result(
                        node_manager_index,
                        node_manager_count,
                        &mut session,
                    );
                    results[input_index] = Some(result);
                } else {
                    i += 1;
                }
            }

            if nodes.is_empty() && batch_nodes.is_empty() {
                break;
            }
        }

        // Process external references

        // Any remaining nodes may have an external ref continuation point, process these before proceeding.
        {
            let type_tree = context.get_type_tree_for_user();
            for node in nodes.iter_mut() {
                if let Some(mut p) = node.take_continuation_point::<ExternalReferencesContPoint>() {
                    while node.remaining() > 0 {
                        let Some(rf) = p.items.pop_front() else {
                            break;
                        };
                        node.add(type_tree.get(), rf);
                    }

                    if !p.items.is_empty() {
                        node.set_next_continuation_point(p);
                    }
                }
            }
        }

        // Gather a unique list of all references
        let mut external_refs = HashMap::new();
        for (rf, mask) in nodes
            .iter()
            .chain(batch_nodes.iter())
            .flat_map(|n| n.get_external_refs().map(|r| (r, n.result_mask())))
        {
            // OR together the masks, so that if (for some reason) a user requests different
            // masks for two nodes but they return a reference to the same node, we use the widest
            // available mask...
            external_refs
                .entry(rf)
                .and_modify(|m| *m |= mask)
                .or_insert(mask);
        }

        // Actually resolve the references
        let external_refs: Vec<_> = external_refs.into_iter().collect();
        let node_meta = resolve_external_references(&context, &node_managers, &external_refs).await;
        let node_map: HashMap<_, _> = node_meta
            .iter()
            .filter_map(|n| n.as_ref())
            .map(|n| (&n.node_id.node_id, n))
            .collect();

        // Finally, process all remaining nodes, including external references.
        // This may still produce a continuation point, for external references.
        {
            let mut session = request.session.write();
            let type_tree = context.get_type_tree_for_user();
            for mut node in nodes.into_iter().chain(batch_nodes) {
                node.resolve_external_references(type_tree.get(), &node_map);

                let (result, input_index) =
                    node.into_result(node_manager_count - 1, node_manager_count, &mut session);
                results[input_index] = Some(result);
            }
        }

        // Cannot be None here, since we are guaranteed to always empty out nodes.
        results.into_iter().map(Option::unwrap).collect()
    };

    let diagnostic_infos = if request.request.release_continuation_points {
        malformed_browse_release(&mut results)
    } else {
        malformed_browse_response("WOTEX_OPCUA_RUST_MALFORMED_BROWSE_NEXT", &mut results)
    };
    let mut response_header = ResponseHeader::new_good(request.request_handle);
    if request.request.release_continuation_points
        && std::env::var_os("WOTEX_OPCUA_RUST_BAD_BROWSE_RELEASE_SERVICE").is_some()
    {
        response_header.service_result = StatusCode::BadUnexpectedError;
    } else if !request.request.release_continuation_points
        && std::env::var_os("WOTEX_OPCUA_RUST_BAD_BROWSE_NEXT_SERVICE").is_some()
    {
        response_header.service_result = StatusCode::BadUnexpectedError;
    }

    Response {
        message: BrowseNextResponse {
            response_header,
            results: Some(results),
            diagnostic_infos,
        }
        .into(),
        request_id: request.request_id,
    }
}

fn browse_release_result() -> BrowseResult {
    BrowseResult {
        status_code: browse_release_status(),
        continuation_point: ByteString::null(),
        references: None,
    }
}

fn malformed_browse_release(results: &mut Vec<BrowseResult>) -> Option<Vec<DiagnosticInfo>> {
    match std::env::var("WOTEX_OPCUA_RUST_MALFORMED_BROWSE_RELEASE").as_deref() {
        Ok("missing_result") => results.clear(),
        Ok("extra_result") => results.push(browse_release_result()),
        Ok("reference") => results[0].references = Some(vec![ReferenceDescription::default()]),
        Ok("continuation") => results[0].continuation_point = ByteString::from(vec![1]),
        Ok("diagnostic") => return Some(vec![DiagnosticInfo::default()]),
        _ => {}
    }
    None
}

fn browse_release_status() -> StatusCode {
    let Ok(marker) = std::env::var("WOTEX_OPCUA_RUST_BAD_BROWSE_RELEASE") else {
        return StatusCode::Good;
    };
    if fs::write(marker, b"responded\n").is_ok() {
        StatusCode::BadUnexpectedError
    } else {
        StatusCode::BadInternalError
    }
}

pub(crate) async fn translate_browse_paths(
    node_managers: NodeManagers,
    request: Request<TranslateBrowsePathsToNodeIdsRequest>,
) -> Response {
    // - We're given a list of (NodeId, BrowsePath) pairs
    // - For a node manager, ask them to explore the browse path, returning _all_ visited nodes in each layer.
    // - This extends the list of (NodeId, BrowsePath) pairs, though each new node should have a shorter browse path.
    // - We keep which node managers returned which nodes. Once every node manager has been asked about every
    //   returned node, the service is finished and we can collect all the node IDs in the bottom layer.

    let mut context = request.context();
    let paths = take_service_items!(
        request,
        request.request.browse_paths,
        request
            .info
            .operational_limits
            .max_nodes_per_translate_browse_paths_to_node_ids
    );

    let mut items: Vec<_> = paths
        .iter()
        .enumerate()
        .map(|(i, p)| BrowsePathItem::new_root(p, i))
        .collect();

    let mut idx = 0;
    let mut iteration = 1;
    let mut any_new_items_in_iteration = false;
    let mut final_results = Vec::new();
    loop {
        let mgr = &node_managers[idx];
        let mut chunk: Vec<_> = items
            .iter_mut()
            .filter(|it| {
                // Item has not yet been marked bad, meaning it failed to resolve somewhere it should.
                it.status().is_good()
                    // Either it's from a previous node manager,
                    && (it.node_manager_index() < idx && it.iteration_number() == iteration
                        // Or it's not from a later node manager in the previous iteration.
                        || it.node_manager_index() > idx && it.iteration_number() == iteration - 1)
                    // Or it may be an external reference with an unmatched browse name.
                    && (!it.path().is_empty() || it.unmatched_browse_name().is_some() && mgr.owns_node(it.node_id()))
            })
            .collect();
        context.current_node_manager_index = idx;

        if !chunk.is_empty() {
            // Call translate on any of the target IDs.
            if let Err(e) = mgr
                .translate_browse_paths_to_node_ids(&context, &mut chunk)
                .instrument(
                    debug_span!("TranslateBrowsePathsToNodeIds", node_manager = %mgr.name()),
                )
                .await
            {
                for n in &mut chunk {
                    if mgr.owns_node(n.node_id()) {
                        n.set_status(e);
                    }
                }
            } else {
                let mut next = Vec::new();
                for n in &mut chunk {
                    let index = n.input_index();
                    for el in n.results_mut().drain(..) {
                        next.push((el, index));
                    }
                    if n.path().is_empty() && n.unmatched_browse_name().is_none() {
                        final_results.push(n.clone())
                    }
                }

                for (n, input_index) in next {
                    let item =
                        BrowsePathItem::new(n, input_index, &items[input_index], idx, iteration);
                    if item.path().is_empty() && item.unmatched_browse_name().is_none() {
                        final_results.push(item);
                    } else {
                        any_new_items_in_iteration = true;
                        items.push(item);
                    }
                }
            }
        }

        idx += 1;
        if idx == node_managers.len() {
            idx = 0;
            iteration += 1;
            if !any_new_items_in_iteration {
                break;
            }
            any_new_items_in_iteration = false;
        }
    }
    // Collect all final paths.
    let mut results: Vec<_> = items
        .iter()
        .take(paths.len())
        .map(|p| BrowsePathResult {
            status_code: p.status(),
            targets: Some(Vec::new()),
        })
        .collect();

    for res in final_results {
        results[res.input_index()]
            .targets
            .as_mut()
            .unwrap()
            .push(BrowsePathTarget {
                target_id: res.node.into(),
                // External server references are not yet supported.
                remaining_path_index: u32::MAX,
            });
    }

    for res in results.iter_mut() {
        if res.targets.is_none() || res.targets.as_ref().is_some_and(|t| t.is_empty()) {
            res.targets = None;
            if res.status_code.is_good() {
                res.status_code = StatusCode::BadNoMatch;
            }
        }
    }

    Response {
        message: TranslateBrowsePathsToNodeIdsResponse {
            response_header: ResponseHeader::new_good(request.request_handle),
            results: Some(results),
            diagnostic_infos: None,
        }
        .into(),
        request_id: request.request_id,
    }
}

pub(crate) async fn register_nodes(
    node_managers: NodeManagers,
    request: Request<RegisterNodesRequest>,
) -> Response {
    let context = request.context();

    let Some(nodes_to_register) = request.request.nodes_to_register else {
        return service_fault!(request, StatusCode::BadNothingToDo);
    };

    if nodes_to_register.is_empty() {
        return service_fault!(request, StatusCode::BadNothingToDo);
    }

    if nodes_to_register.len() > request.info.operational_limits.max_nodes_per_register_nodes {
        return service_fault!(request, StatusCode::BadTooManyOperations);
    }

    let mut items: Vec<_> = nodes_to_register
        .into_iter()
        .map(RegisterNodeItem::new)
        .collect();

    for mgr in &node_managers {
        let mut owned: Vec<_> = items
            .iter_mut()
            .filter(|n| mgr.owns_node(n.node_id()))
            .collect();

        if owned.is_empty() {
            continue;
        }

        // All errors are fatal in this case, node managers should avoid them.
        if let Err(e) = mgr
            .register_nodes(&context, &mut owned)
            .instrument(debug_span!("RegisterNodes", node_manager = %mgr.name()))
            .await
        {
            error!("Register nodes failed for node manager {}: {e}", mgr.name());
            return service_fault!(request, e);
        }
    }

    let registered_node_ids: Vec<_> = items.into_iter().filter_map(|n| n.into_result()).collect();

    Response {
        message: RegisterNodesResponse {
            response_header: ResponseHeader::new_good(request.request_handle),
            registered_node_ids: Some(registered_node_ids),
        }
        .into(),
        request_id: request.request_id,
    }
}

pub(crate) async fn unregister_nodes(
    node_managers: NodeManagers,
    request: Request<UnregisterNodesRequest>,
) -> Response {
    let context = request.context();

    let Some(nodes_to_unregister) = request.request.nodes_to_unregister else {
        return service_fault!(request, StatusCode::BadNothingToDo);
    };

    if nodes_to_unregister.is_empty() {
        return service_fault!(request, StatusCode::BadNothingToDo);
    }

    if nodes_to_unregister.len() > request.info.operational_limits.max_nodes_per_register_nodes {
        return service_fault!(request, StatusCode::BadTooManyOperations);
    }

    for mgr in &node_managers {
        let owned: Vec<_> = nodes_to_unregister
            .iter()
            .filter(|n| mgr.owns_node(n))
            .collect();

        if owned.is_empty() {
            continue;
        }

        // All errors are fatal in this case, node managers should avoid them.
        if let Err(e) = mgr
            .unregister_nodes(&context, &owned)
            .instrument(debug_span!("UnregisterNodes", node_manager = %mgr.name()))
            .await
        {
            error!(
                "Unregister nodes failed for node manager {}: {e}",
                mgr.name()
            );
            return service_fault!(request, e);
        }
    }

    Response {
        message: UnregisterNodesResponse {
            response_header: ResponseHeader::new_good(request.request_handle),
        }
        .into(),
        request_id: request.request_id,
    }
}
