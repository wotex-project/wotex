#ifndef WOTEX_MATTER_RESOURCE_TESTING_HPP
#define WOTEX_MATTER_RESOURCE_TESTING_HPP

#include <memory>
#include <optional>
#include <string>
#include <utility>

namespace wotex::matter::resource_testing {

enum class Object {
  Interaction,
  Commissioning,
  Window,
  Subscription,
  ReadClient,
  WriteClient,
  CommandSender,
  WindowOpener,
  RecoveryTimer,
  Count
};

#ifdef WOTEX_MATTER_RESOURCE_TESTING

void Acquired(Object object);
void Destroyed(Object object);
void Event(const char *name);
std::string SnapshotJson();
std::optional<std::string> ReadBounded(const std::string &path, std::size_t maximum);
bool WriteExclusive(const std::string &path, const std::string &contents);
bool WriteAtomicExclusive(const std::string &path, const std::string &contents);
void ConfigureStartup(std::string directory, std::string stage, std::string action);
bool StartupStage(const char *stage);

class Lifetime final {
 public:
  explicit Lifetime(Object object) : object_(object) { Acquired(object_); }
  ~Lifetime() { Destroyed(object_); }
  Lifetime(const Lifetime &) = delete;
  Lifetime &operator=(const Lifetime &) = delete;

 private:
  Object object_;
};

template <typename T, Object object>
struct Deleter {
  void operator()(T *value) const {
    delete value;
    Destroyed(object);
  }
};

template <typename T, Object object>
using Pointer = std::unique_ptr<T, Deleter<T, object>>;

template <typename T, Object object, typename... Args>
Pointer<T, object> Make(Args &&...args) {
  Pointer<T, object> result(new T(std::forward<Args>(args)...));
  Acquired(object);
  return result;
}

#else

inline void Acquired(Object) {}
inline void Destroyed(Object) {}
inline void Event(const char *) {}

template <typename T, Object>
using Pointer = std::unique_ptr<T>;

template <typename T, Object object, typename... Args>
Pointer<T, object> Make(Args &&...args) {
  return std::make_unique<T>(std::forward<Args>(args)...);
}

#endif

} // namespace wotex::matter::resource_testing

#endif
