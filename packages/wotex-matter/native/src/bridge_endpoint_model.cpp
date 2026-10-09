#include "wotex_matter/bridge_endpoint_model.hpp"

#include <app/util/attribute-storage.h>

namespace wotex::matter {
namespace {

using namespace chip;

DECLARE_DYNAMIC_ATTRIBUTE_LIST_BEGIN(descriptor)
DECLARE_DYNAMIC_ATTRIBUTE(0, ARRAY, 254, 0), DECLARE_DYNAMIC_ATTRIBUTE(1, ARRAY, 254, 0),
    DECLARE_DYNAMIC_ATTRIBUTE(2, ARRAY, 254, 0), DECLARE_DYNAMIC_ATTRIBUTE(3, ARRAY, 254, 0),
    DECLARE_DYNAMIC_ATTRIBUTE(0xFFFC, BITMAP32, 4, 0), DECLARE_DYNAMIC_ATTRIBUTE_LIST_END();
DECLARE_DYNAMIC_ATTRIBUTE_LIST_BEGIN(identify)
DECLARE_DYNAMIC_ATTRIBUTE(0, INT16U, 2, ZAP_ATTRIBUTE_MASK(WRITABLE)),
    DECLARE_DYNAMIC_ATTRIBUTE(1, ENUM8, 1, 0), DECLARE_DYNAMIC_ATTRIBUTE(0xFFFC, BITMAP32, 4, 0),
    DECLARE_DYNAMIC_ATTRIBUTE_LIST_END();
DECLARE_DYNAMIC_ATTRIBUTE_LIST_BEGIN(groups)
DECLARE_DYNAMIC_ATTRIBUTE(0, BITMAP8, 1, 0), DECLARE_DYNAMIC_ATTRIBUTE(0xFFFC, BITMAP32, 4, 0),
    DECLARE_DYNAMIC_ATTRIBUTE_LIST_END();
DECLARE_DYNAMIC_ATTRIBUTE_LIST_BEGIN(onoff)
DECLARE_DYNAMIC_ATTRIBUTE(0, BOOLEAN, 1, 0), DECLARE_DYNAMIC_ATTRIBUTE(0x4000, BOOLEAN, 1, 0),
    DECLARE_DYNAMIC_ATTRIBUTE(0x4001, INT16U, 2, ZAP_ATTRIBUTE_MASK(WRITABLE)),
    DECLARE_DYNAMIC_ATTRIBUTE(0x4002, INT16U, 2, ZAP_ATTRIBUTE_MASK(WRITABLE)),
    DECLARE_DYNAMIC_ATTRIBUTE(0x4003, ENUM8, 1,
                              ZAP_ATTRIBUTE_MASK(WRITABLE) | ZAP_ATTRIBUTE_MASK(NULLABLE)),
    DECLARE_DYNAMIC_ATTRIBUTE(0xFFFC, BITMAP32, 4, 0), DECLARE_DYNAMIC_ATTRIBUTE_LIST_END();
DECLARE_DYNAMIC_ATTRIBUTE_LIST_BEGIN(scenes)
DECLARE_DYNAMIC_ATTRIBUTE(1, INT16U, 2, 0), DECLARE_DYNAMIC_ATTRIBUTE(2, ARRAY, 254, 0),
    DECLARE_DYNAMIC_ATTRIBUTE(0xFFFC, BITMAP32, 4, 0), DECLARE_DYNAMIC_ATTRIBUTE_LIST_END();
DECLARE_DYNAMIC_ATTRIBUTE_LIST_BEGIN(temperature)
DECLARE_DYNAMIC_ATTRIBUTE(0, INT16S, 2, ZAP_ATTRIBUTE_MASK(NULLABLE)),
    DECLARE_DYNAMIC_ATTRIBUTE(1, INT16S, 2, ZAP_ATTRIBUTE_MASK(NULLABLE)),
    DECLARE_DYNAMIC_ATTRIBUTE(2, INT16S, 2, ZAP_ATTRIBUTE_MASK(NULLABLE)),
    DECLARE_DYNAMIC_ATTRIBUTE(0xFFFC, BITMAP32, 4, 0), DECLARE_DYNAMIC_ATTRIBUTE_LIST_END();
constexpr CommandId identify_light[] = {0, 64, kInvalidCommandId};
constexpr CommandId identify_sensor[] = {0, kInvalidCommandId};
constexpr CommandId groups_in[] = {0, 1, 2, 3, 4, 5, kInvalidCommandId};
constexpr CommandId groups_out[] = {0, 1, 2, 3, kInvalidCommandId};
constexpr CommandId onoff_in[] = {0, 1, 2, 64, 65, 66, kInvalidCommandId};
constexpr CommandId scenes_in[] = {0, 1, 2, 3, 4, 5, 6, 64, kInvalidCommandId};
constexpr CommandId scenes_out[] = {0, 1, 2, 3, 4, 6, 64, kInvalidCommandId};
DECLARE_DYNAMIC_CLUSTER_LIST_BEGIN(light_clusters)
DECLARE_DYNAMIC_CLUSTER(0x001D, descriptor, ZAP_CLUSTER_MASK(SERVER), nullptr, nullptr),
    DECLARE_DYNAMIC_CLUSTER(0x0003, identify, ZAP_CLUSTER_MASK(SERVER), identify_light, nullptr),
    DECLARE_DYNAMIC_CLUSTER(0x0004, groups, ZAP_CLUSTER_MASK(SERVER), groups_in, groups_out),
    DECLARE_DYNAMIC_CLUSTER(0x0006, onoff, ZAP_CLUSTER_MASK(SERVER), onoff_in, nullptr),
    DECLARE_DYNAMIC_CLUSTER(0x0062, scenes, ZAP_CLUSTER_MASK(SERVER), scenes_in, scenes_out),
    DECLARE_DYNAMIC_CLUSTER_LIST_END;
DECLARE_DYNAMIC_ENDPOINT(light, light_clusters);
DECLARE_DYNAMIC_CLUSTER_LIST_BEGIN(sensor_clusters)
DECLARE_DYNAMIC_CLUSTER(0x001D, descriptor, ZAP_CLUSTER_MASK(SERVER), nullptr, nullptr),
    DECLARE_DYNAMIC_CLUSTER(0x0003, identify, ZAP_CLUSTER_MASK(SERVER), identify_sensor, nullptr),
    DECLARE_DYNAMIC_CLUSTER(0x0402, temperature, ZAP_CLUSTER_MASK(SERVER), nullptr, nullptr),
    DECLARE_DYNAMIC_CLUSTER_LIST_END;
DECLARE_DYNAMIC_ENDPOINT(sensor, sensor_clusters);
constexpr EmberAfDeviceType light_types[] = {{0x0013, 3}, {0x0100, 3}};
constexpr EmberAfDeviceType sensor_types[] = {{0x0013, 3}, {0x0302, 3}};

} // namespace

const EmberAfEndpointType &BridgeEndpointModel(BridgedDeviceType type) {
  return type == BridgedDeviceType::OnOffLight ? light : sensor;
}

chip::Span<const EmberAfDeviceType> BridgeEndpointDeviceTypes(BridgedDeviceType type) {
  return type == BridgedDeviceType::OnOffLight ? chip::Span<const EmberAfDeviceType>(light_types)
                                               : chip::Span<const EmberAfDeviceType>(sensor_types);
}

} // namespace wotex::matter
