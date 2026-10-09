#include "wotex_matter/bridge_replies.hpp"
#include "wotex_matter/bridge_server.hpp"

#include <algorithm>
#include <cstdlib>

namespace wotex::matter {

using CommandPath = chip::app::ConcreteCommandPath;
using ClusterStatus = chip::Protocols::InteractionModel::ClusterStatusCode;
using Encodable = chip::app::DataModel::EncodableToTLV;

SdkBridgeCommandReply::SdkBridgeCommandReply(chip::app::CommandHandler &handler,
                                             const BridgeRequestMetadata &request,
                                             chip::Span<const chip::CommandId> responses)
    : handler_(handler), request_(request),
      path_(request.endpoint, request.cluster, request.member) {
  if (request.operation != BridgeRequestMetadata::Operation::Invoke || !path_.HasValidIds() ||
      !chip::IsValidCommandId(path_.mCommandId) || responses.size() > responses_.size()) {
    validation_error_ = Remember(CHIP_ERROR_INVALID_ARGUMENT);
    return;
  }
  for (const auto id : responses) {
    const auto end = responses_.begin() + static_cast<std::ptrdiff_t>(count_);
    if (!chip::IsValidCommandId(id) || std::find(responses_.begin(), end, id) != end) {
      validation_error_ = Remember(CHIP_ERROR_INVALID_ARGUMENT);
      return;
    }
    responses_[count_++] = id;
  }
}

CHIP_ERROR SdkBridgeCommandReply::configuration_status() const { return validation_error_; }
CHIP_ERROR SdkBridgeCommandReply::result() const {
  if (error_ != CHIP_NO_ERROR) return error_;
  return replied_ ? CHIP_NO_ERROR : CHIP_ERROR_INCORRECT_STATE;
}
bool SdkBridgeCommandReply::replied() const { return replied_; }

CHIP_ERROR SdkBridgeCommandReply::CheckPath(const CommandPath &path) {
  if (validation_error_ != CHIP_NO_ERROR) return validation_error_;
  if (replied_) return CHIP_ERROR_INCORRECT_STATE;
  if (path.mEndpointId != path_.mEndpointId || path.mClusterId != path_.mClusterId ||
      path.mCommandId != path_.mCommandId) {
    validation_error_ = CHIP_ERROR_INVALID_ARGUMENT;
    return validation_error_;
  }
  return CHIP_NO_ERROR;
}

CHIP_ERROR SdkBridgeCommandReply::CheckResponse(const CommandPath &path, chip::CommandId response) {
  const auto error = CheckPath(path);
  if (error != CHIP_NO_ERROR) return error;
  const auto end = responses_.begin() + static_cast<std::ptrdiff_t>(count_);
  if (std::find(responses_.begin(), end, response) == end) {
    validation_error_ = CHIP_ERROR_INVALID_ARGUMENT;
    return validation_error_;
  }
  return CHIP_NO_ERROR;
}

CHIP_ERROR SdkBridgeCommandReply::Remember(CHIP_ERROR error) {
  if (error_ == CHIP_NO_ERROR) error_ = error;
  return error;
}

CHIP_ERROR SdkBridgeCommandReply::FallibleAddStatus(const CommandPath &path,
                                                    const ClusterStatus &status,
                                                    const char *context) {
  const auto admitted = CheckPath(path);
  if (admitted != CHIP_NO_ERROR) return Remember(admitted);
  const auto error = handler_.FallibleAddStatus(path_, status, context);
  if (error == CHIP_NO_ERROR) replied_ = true;
  return Remember(error);
}

void SdkBridgeCommandReply::AddStatus(const CommandPath &path, const ClusterStatus &status,
                                      const char *context) {
  (void)FallibleAddStatus(path, status, context);
}

CHIP_ERROR SdkBridgeCommandReply::EncodeData(chip::CommandId response, const Encodable &value) {
  const auto error = handler_.AddResponseData(path_, response, value);
  if (error == CHIP_NO_ERROR) replied_ = true;
  return Remember(error);
}

CHIP_ERROR SdkBridgeCommandReply::AddResponseData(const CommandPath &path, chip::CommandId response,
                                                  const Encodable &value) {
  const auto admitted = CheckResponse(path, response);
  return admitted == CHIP_NO_ERROR ? EncodeData(response, value) : Remember(admitted);
}

void SdkBridgeCommandReply::AddResponse(const CommandPath &path, chip::CommandId response,
                                        const Encodable &value) {
  const auto admitted = CheckResponse(path, response);
  if (admitted != CHIP_NO_ERROR) {
    (void)Remember(admitted);
    return;
  }
  if (EncodeData(response, value) != CHIP_NO_ERROR) {
    // SDK AddResponse specifies a Failure-status attempt after any data
    // encoding failure. Local path/scope refusal never enters the encoder.
    (void)FallibleAddStatus(path_,
                            ClusterStatus(chip::Protocols::InteractionModel::Status::Failure));
  }
}

chip::FabricIndex SdkBridgeCommandReply::GetAccessingFabricIndex() const {
  return request_.principal.fabricIndex;
}
chip::Access::SubjectDescriptor SdkBridgeCommandReply::GetSubjectDescriptor() const {
  return request_.principal;
}
bool SdkBridgeCommandReply::IsTimedInvoke() const { return request_.timed; }
chip::Messaging::ExchangeContext *SdkBridgeCommandReply::GetExchangeContext() const {
  return nullptr;
}
void SdkBridgeCommandReply::FlushAcksRightAwayOnSlowCommand() {}
void SdkBridgeCommandReply::IncrementHoldOff(Handle *) {
  std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
}
void SdkBridgeCommandReply::DecrementHoldOff(Handle *) {
  std::_Exit(SdkBridgeServerBinding::kStartupFailureExit);
}

} // namespace wotex::matter
