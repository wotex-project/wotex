#ifndef WOTEX_THREAD_DATASET_HPP
#define WOTEX_THREAD_DATASET_HPP

#include "protocol.hpp"
#include <openthread/dataset.h>
#include <mbedtls/base64.h>
#include <array>
#include <cstring>

namespace wotex::thread {
class DatasetError final : public std::runtime_error {
 public:
  DatasetError() : std::runtime_error("invalid_dataset") {}
};

inline bool dataset_kind(const Json &parameters, bool includes_dataset) {
  if (!exact_keys(parameters, includes_dataset ? std::set<std::string>{"kind", "dataset"}
                                               : std::set<std::string>{"kind"}) ||
      (parameters.at("kind") != "active" && parameters.at("kind") != "pending")) throw ProtocolError();
  return parameters.at("kind") == "active";
}

inline Json dataset_envelope(const otOperationalDatasetTlvs &tlvs) {
  if (tlvs.mLength > OT_OPERATIONAL_DATASET_MAX_LENGTH) throw DatasetError();
  std::array<unsigned char, 341> encoded {};
  std::size_t length = 0;
  if (mbedtls_base64_encode(encoded.data(), encoded.size(), &length, tlvs.mTlvs, tlvs.mLength) != 0) {
    throw DatasetError();
  }
  return {{"type", "bytes"}, {"base64", std::string(reinterpret_cast<const char *>(encoded.data()), length)}};
}

class DatasetValue final {
 public:
  explicit DatasetValue(const Json &envelope) {
    static_assert(OT_OPERATIONAL_DATASET_MAX_LENGTH == 254);
    if (!exact_keys(envelope, {"type", "base64"}) || envelope.at("type") != "bytes" ||
        !envelope.at("base64").is_string()) throw ProtocolError();
    const auto &encoded = envelope.at("base64").get_ref<const std::string &>();
    if (encoded.size() > 340) throw DatasetError();
    std::size_t length = 0;
    if (mbedtls_base64_decode(tlvs.mTlvs, sizeof tlvs.mTlvs, &length,
        reinterpret_cast<const unsigned char *>(encoded.data()), encoded.size()) != 0 || length > 254) {
      throw DatasetError();
    }
    tlvs.mLength = static_cast<std::uint8_t>(length);
    if (dataset_envelope(tlvs).at("base64") != encoded || !profile_widths()) throw DatasetError();
  }

  bool valid(bool active) const {
    if (!otDatasetIsValid(&tlvs, active)) return false;
    if (active && (contains(OT_MESHCOP_TLV_PENDINGTIMESTAMP) || contains(OT_MESHCOP_TLV_DELAYTIMER))) return false;
    otOperationalDataset fields {};
    if (otDatasetParseTlvs(&tlvs, &fields) != OT_ERROR_NONE || fields.mChannel >= 32) return false;
    return (fields.mChannelMask & (std::uint32_t{1} << fields.mChannel)) != 0;
  }

  otOperationalDatasetTlvs tlvs {};
 private:
  bool contains(std::uint8_t type) const {
    for (std::size_t offset = 0; offset < tlvs.mLength; offset += 2 + tlvs.mTlvs[offset + 1]) {
      if (tlvs.mTlvs[offset] == type) return true;
    }
    return false;
  }
  bool profile_widths() const {
    std::array<bool, 256> seen {};
    for (std::size_t offset = 0; offset < tlvs.mLength;) {
      if (offset + 2 > tlvs.mLength) return false;
      const std::uint8_t type = tlvs.mTlvs[offset], size = tlvs.mTlvs[offset + 1];
      if (seen[type] || offset + 2 + size > tlvs.mLength) return false;
      seen[type] = true;
      switch (type) {
        case 0: if (size != 3) return false; break;
        case 1: if (size != 2) return false; break;
        case 2: case 7: case 14: case 51: if (size != 8) return false; break;
        case 4: case 5: if (size != 16) return false; break;
        case 12: if (size != 3 && size != 4) return false; break;
        case 52: if (size != 4) return false; break;
        case 3:
          if (size == 0 || size > 16) return false;
          for (std::size_t index = offset + 2; index < offset + 2 + size; ++index) {
            if (tlvs.mTlvs[index] < 32 || tlvs.mTlvs[index] == 127) return false;
          }
          break;
        default: break;
      }
      offset += 2 + size;
    }
    return true;
  }
};
}  // namespace wotex::thread
#endif
