#include "wotex_matter/sdk_storage.hpp"

namespace wotex::matter {

CHIP_ERROR SdkStorageBinding::Init(DurableStorage &storage) {
  if (initialized_) {
    return CHIP_ERROR_INCORRECT_STATE;
  }

  CHIP_ERROR error = operational_keystore_.Init(&storage);
  if (error != CHIP_NO_ERROR) {
    return error;
  }

  error = certificate_store_.Init(&storage);
  if (error != CHIP_NO_ERROR) {
    operational_keystore_.Finish();
    return error;
  }

  initialized_ = true;
  return CHIP_NO_ERROR;
}

void SdkStorageBinding::Finish() {
  if (!initialized_) {
    return;
  }

  certificate_store_.Finish();
  operational_keystore_.Finish();
  initialized_ = false;
}

chip::PersistentStorageOperationalKeystore &
SdkStorageBinding::operational_keystore() {
  return operational_keystore_;
}

chip::Credentials::PersistentStorageOpCertStore &
SdkStorageBinding::certificate_store() {
  return certificate_store_;
}

} // namespace wotex::matter
