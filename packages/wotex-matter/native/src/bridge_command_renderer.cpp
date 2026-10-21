#include "wotex_matter/bridge_command_renderer.hpp"
#include "wotex_matter/bridge_replies.hpp"

#include <data-model-providers/codegen/CodegenDataModelProvider.h>
#include <algorithm>
#include <cstdlib>

namespace wotex::matter {
SdkBridgeCommandRenderer::~SdkBridgeCommandRenderer() {
  if (endpoints_) std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
}
CHIP_ERROR SdkBridgeCommandRenderer::Attach(SdkBridgeEndpointBinding &endpoints) noexcept {
  if (used_) return CHIP_ERROR_INCORRECT_STATE;
  used_ = true;
  if (!endpoints.initialized()) return CHIP_ERROR_INCORRECT_STATE;
  endpoints_ = &endpoints;
  return CHIP_NO_ERROR;
}
CHIP_ERROR SdkBridgeCommandRenderer::Finish() noexcept {
  if (!used_ || finished_) return CHIP_ERROR_INCORRECT_STATE;
  finished_ = true;
  endpoints_ = nullptr;
  return CHIP_NO_ERROR;
}
CHIP_ERROR SdkBridgeCommandRenderer::Completed(chip::app::CommandHandler &handler,
                                               const BridgeInvocation &invocation) noexcept try {
  if (!endpoints_ || !endpoints_->initialized()) return CHIP_ERROR_INCORRECT_STATE;
  const auto &request = invocation.request;
  if (request.operation != BridgeRequestMetadata::Operation::Invoke || request.endpoint < 3 ||
      invocation.arguments.empty() ||
      invocation.arguments.size() > SdkBridgeInvokeContexts::kMaximumArgumentsBytes)
    return CHIP_ERROR_INVALID_ARGUMENT;
  const auto command = request.member;
  std::optional<chip::CommandId> response;
  switch (request.cluster) {
  case 3:
    if (command != 0 && command != 64) return CHIP_IM_GLOBAL_STATUS(UnsupportedCommand);
    break;
  case 4:
    if (command > 5) return CHIP_IM_GLOBAL_STATUS(UnsupportedCommand);
    if (command <= 3) response = command;
    break;
  case 6:
    if (command > 2 && command != 64 && command != 65 && command != 66)
      return CHIP_IM_GLOBAL_STATUS(UnsupportedCommand);
    break;
  case 98:
    if (command > 6 && command != 64) return CHIP_IM_GLOBAL_STATUS(UnsupportedCommand);
    if (command != 5) response = command;
    break;
  default:
    return CHIP_IM_GLOBAL_STATUS(UnsupportedCluster);
  }
  std::string thing;
  ReturnErrorOnFailure(endpoints_->ResolveThing(request.endpoint, thing));
  auto &provider = chip::app::CodegenDataModelProvider::Instance();
  chip::ReadOnlyBufferBuilder<chip::app::DataModel::AcceptedCommandEntry> builder;
  ReturnErrorOnFailure(provider.AcceptedCommands({request.endpoint, request.cluster}, builder));
  const auto commands = builder.TakeBuffer();
  if (std::none_of(commands.begin(), commands.end(),
                   [&](const auto &entry) { return entry.commandId == command; }))
    return CHIP_IM_GLOBAL_STATUS(UnsupportedCommand);
  const auto permitted = response ? chip::Span<const chip::CommandId>(&*response, 1)
                                  : chip::Span<const chip::CommandId>();
  SdkBridgeCommandReply reply(handler, request, permitted);
  ReturnErrorOnFailure(reply.configuration_status());
  chip::TLV::TLVReader arguments;
  arguments.Init(invocation.arguments.data(), invocation.arguments.size());
  ReturnErrorOnFailure(arguments.Next());
  const chip::app::ConcreteCommandPath path(request.endpoint, request.cluster, command);
  chip::app::DataModel::InvokeRequest native(path, request.principal);
  native.invokeFlags.Set(chip::app::DataModel::InvokeFlags::kTimed, request.timed);
  const auto result = provider.InvokeCommand(native, arguments, &reply);
  if (result) (void)reply.FallibleAddStatus(path, result->GetStatusCode());
  return reply.result();
} catch (...) {
  return CHIP_ERROR_NO_MEMORY;
}
}
