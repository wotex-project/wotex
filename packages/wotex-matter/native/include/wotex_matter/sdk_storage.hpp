#ifndef WOTEX_MATTER_SDK_STORAGE_HPP
#define WOTEX_MATTER_SDK_STORAGE_HPP

#include <credentials/PersistentStorageOpCertStore.h>
#include <crypto/PersistentStorageOperationalKeystore.h>
#include <lib/core/CHIPError.h>

#include <lib/core/CHIPPersistentStorageDelegate.h>

namespace wotex::matter {

class SdkStorageBinding final {
 public:
  SdkStorageBinding() = default;
  ~SdkStorageBinding();
  SdkStorageBinding(const SdkStorageBinding &) = delete;
  SdkStorageBinding &operator=(const SdkStorageBinding &) = delete;

  CHIP_ERROR Init(chip::PersistentStorageDelegate &storage);
  void Finish();

  chip::PersistentStorageOperationalKeystore &operational_keystore();
  chip::Credentials::PersistentStorageOpCertStore &certificate_store();

 private:
  chip::PersistentStorageOperationalKeystore operational_keystore_;
  chip::Credentials::PersistentStorageOpCertStore certificate_store_;
  bool initialized_{false};
};

} // namespace wotex::matter

#endif
