/*
 * redwood_mpss.c -- deliberately not the upstream driver.  overrides/ wins
 * over hackios/xnu/files, so this is what gets compiled.
 *
 * Upstream's version is 224 KB that brings up the modem's DSP on the phone it
 * was written for (a Qualcomm MPSS: qrtr, the NAS service, the ADSP).  cactus
 * has a MediaTek modem that code cannot talk to, and upstream's own entry
 * point is inert off their hardware anyway: it returns at once unless
 * "modem=1" or "modem_step=N" is on the command line *and* the SoC base is
 * theirs.  So on this device the driver's entire effect is to be called and
 * return -- which is what these three functions do, without the 224 KB and
 * without dragging in the nas/qrtr files it would otherwise need.
 *
 * The three have to exist to link: bsd/dev/redwood_input.c calls
 * redwood_mpss_init() while the input driver starts, and
 * osfmk/arm64/loader_return.c calls the other two on the way back to the
 * loader.
 */
#include <sys/types.h>

void redwood_mpss_init(void);
void redwood_mpss_stop(void);
void redwood_mpss_quiesce(void);

void
redwood_mpss_init(void)
{
}

void
redwood_mpss_stop(void)
{
}

void
redwood_mpss_quiesce(void)
{
}
