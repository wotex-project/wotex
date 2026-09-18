#include "wotex_matter/value.hpp"

#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

namespace {

using wotex::matter::Conversion;
using wotex::matter::ConversionError;
using wotex::matter::DeviceType;
using wotex::matter::ElementType;
using wotex::matter::Element;
using wotex::matter::MemberKind;
using wotex::matter::NativeValue;
using wotex::matter::Operation;
using wotex::matter::TagKind;
using wotex::matter::convert_value;
using wotex::matter::validate_element;

void require(bool condition, const std::string &message) {
  if (!condition) {
    std::cerr << message << '\n';
    std::exit(1);
  }
}

wotex::matter::Element successful(Conversion conversion, const std::string &name) {
  require(conversion.error == ConversionError::None, name + " returned an error");
  require(conversion.element.has_value(), name + " omitted its element");
  // NOLINTNEXTLINE(bugprone-unchecked-optional-access): require exits the test when the element is absent
  return std::move(*conversion.element);
}

void scalar_recipes() {
  const auto temperature = successful(
      convert_value(MemberKind::Attribute, 0x0201, 0x0000, Operation::Read,
                    NativeValue::signed_integer(2150)),
      "thermostat temperature");
  require(temperature.type == ElementType::I16 && temperature.signed_value == 2150,
          "thermostat temperature lost signed i16 semantics");

  const auto null_temperature =
      successful(convert_value(MemberKind::Attribute, 0x0402, 0x0000, Operation::Read,
                               NativeValue::null_value()),
                 "nullable sensor");
  require(null_temperature.type == ElementType::Null, "nullable sensor lost null");

  const auto setpoint = successful(
      convert_value(MemberKind::Attribute, 0x0201, 0x0012, Operation::Write,
                    NativeValue::signed_integer(2000)),
      "heating setpoint");
  require(setpoint.type == ElementType::I16 && setpoint.signed_value == 2000,
          "setpoint lost signed i16 semantics");

  const auto mode = successful(
      convert_value(MemberKind::Attribute, 0x0201, 0x001C, Operation::Write,
                    NativeValue::unsigned_integer(4)),
      "thermostat mode");
  require(mode.type == ElementType::U8 && mode.unsigned_value == 4,
          "thermostat mode lost enum8 width");

  const auto light = successful(
      convert_value(MemberKind::Attribute, 0x0006, 0x0000, Operation::Read,
                    NativeValue::boolean(false)),
      "OnOff attribute");
  require(light.type == ElementType::Boolean && !light.boolean_value,
          "OnOff attribute lost false");

  const auto command = successful(
      convert_value(MemberKind::Command, 0x0006, 0x0001, Operation::Invoke,
                    NativeValue::empty_structure()),
      "On command");
  require(command.type == ElementType::Structure && command.children.empty(),
          "On command did not retain an empty structure");
}

void descriptor_recipes() {
  const auto device_types = successful(
      convert_value(MemberKind::Attribute, 0x001D, 0x0000, Operation::Read,
                    NativeValue::device_type_list({DeviceType{0x0100, 2}})),
      "DeviceTypeList");
  require(device_types.type == ElementType::Array && device_types.children.size() == 1,
          "DeviceTypeList did not retain one entry");
  const auto &device = device_types.children.front();
  require(device.type == ElementType::Structure && device.children.size() == 2,
          "DeviceTypeList entry shape changed");
  require(device.children[0].tag.kind == TagKind::Context && device.children[0].tag.id == 0 &&
              device.children[0].type == ElementType::U32 &&
              device.children[0].unsigned_value == 0x0100,
          "DeviceTypeList identifier changed");
  require(device.children[1].tag.kind == TagKind::Context && device.children[1].tag.id == 1 &&
              device.children[1].type == ElementType::U16 &&
              device.children[1].unsigned_value == 2,
          "DeviceTypeList revision changed");

  const auto servers = successful(
      convert_value(MemberKind::Attribute, 0x001D, 0x0001, Operation::Read,
                    NativeValue::identifier_list({0x0006, 0x0402})),
      "ServerList");
  require(servers.children.size() == 2 && servers.children[0].type == ElementType::U32 &&
              servers.children[1].unsigned_value == 0x0402,
          "ServerList identifiers changed");

  const auto clients = successful(
      convert_value(MemberKind::Attribute, 0x001D, 0x0002, Operation::Read,
                    NativeValue::identifier_list({0x0006})),
      "ClientList");
  require(clients.children.size() == 1 && clients.children[0].type == ElementType::U32,
          "ClientList identifiers changed");

  const auto parts = successful(
      convert_value(MemberKind::Attribute, 0x001D, 0x0003, Operation::Read,
                    NativeValue::identifier_list({1, 2})),
      "PartsList");
  require(parts.children.size() == 2 && parts.children[0].type == ElementType::U16 &&
              parts.children[1].unsigned_value == 2,
          "PartsList endpoint width changed");

  const auto reachable = successful(
      convert_value(MemberKind::Event, 0x0039, 0x0003, Operation::Read,
                    NativeValue::reachable(true)),
      "ReachableChanged event");
  require(reachable.type == ElementType::Structure && reachable.children.size() == 1 &&
              reachable.children[0].tag.kind == TagKind::Context &&
              reachable.children[0].tag.id == 0 && reachable.children[0].boolean_value,
          "ReachableChanged event shape changed");

  const auto reachable_attribute = successful(
      convert_value(MemberKind::Attribute, 0x0039, 0x0011, Operation::Subscribe,
                    NativeValue::boolean(true)),
      "Reachable attribute");
  require(reachable_attribute.type == ElementType::Boolean,
          "Reachable attribute did not retain Boolean type");
}

void rejected_values() {
  for (const std::uint32_t cluster : {0U, 0x7FFFU, 0x0001FC00U, 0x0001FFFEU,
                                      0xFFF1FC05U, 0xFFF4FFFEU}) {
    const auto value = successful(
        convert_value(MemberKind::Attribute, 0x001D, 1, Operation::Read,
                      NativeValue::identifier_list({cluster})),
        "SDK cluster identifier");
    require(value.children.size() == 1 && value.children[0].unsigned_value == cluster,
            "SDK cluster identifier changed during conversion");
    require(validate_element(MemberKind::Attribute, 0x001D, 1, Operation::Read, value) ==
                ConversionError::None,
            "valid SDK cluster element rejected");
  }
  for (const std::uint32_t cluster : {0x8000U, 0xFC00U, 0xFFFFU, 0x10000U,
                                      0x1FBFFU, 0x1FFFFU, 0xFFF50000U,
                                      0xFFF5FC00U, 0xFFFFFFFFU}) {
    require(convert_value(MemberKind::Attribute, 0x001D, 1, Operation::Read,
                          NativeValue::identifier_list({cluster})).error ==
                ConversionError::InvalidValue,
            "reserved SDK cluster identifier admitted");
  }
  require(convert_value(MemberKind::Attribute, 0x0006, 0x0000, Operation::Write,
                        NativeValue::boolean(true))
              .error == ConversionError::NotWritable,
          "read-only OnOff attribute admitted a write");

  require(convert_value(MemberKind::Attribute, 0x0201, 0x0000, Operation::Read,
                        NativeValue::signed_integer(32768))
              .error == ConversionError::InvalidValue,
          "out-of-range i16 was admitted");

  require(convert_value(MemberKind::Attribute, 0x0201, 0x001C, Operation::Write,
                        NativeValue::unsigned_integer(256))
              .error == ConversionError::InvalidValue,
          "out-of-range enum8 was admitted");

  require(convert_value(MemberKind::Attribute, 0x001D, 0x0001, Operation::Read,
                        NativeValue::identifier_list({0x8000}))
              .error == ConversionError::InvalidValue,
          "reserved cluster identifier was admitted");

  require(convert_value(MemberKind::Attribute, 0x001D, 0x0003, Operation::Read,
                        NativeValue::identifier_list({0xFFFF}))
              .error == ConversionError::InvalidValue,
          "reserved endpoint identifier was admitted");

  require(convert_value(MemberKind::Attribute, 0x0006, 0xFFFF, Operation::Read,
                        NativeValue::boolean(true))
              .error == ConversionError::UnsupportedSchema,
          "unknown descriptor was converted generically");

  require(convert_value(MemberKind::Event, 0x0039, 0x0003, Operation::Invoke,
                        NativeValue::reachable(true))
              .error == ConversionError::UnsupportedOperation,
          "event descriptor admitted an invoke");

  std::vector<std::uint32_t> oversized(1024, 0x0006);
  require(convert_value(MemberKind::Attribute, 0x001D, 0x0001, Operation::Read,
                        NativeValue::identifier_list(std::move(oversized)))
              .error == ConversionError::InvalidValue,
          "1024 children exceeded the aggregate TLV node limit without failure");
}

Element field(std::uint8_t tag, ElementType type, std::uint64_t value = 0) {
  Element element;
  element.tag = {TagKind::Context, tag};
  element.type = type;
  element.unsigned_value = value;
  return element;
}

void commissioning_descriptors() {
  Element subject;
  subject.type = ElementType::U64;
  subject.unsigned_value = 2;

  Element subjects = field(3, ElementType::Array);
  subjects.children.push_back(subject);
  Element targets = field(4, ElementType::Null);

  Element entry;
  entry.type = ElementType::Structure;
  entry.children = {field(1, ElementType::U8, 5),
                    field(2, ElementType::U8, 2), subjects, targets};
  Element acl;
  acl.type = ElementType::Array;
  acl.children.push_back(entry);

  require(validate_element(MemberKind::Attribute, 0x001F, 0x0000,
                           Operation::Write, acl) == ConversionError::None,
          "typed CASE ACL entry was rejected");

  Element empty_target;
  empty_target.type = ElementType::Structure;
  empty_target.children = {field(0, ElementType::Null),
                           field(1, ElementType::Null),
                           field(2, ElementType::Null)};
  acl.children[0].children[3].type = ElementType::Array;
  acl.children[0].children[3].children = {empty_target};
  require(validate_element(MemberKind::Attribute, 0x001F, 0x0000,
                           Operation::Write, acl) ==
              ConversionError::InvalidValue,
          "an ACL target without a selector was admitted");

  Element conflicting_target = empty_target;
  conflicting_target.children[1] = field(1, ElementType::U16, 1);
  conflicting_target.children[2] = field(2, ElementType::U32, 0x0100);
  acl.children[0].children[3].children = {conflicting_target};
  require(validate_element(MemberKind::Attribute, 0x001F, 0x0000,
                           Operation::Write, acl) ==
              ConversionError::InvalidValue,
          "an ACL target combined endpoint and device type");

  acl.children[0].children[3].type = ElementType::Null;
  acl.children[0].children[3].children.clear();
  acl.children[0].children[1].unsigned_value = 1;
  require(validate_element(MemberKind::Attribute, 0x001F, 0x0000,
                           Operation::Write, acl) ==
              ConversionError::InvalidValue,
          "PASE was admitted as operational ACL authority");

  const auto window = successful(
      convert_value(MemberKind::Attribute, 0x003C, 0x0000,
                    Operation::Read, NativeValue::unsigned_integer(1)),
      "commissioning window status");
  require(window.type == ElementType::U8 && window.unsigned_value == 1,
          "commissioning window status lost enum8 width");

  const auto fabric = successful(
      convert_value(MemberKind::Attribute, 0x003C, 0x0001,
                    Operation::Read, NativeValue::unsigned_integer(254)),
      "commissioning admin fabric");
  require(fabric.type == ElementType::U8 && fabric.unsigned_value == 254,
          "commissioning admin fabric lost fabric-index bounds");

  require(convert_value(MemberKind::Attribute, 0x003C, 0x0002,
                        Operation::Read, NativeValue::unsigned_integer(0xFFFF))
              .error == ConversionError::InvalidValue,
          "invalid commissioning admin vendor was admitted");
}

} // namespace

int main() {
  scalar_recipes();
  descriptor_recipes();
  rejected_values();
  commissioning_descriptors();
  std::cout << "WMA-P01 native descriptor and value conversion passed\n";
  return 0;
}
