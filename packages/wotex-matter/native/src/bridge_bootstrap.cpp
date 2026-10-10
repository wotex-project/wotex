#include "wotex_matter/bridge_bootstrap.hpp"
#include "wotex_matter/bridge_private_file.hpp"
#include "wotex_matter/bridge_commissioning_input.hpp"
#include <crypto/CHIPCryptoPAL.h>
#include <new>

namespace wotex::matter {
BootstrapLoad LoadBootstrap(std::string_view path,
                            std::unique_ptr<BridgeBootstrap> &result) noexcept {
  using R = BootstrapLoad;
  try {
    std::unique_ptr<BridgePrivateFile> master;
    const auto loaded = BridgePrivateFile::Load(path, 65'536, master);
    if (loaded != BridgePrivateFile::Result::Loaded)
      return loaded == BridgePrivateFile::Result::NoMemory ? R::NoMemory : R::File;
    auto owned = std::make_unique<BridgeBootstrap>();
    const auto decoded = DecodeBridgeConfiguration(
        std::string_view(reinterpret_cast<const char *>(master->data()), master->size()),
        owned->configuration);
    if (decoded != BridgeConfigurationDecode::Decoded)
      return decoded == BridgeConfigurationDecode::NoMemory ? R::NoMemory : R::Configuration;
    master->Clear();
    const auto &configuration = *owned->configuration;
    std::unique_ptr<BridgePrivateFile> dac, pai, declaration, key, commissioning;
    const struct Input {
      const std::string *path;
      std::size_t maximum;
      std::unique_ptr<BridgePrivateFile> *owner;
    } inputs[] = {{&configuration.dac_path, SdkBridgeCredentials::kMaximumCertificateBytes, &dac},
                  {&configuration.pai_path, SdkBridgeCredentials::kMaximumCertificateBytes, &pai},
                  {&configuration.declaration_path, SdkBridgeCredentials::kMaximumDeclarationBytes,
                   &declaration},
                  {&configuration.key_path, chip::Crypto::P256SerializedKeypair::Capacity(), &key},
                  {&configuration.commissioning_path, 51, &commissioning}};
    for (const auto &input : inputs) {
      const auto status = BridgePrivateFile::Load(*input.path, input.maximum, *input.owner);
      if (status != BridgePrivateFile::Result::Loaded)
        return status == BridgePrivateFile::Result::NoMemory ? R::NoMemory : R::File;
    }
    BridgeCommissioningInput parsed;
    if (key->size() != chip::Crypto::P256SerializedKeypair::Capacity() ||
        parsed.Decode(std::string_view(reinterpret_cast<const char *>(commissioning->data()),
                                       commissioning->size())) !=
            BridgeCommissioningInput::Result::Decoded)
      return R::Credentials;
    BridgeAttestationMaterial attestation{chip::ByteSpan(dac->data(), dac->size()),
                                          chip::ByteSpan(pai->data(), pai->size()),
                                          chip::ByteSpan(declaration->data(), declaration->size()),
                                          chip::ByteSpan(key->data(), key->size())};
    BridgeCommissioningMaterial setup{parsed.passcode(), parsed.discriminator(),
                                      parsed.iterations(),
                                      chip::ByteSpan(parsed.salt(), parsed.salt_size())};
    const auto status = SdkBridgeCredentials::Create(configuration.identity.vendor_id,
                                                     configuration.identity.product_id, attestation,
                                                     setup, owned->credentials);
    chip::Crypto::ClearSecretData(reinterpret_cast<std::uint8_t *>(&setup.passcode),
                                  sizeof(setup.passcode));
    parsed.Clear();
    key->Clear();
    commissioning->Clear();
    if (status != CHIP_NO_ERROR)
      return status == CHIP_ERROR_NO_MEMORY ? R::NoMemory : R::Credentials;
    result.swap(owned);
    return R::Loaded;
  } catch (const std::bad_alloc &) {
    return R::NoMemory;
  }
}
} // namespace wotex::matter
