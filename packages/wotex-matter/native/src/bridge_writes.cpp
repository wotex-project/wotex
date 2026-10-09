#include "wotex_matter/bridge_writes.hpp"

#include <app/data-model/Nullable.h>

namespace wotex::matter {
namespace {

bool SamePrincipal(const chip::Access::SubjectDescriptor &left,
                   const chip::Access::SubjectDescriptor &right) {
  return left.fabricIndex == right.fabricIndex && left.authMode == right.authMode &&
      left.subject == right.subject && left.cats.values == right.cats.values &&
      left.isCommissioning == right.isCommissioning;
}

CHIP_ERROR CopyScalar(const BridgeRequestMetadata &request,
                      chip::app::AttributeValueDecoder &decoder, BridgeWriteScalar &result) {
  using List = chip::app::ConcreteDataAttributePath::ListOperation;
  if (request.operation != BridgeRequestMetadata::Operation::Write || request.endpoint < 3 ||
      request.endpoint == chip::kInvalidEndpointId || request.list_operation != List::NotList ||
      !SamePrincipal(request.principal, decoder.GetSubjectDescriptor())) {
    return CHIP_ERROR_INVALID_ARGUMENT;
  }
  if ((request.cluster == 0x0003 && request.member == 0x0000) ||
      (request.cluster == 0x0006 && (request.member == 0x4001 || request.member == 0x4002))) {
    std::uint16_t value = 0;
    const auto error = decoder.Decode(value);
    if (error != CHIP_NO_ERROR) return error;
    result = value;
    return CHIP_NO_ERROR;
  }
  if (request.cluster == 0x0006 && request.member == 0x4003) {
    chip::app::DataModel::Nullable<std::uint8_t> value;
    const auto error = decoder.Decode(value);
    if (error != CHIP_NO_ERROR) return error;
    if (!value.IsNull() && value.Value() > 2) return CHIP_IM_GLOBAL_STATUS(ConstraintError);
    result = value.IsNull() ? std::optional<std::uint8_t>{} : std::make_optional(value.Value());
    return CHIP_NO_ERROR;
  }
  return CHIP_IM_GLOBAL_STATUS(UnsupportedWrite);
}

CHIP_ERROR AdmissionError(BridgeConsumerHandoff::Admission admission) {
  using A = BridgeConsumerHandoff::Admission;
  switch (admission) {
  case A::Reserved:
    return CHIP_NO_ERROR;
  case A::Busy:
    return CHIP_ERROR_BUSY;
  case A::InvalidClock:
  case A::InvalidDeadline:
    return CHIP_ERROR_INVALID_ARGUMENT;
  case A::Closed:
  case A::Exhausted:
    return CHIP_ERROR_INCORRECT_STATE;
  }
  return CHIP_ERROR_INVALID_ARGUMENT;
}

} // namespace

CHIP_ERROR StartBridgeWrite(BridgeConsumerHandoff &custody, BridgeRequestMetadata request,
                            chip::app::AttributeValueDecoder &decoder, std::uint64_t now_ms,
                            std::uint64_t deadline_ms, BridgeAttributeWrite &result) {
  BridgeAttributeWrite copied;
  copied.request = request;
  const auto error = CopyScalar(request, decoder, copied.value);
  if (error != CHIP_NO_ERROR) return error;
  const auto admitted = AdmissionError(custody.Reserve(now_ms, deadline_ms, copied.ticket));
  if (admitted != CHIP_NO_ERROR) return admitted;
  copied.deadline_ms = deadline_ms;
  result = copied;
  return CHIP_NO_ERROR;
}

} // namespace wotex::matter
