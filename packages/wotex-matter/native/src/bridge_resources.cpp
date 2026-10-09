#include "wotex_matter/bridge_resources.hpp"

#include <app/reporting/ReportSchedulerImpl.h>

namespace wotex::matter {

std::unique_ptr<chip::app::reporting::ReportScheduler> MakeBridgeReportScheduler(
    chip::TimerDelegate &timer) {
  return std::make_unique<chip::app::reporting::ReportSchedulerImpl>(&timer);
}

} // namespace wotex::matter
