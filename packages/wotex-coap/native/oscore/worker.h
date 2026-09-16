/* SPDX-License-Identifier: Apache-2.0 */
#ifndef WOTEX_COAP_OSCORE_WORKER_H
#define WOTEX_COAP_OSCORE_WORKER_H

/* Internal same-binary entry. The public executable dispatches this only for
 * its fixed --worker argument after custody has established the process group. */
int wco_worker_main(void);

#endif
