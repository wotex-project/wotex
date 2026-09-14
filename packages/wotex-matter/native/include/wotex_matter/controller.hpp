#ifndef WOTEX_MATTER_CONTROLLER_HPP
#define WOTEX_MATTER_CONTROLLER_HPP

#include "wotex_matter/protocol.hpp"

#include <memory>

namespace wotex::matter {

class SdkControllerBackend final : public ControllerBackend {
 public:
  SdkControllerBackend();
  ~SdkControllerBackend() override;

  SdkControllerBackend(const SdkControllerBackend &) = delete;
  SdkControllerBackend &operator=(const SdkControllerBackend &) = delete;

  BackendResult Open(const NativeOpenOptions &options) override;
  void Close() override;
  bool IsOpen() const override;

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

} // namespace wotex::matter

#endif
