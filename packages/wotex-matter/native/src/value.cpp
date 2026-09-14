#include "wotex_matter/value.hpp"

#include <array>
#include <limits>
#include <utility>

namespace wotex::matter {
namespace {

constexpr std::uint8_t kRead = 1U << 0U;
constexpr std::uint8_t kWrite = 1U << 1U;
constexpr std::uint8_t kInvoke = 1U << 2U;
constexpr std::uint8_t kSubscribe = 1U << 3U;

constexpr std::array<Descriptor, 15> kDescriptors{{
    {MemberKind::Attribute, 0x0201, 0x0000, Schema::NullableI16, kRead | kSubscribe},
    {MemberKind::Attribute, 0x0201, 0x0011, Schema::I16, kRead | kWrite},
    {MemberKind::Attribute, 0x0201, 0x0012, Schema::I16, kRead | kWrite},
    {MemberKind::Attribute, 0x0201, 0x001C, Schema::U8, kRead | kWrite},
    {MemberKind::Attribute, 0x0006, 0x0000, Schema::Boolean, kRead | kSubscribe},
    {MemberKind::Command, 0x0006, 0x0000, Schema::EmptyStructure, kInvoke},
    {MemberKind::Command, 0x0006, 0x0001, Schema::EmptyStructure, kInvoke},
    {MemberKind::Command, 0x0006, 0x0002, Schema::EmptyStructure, kInvoke},
    {MemberKind::Attribute, 0x001D, 0x0000, Schema::DeviceTypeList, kRead},
    {MemberKind::Attribute, 0x001D, 0x0001, Schema::ClusterList, kRead},
    {MemberKind::Attribute, 0x001D, 0x0002, Schema::ClusterList, kRead},
    {MemberKind::Attribute, 0x001D, 0x0003, Schema::PartsList, kRead},
    {MemberKind::Attribute, 0x0039, 0x0011, Schema::Boolean, kRead | kSubscribe},
    {MemberKind::Event, 0x0039, 0x0003, Schema::ReachableEvent, kRead | kSubscribe},
    {MemberKind::Attribute, 0x0402, 0x0000, Schema::NullableI16, kRead | kSubscribe},
}};

constexpr std::uint8_t operation_flag(Operation operation) {
  switch (operation) {
  case Operation::Read:
    return kRead;
  case Operation::Write:
    return kWrite;
  case Operation::Invoke:
    return kInvoke;
  case Operation::Subscribe:
    return kSubscribe;
  }
  return 0;
}

Element element(ElementType type) {
  Element value;
  value.type = type;
  return value;
}

Element context_element(ElementType type, std::uint8_t id) {
  Element value = element(type);
  value.tag = Tag{TagKind::Context, id};
  return value;
}

Conversion success(Element value) {
  return Conversion{ConversionError::None, std::move(value)};
}

Conversion failure(ConversionError error) { return Conversion{error, std::nullopt}; }

bool valid_cluster(std::uint32_t value) {
  return value <= 0x7FFFU ||
         (value >= 0x00010000U && value <= 0xFFF47FFFU && (value % 65536U) <= 0x7FFFU);
}

Conversion convert(const Descriptor &descriptor, const NativeValue &value) {
  switch (descriptor.schema) {
  case Schema::NullableI16:
    if (value.kind == NativeValueKind::Null) {
      return success(element(ElementType::Null));
    }
    [[fallthrough]];

  case Schema::I16:
    if (value.kind == NativeValueKind::Signed &&
        value.signed_value >= std::numeric_limits<std::int16_t>::min() &&
        value.signed_value <= std::numeric_limits<std::int16_t>::max()) {
      Element result = element(ElementType::I16);
      result.signed_value = value.signed_value;
      return success(std::move(result));
    }
    break;

  case Schema::U8:
    if (value.kind == NativeValueKind::Unsigned && value.unsigned_value <= 0xFFU) {
      Element result = element(ElementType::U8);
      result.unsigned_value = value.unsigned_value;
      return success(std::move(result));
    }
    break;

  case Schema::Boolean:
    if (value.kind == NativeValueKind::Boolean) {
      Element result = element(ElementType::Boolean);
      result.boolean_value = value.boolean_value;
      return success(std::move(result));
    }
    break;

  case Schema::EmptyStructure:
    if (value.kind == NativeValueKind::EmptyStructure) {
      return success(element(ElementType::Structure));
    }
    break;

  case Schema::DeviceTypeList:
    if (value.kind == NativeValueKind::DeviceTypes && value.device_types.size() <= 1023U) {
      Element result = element(ElementType::Array);
      result.children.reserve(value.device_types.size());

      for (const DeviceType &device_type : value.device_types) {
        Element entry = element(ElementType::Structure);
        Element id = context_element(ElementType::U32, 0);
        id.unsigned_value = device_type.id;
        Element revision = context_element(ElementType::U16, 1);
        revision.unsigned_value = device_type.revision;
        entry.children.push_back(std::move(id));
        entry.children.push_back(std::move(revision));
        result.children.push_back(std::move(entry));
      }
      return success(std::move(result));
    }
    break;

  case Schema::ClusterList:
    if (value.kind == NativeValueKind::Identifiers && value.identifiers.size() <= 1023U) {
      Element result = element(ElementType::Array);
      result.children.reserve(value.identifiers.size());

      for (const std::uint32_t identifier : value.identifiers) {
        if (!valid_cluster(identifier)) {
          return failure(ConversionError::InvalidValue);
        }
        Element child = element(ElementType::U32);
        child.unsigned_value = identifier;
        result.children.push_back(std::move(child));
      }
      return success(std::move(result));
    }
    break;

  case Schema::PartsList:
    if (value.kind == NativeValueKind::Identifiers && value.identifiers.size() <= 1023U) {
      Element result = element(ElementType::Array);
      result.children.reserve(value.identifiers.size());

      for (const std::uint32_t identifier : value.identifiers) {
        if (identifier > 0xFFFEU) {
          return failure(ConversionError::InvalidValue);
        }
        Element child = element(ElementType::U16);
        child.unsigned_value = identifier;
        result.children.push_back(std::move(child));
      }
      return success(std::move(result));
    }
    break;

  case Schema::ReachableEvent:
    if (value.kind == NativeValueKind::Reachable) {
      Element result = element(ElementType::Structure);
      Element child = context_element(ElementType::Boolean, 0);
      child.boolean_value = value.boolean_value;
      result.children.push_back(std::move(child));
      return success(std::move(result));
    }
    break;
  }

  return failure(ConversionError::InvalidValue);
}

} // namespace

NativeValue NativeValue::null_value() { return NativeValue{}; }

NativeValue NativeValue::signed_integer(std::int64_t value) {
  NativeValue result;
  result.kind = NativeValueKind::Signed;
  result.signed_value = value;
  return result;
}

NativeValue NativeValue::unsigned_integer(std::uint64_t value) {
  NativeValue result;
  result.kind = NativeValueKind::Unsigned;
  result.unsigned_value = value;
  return result;
}

NativeValue NativeValue::boolean(bool value) {
  NativeValue result;
  result.kind = NativeValueKind::Boolean;
  result.boolean_value = value;
  return result;
}

NativeValue NativeValue::empty_structure() {
  NativeValue result;
  result.kind = NativeValueKind::EmptyStructure;
  return result;
}

NativeValue NativeValue::device_type_list(std::vector<DeviceType> values) {
  NativeValue result;
  result.kind = NativeValueKind::DeviceTypes;
  result.device_types = std::move(values);
  return result;
}

NativeValue NativeValue::identifier_list(std::vector<std::uint32_t> values) {
  NativeValue result;
  result.kind = NativeValueKind::Identifiers;
  result.identifiers = std::move(values);
  return result;
}

NativeValue NativeValue::reachable(bool value) {
  NativeValue result;
  result.kind = NativeValueKind::Reachable;
  result.boolean_value = value;
  return result;
}

std::optional<Descriptor> lookup_descriptor(MemberKind kind, std::uint32_t cluster,
                                            std::uint32_t member) {
  for (const Descriptor &descriptor : kDescriptors) {
    if (descriptor.kind == kind && descriptor.cluster == cluster && descriptor.member == member) {
      return descriptor;
    }
  }
  return std::nullopt;
}

Conversion convert_value(MemberKind kind, std::uint32_t cluster, std::uint32_t member,
                         Operation operation, const NativeValue &value) {
  const std::optional<Descriptor> descriptor = lookup_descriptor(kind, cluster, member);
  if (!descriptor.has_value()) {
    return failure(ConversionError::UnsupportedSchema);
  }

  if ((descriptor->operations & operation_flag(operation)) == 0U) {
    return failure(operation == Operation::Write ? ConversionError::NotWritable
                                                 : ConversionError::UnsupportedOperation);
  }

  return convert(*descriptor, value);
}

} // namespace wotex::matter
