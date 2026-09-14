#ifndef WOTEX_MATTER_VALUE_HPP
#define WOTEX_MATTER_VALUE_HPP

#include <cstdint>
#include <optional>
#include <vector>

namespace wotex::matter {

enum class MemberKind { Attribute, Command, Event };
enum class Operation { Read, Write, Invoke, Subscribe };
enum class Schema {
  NullableI16,
  I16,
  U8,
  Boolean,
  EmptyStructure,
  DeviceTypeList,
  ClusterList,
  PartsList,
  ReachableEvent,
  AccessControlList,
  WindowStatus,
  NullableFabricIndex,
  NullableVendorId
};

enum class ElementType { Null, I16, U8, U16, U32, U64, Boolean, Structure, Array };
enum class TagKind { Anonymous, Context };

struct Tag {
  TagKind kind{TagKind::Anonymous};
  std::uint8_t id{0};
};

struct Element {
  Tag tag{};
  ElementType type{ElementType::Null};
  std::int64_t signed_value{0};
  std::uint64_t unsigned_value{0};
  bool boolean_value{false};
  std::vector<Element> children{};
};

struct DeviceType {
  std::uint32_t id{0};
  std::uint16_t revision{0};
};

enum class NativeValueKind {
  Null,
  Signed,
  Unsigned,
  Boolean,
  EmptyStructure,
  DeviceTypes,
  Identifiers,
  Reachable
};

struct NativeValue {
  NativeValueKind kind{NativeValueKind::Null};
  std::int64_t signed_value{0};
  std::uint64_t unsigned_value{0};
  bool boolean_value{false};
  std::vector<DeviceType> device_types{};
  std::vector<std::uint32_t> identifiers{};

  static NativeValue null_value();
  static NativeValue signed_integer(std::int64_t value);
  static NativeValue unsigned_integer(std::uint64_t value);
  static NativeValue boolean(bool value);
  static NativeValue empty_structure();
  static NativeValue device_type_list(std::vector<DeviceType> values);
  static NativeValue identifier_list(std::vector<std::uint32_t> values);
  static NativeValue reachable(bool value);
};

struct Descriptor {
  MemberKind kind;
  std::uint32_t cluster;
  std::uint32_t member;
  Schema schema;
  std::uint8_t operations;
};

enum class ConversionError {
  None,
  UnsupportedSchema,
  UnsupportedOperation,
  NotWritable,
  InvalidValue
};

struct Conversion {
  ConversionError error{ConversionError::None};
  std::optional<Element> element{};
};

std::optional<Descriptor> lookup_descriptor(MemberKind kind, std::uint32_t cluster,
                                            std::uint32_t member);

Conversion convert_value(MemberKind kind, std::uint32_t cluster, std::uint32_t member,
                         Operation operation, const NativeValue &value);

ConversionError validate_element(MemberKind kind, std::uint32_t cluster,
                                 std::uint32_t member, Operation operation,
                                 const Element &element);

} // namespace wotex::matter

#endif
