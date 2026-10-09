#ifndef WOTEX_MATTER_BRIDGE_RESOURCES_HPP
#define WOTEX_MATTER_BRIDGE_RESOURCES_HPP

#include <app/reporting/ReportScheduler.h>
#include <lib/support/TimerDelegate.h>

#include <memory>

namespace wotex::matter {

// Internal SDK resource factory. The serialized server owner holds the
// scheduler; its explicitly supplied timer delegate outlives it.
std::unique_ptr<chip::app::reporting::ReportScheduler> MakeBridgeReportScheduler(
    chip::TimerDelegate &timer);

} // namespace wotex::matter

#endif
