/* SPDX-License-Identifier: Apache-2.0
 * Native-test entry for the generic custody primitive. The production dispatch
 * must select its manifest-verified same executable and is accepted separately.
 */
int wco_custody_main(int argc, char **argv);
int main(int argc, char **argv) { return wco_custody_main(argc, argv); }
