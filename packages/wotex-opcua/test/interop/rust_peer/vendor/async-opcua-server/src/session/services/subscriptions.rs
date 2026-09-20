use crate::{
    node_manager::{NodeManagers, RequestContext},
    session::{controller::Response, message_handler::Request},
    SubscriptionCache,
};

use opcua_types::{
    DeleteSubscriptionsRequest, DeleteSubscriptionsResponse, DiagnosticInfo, ResponseHeader,
    StatusCode,
};
use tracing::debug_span;
use tracing_futures::Instrument;

pub(crate) async fn delete_subscriptions(
    node_managers: NodeManagers,
    request: Request<DeleteSubscriptionsRequest>,
) -> Response {
    request.info.record_delete_subscriptions_request();
    let mut context = request.context();
    let items = take_service_items!(
        request,
        request.request.subscription_ids,
        request.info.operational_limits.max_subscriptions_per_call
    );

    let mut results = match delete_subscriptions_inner(
        node_managers,
        items,
        &request.subscriptions,
        &mut context,
    )
    .await
    {
        Ok(r) => r,
        Err(e) => return service_fault!(request, e),
    };

    let diagnostic_infos =
        match std::env::var("WOTEX_OPCUA_RUST_MALFORMED_DELETE_SUBSCRIPTION").as_deref() {
            Ok("missing_result") => {
                results.clear();
                None
            }
            Ok("extra_result") => {
                results.push(StatusCode::Good);
                None
            }
            Ok("bad_status") => {
                if let Some(status) = results.first_mut() {
                    *status = StatusCode::BadUnexpectedError;
                }
                None
            }
            Ok("diagnostic") => Some(vec![DiagnosticInfo::default()]),
            _ => None,
        };
    let mut response_header = ResponseHeader::new_good(request.request_handle);
    if std::env::var_os("WOTEX_OPCUA_RUST_BAD_DELETE_SUBSCRIPTION_SERVICE").is_some() {
        response_header.service_result = StatusCode::BadUnexpectedError;
    }

    Response {
        message: DeleteSubscriptionsResponse {
            response_header,
            results: Some(results),
            diagnostic_infos,
        }
        .into(),
        request_id: request.request_id,
    }
}

pub(crate) async fn delete_subscriptions_inner(
    node_managers: NodeManagers,
    to_delete: Vec<u32>,
    subscriptions: &SubscriptionCache,
    context: &mut RequestContext,
) -> Result<Vec<StatusCode>, StatusCode> {
    let results =
        subscriptions.delete_subscriptions(context.session_id, &to_delete, &context.info)?;

    for (idx, mgr) in node_managers.iter().enumerate() {
        context.current_node_manager_index = idx;
        let owned: Vec<_> = results
            .iter()
            .filter(|f| f.0.is_good())
            .flat_map(|f| f.1.iter().filter(|i| mgr.owns_node(i.node_id())))
            .collect();

        if owned.is_empty() {
            continue;
        }

        mgr.delete_monitored_items(context, &owned)
            .instrument(debug_span!("DeleteMonitoredItems", node_manager = %mgr.name()))
            .await;
    }

    Ok(results.into_iter().map(|r| r.0).collect())
}
