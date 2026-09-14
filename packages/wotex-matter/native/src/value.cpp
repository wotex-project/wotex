#include "wotex_matter/value.hpp"

#include <algorithm>
#include <array>
#include <limits>
#include <utility>

namespace wotex::matter {
namespace {

constexpr std::uint8_t kRead = 1U << 0U;
constexpr std::uint8_t kWrite = 1U << 1U;
constexpr std::uint8_t kInvoke = 1U << 2U;
constexpr std::uint8_t kSubscribe = 1U << 3U;

constexpr std::array<Descriptor, 19> kDescriptors{{
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
    {MemberKind::Attribute, 0x001F, 0x0000, Schema::AccessControlList, kRead | kWrite},
    {MemberKind::Attribute, 0x003C, 0x0000, Schema::WindowStatus, kRead},
    {MemberKind::Attribute, 0x003C, 0x0001, Schema::NullableFabricIndex, kRead},
    {MemberKind::Attribute, 0x003C, 0x0002, Schema::NullableVendorId, kRead},
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

const Element *ContextField(const Element &structure, std::uint8_t id) {
  const Element *result = nullptr;
  for (const Element &field : structure.children) {
    if (field.tag.kind != TagKind::Context) {
      return nullptr;
    }
    if (field.tag.id == id) {
      if (result != nullptr) {
        return nullptr;
      }
      result = &field;
    }
  }
  return result;
}

bool NullableTargetField(const Element *field, ElementType type,
                         std::uint64_t maximum, bool cluster = false) {
  return field != nullptr &&
      (field->type == ElementType::Null ||
       (field->type == type && field->unsigned_value <= maximum &&
        (!cluster || valid_cluster(
            static_cast<std::uint32_t>(field->unsigned_value)))));
}

bool ValidTarget(const Element &target) {
  if (target.tag.kind != TagKind::Anonymous ||
      target.type != ElementType::Structure || target.children.size() != 3U) {
    return false;
  }
  const Element *cluster = ContextField(target, 0);
  const Element *endpoint = ContextField(target, 1);
  const Element *device_type = ContextField(target, 2);
  return NullableTargetField(cluster, ElementType::U32, 0xFFFFFFFFU, true) &&
      NullableTargetField(endpoint, ElementType::U16, 0xFFFEU) &&
      NullableTargetField(device_type, ElementType::U32, 0xFFFFFFFFU) &&
      (cluster->type != ElementType::Null ||
       endpoint->type != ElementType::Null ||
       device_type->type != ElementType::Null) &&
      (endpoint->type == ElementType::Null ||
       device_type->type == ElementType::Null);
}

bool ValidNullableSubjects(const Element *subjects) {
  if (subjects == nullptr || subjects->tag.kind != TagKind::Context ||
      subjects->tag.id != 3U) {
    return false;
  }
  if (subjects->type == ElementType::Null) {
    return true;
  }
  return subjects->type == ElementType::Array &&
      subjects->children.size() <= 64U &&
      std::all_of(subjects->children.begin(), subjects->children.end(),
                  [](const Element &subject) {
                    return subject.tag.kind == TagKind::Anonymous &&
                        subject.type == ElementType::U64;
                  });
}

bool ValidNullableTargets(const Element *targets) {
  if (targets == nullptr || targets->tag.kind != TagKind::Context ||
      targets->tag.id != 4U) {
    return false;
  }
  return targets->type == ElementType::Null ||
      (targets->type == ElementType::Array && targets->children.size() <= 64U &&
       std::all_of(targets->children.begin(), targets->children.end(),
                   ValidTarget));
}

bool valid_access_control_list(const Element &element, Operation operation) {
  if (element.type != ElementType::Array ||
      element.tag.kind != TagKind::Anonymous || element.children.size() > 64U) {
    return false;
  }
  for (const Element &entry : element.children) {
    if (entry.tag.kind != TagKind::Anonymous ||
        entry.type != ElementType::Structure || entry.children.size() < 4U ||
        entry.children.size() > 6U) {
      return false;
    }
    const Element *privilege = ContextField(entry, 1);
    const Element *auth_mode = ContextField(entry, 2);
    const Element *subjects = ContextField(entry, 3);
    const Element *targets = ContextField(entry, 4);
    const Element *auxiliary = ContextField(entry, 5);
    const Element *fabric = ContextField(entry, 254);
    for (const Element &field : entry.children) {
      if (field.tag.kind != TagKind::Context ||
          (field.tag.id != 1U && field.tag.id != 2U && field.tag.id != 3U &&
           field.tag.id != 4U && field.tag.id != 5U &&
           field.tag.id != 254U)) {
        return false;
      }
    }
    if (privilege == nullptr || privilege->type != ElementType::U8 ||
        privilege->unsigned_value < 1U || privilege->unsigned_value > 5U ||
        auth_mode == nullptr || auth_mode->type != ElementType::U8 ||
        auth_mode->unsigned_value < 2U || auth_mode->unsigned_value > 3U ||
        !ValidNullableSubjects(subjects) || !ValidNullableTargets(targets) ||
        (auxiliary != nullptr &&
         (auxiliary->type != ElementType::U8 ||
          auxiliary->unsigned_value > 1U)) ||
        (fabric != nullptr &&
         (operation != Operation::Read || fabric->type != ElementType::U8 ||
          fabric->unsigned_value < 1U || fabric->unsigned_value > 254U))) {
      return false;
    }
  }
  return true;
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

  case Schema::WindowStatus:
    if (value.kind == NativeValueKind::Unsigned && value.unsigned_value <= 2U) {
      Element result = element(ElementType::U8);
      result.unsigned_value = value.unsigned_value;
      return success(std::move(result));
    }
    break;

  case Schema::NullableFabricIndex:
  case Schema::NullableVendorId:
    if (value.kind == NativeValueKind::Null) {
      return success(element(ElementType::Null));
    }
    if (value.kind == NativeValueKind::Unsigned &&
        ((descriptor.schema == Schema::NullableFabricIndex &&
          value.unsigned_value >= 1U && value.unsigned_value <= 254U) ||
         (descriptor.schema == Schema::NullableVendorId &&
          value.unsigned_value >= 1U && value.unsigned_value <= 0xFFFEU))) {
      Element result = element(descriptor.schema == Schema::NullableFabricIndex
                                   ? ElementType::U8
                                   : ElementType::U16);
      result.unsigned_value = value.unsigned_value;
      return success(std::move(result));
    }
    break;

  case Schema::AccessControlList:
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

ConversionError validate_element(MemberKind kind, std::uint32_t cluster,
                                 std::uint32_t member, Operation operation,
                                 const Element &element) {
  const std::optional<Descriptor> descriptor =
      lookup_descriptor(kind, cluster, member);
  if (!descriptor.has_value()) {
    return ConversionError::UnsupportedSchema;
  }
  if ((descriptor->operations & operation_flag(operation)) == 0U) {
    return operation == Operation::Write ? ConversionError::NotWritable
                                         : ConversionError::UnsupportedOperation;
  }
  if (element.tag.kind != TagKind::Anonymous) {
    return ConversionError::InvalidValue;
  }

  switch (descriptor->schema) {
  case Schema::NullableI16:
    if (element.type == ElementType::Null) {
      return ConversionError::None;
    }
    [[fallthrough]];
  case Schema::I16:
    return element.type == ElementType::I16 &&
            element.signed_value >= std::numeric_limits<std::int16_t>::min() &&
            element.signed_value <= std::numeric_limits<std::int16_t>::max()
        ? ConversionError::None
        : ConversionError::InvalidValue;
  case Schema::U8:
    return element.type == ElementType::U8 && element.unsigned_value <= 0xFFU
        ? ConversionError::None
        : ConversionError::InvalidValue;
  case Schema::Boolean:
    return element.type == ElementType::Boolean ? ConversionError::None
                                                : ConversionError::InvalidValue;
  case Schema::EmptyStructure:
    return element.type == ElementType::Structure && element.children.empty()
        ? ConversionError::None
        : ConversionError::InvalidValue;
  case Schema::DeviceTypeList:
    if (element.type != ElementType::Array || element.children.size() > 1023U) {
      return ConversionError::InvalidValue;
    }
    for (const Element &entry : element.children) {
      if (entry.tag.kind != TagKind::Anonymous ||
          entry.type != ElementType::Structure || entry.children.size() != 2U ||
          entry.children[0].tag.kind != TagKind::Context ||
          entry.children[0].tag.id != 0 ||
          entry.children[0].type != ElementType::U32 ||
          entry.children[1].tag.kind != TagKind::Context ||
          entry.children[1].tag.id != 1 ||
          entry.children[1].type != ElementType::U16) {
        return ConversionError::InvalidValue;
      }
    }
    return ConversionError::None;
  case Schema::ClusterList:
    if (element.type != ElementType::Array || element.children.size() > 1023U) {
      return ConversionError::InvalidValue;
    }
    for (const Element &entry : element.children) {
      if (entry.tag.kind != TagKind::Anonymous || entry.type != ElementType::U32 ||
          !valid_cluster(static_cast<std::uint32_t>(entry.unsigned_value))) {
        return ConversionError::InvalidValue;
      }
    }
    return ConversionError::None;
  case Schema::PartsList:
    if (element.type != ElementType::Array || element.children.size() > 1023U) {
      return ConversionError::InvalidValue;
    }
    for (const Element &entry : element.children) {
      if (entry.tag.kind != TagKind::Anonymous || entry.type != ElementType::U16 ||
          entry.unsigned_value > 0xFFFEU) {
        return ConversionError::InvalidValue;
      }
    }
    return ConversionError::None;
  case Schema::ReachableEvent:
    return element.type == ElementType::Structure &&
            element.children.size() == 1 &&
            element.children[0].tag.kind == TagKind::Context &&
            element.children[0].tag.id == 0 &&
            element.children[0].type == ElementType::Boolean
        ? ConversionError::None
        : ConversionError::InvalidValue;
  case Schema::WindowStatus:
    return element.type == ElementType::U8 && element.unsigned_value <= 2U
        ? ConversionError::None
        : ConversionError::InvalidValue;
  case Schema::NullableFabricIndex:
    return element.type == ElementType::Null ||
            (element.type == ElementType::U8 &&
             element.unsigned_value >= 1U && element.unsigned_value <= 254U)
        ? ConversionError::None
        : ConversionError::InvalidValue;
  case Schema::NullableVendorId:
    return element.type == ElementType::Null ||
            (element.type == ElementType::U16 &&
             element.unsigned_value >= 1U &&
             element.unsigned_value <= 0xFFFEU)
        ? ConversionError::None
        : ConversionError::InvalidValue;
  case Schema::AccessControlList:
    return valid_access_control_list(element, operation)
        ? ConversionError::None
        : ConversionError::InvalidValue;
  }
  return ConversionError::InvalidValue;
}

} // namespace wotex::matter
