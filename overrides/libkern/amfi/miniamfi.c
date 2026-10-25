/*
 * Stand-in for the AppleMobileFileIntegrity kext interface.
 *
 * The kernel reaches AMFI through a table of function pointers that the kext
 * registers at load time. That kext is closed, so this file registers a table
 * of its own. No trust cache contains anything, and there is no signature
 * policy behind it; a process holds the entitlements that the signature of
 * its program lists (miniamfi_entitlements.cpp), and a program without a
 * signature holds none.
 *
 * This is the XNU 8020 (iOS 15.3) shape of that table. 8796's amfi_t is larger:
 * it carries a TrustCache sub-table (libTrustCache arrived with iOS 16), an
 * OSEntitlements sub-table with *WithProc queries, and a filled-in
 * coreentitlements_t. 8020's amfi_t is nine function pointers, one of which is
 * the whole CoreEntitlements bundle. Everything below is what 8020 asks for;
 * nothing here is left out on purpose except the trust-cache answers, which do
 * not exist in this kernel at all.
 */

#include <kern/startup.h>
#include <kern/kern_types.h>
#include <libkern/libkern.h>
#include <libkern/amfi/amfi.h>

static void
mini_OSEntitlements_invalidate(__unused void *osentitlements)
{
}

static void *
mini_OSEntitlements_asdict(__unused void *osentitlements)
{
	return NULL;
}

/*
 * 8020 asks this one directly (IOKitBSDInit: IOEntitlementCheck compares the result with
 * amfi->CoreEntitlements.kNoError). CoreEntitlements below is empty, so kNoError is NULL and any
 * non-NULL error means "denied", which is what an entitlement query has to answer here: there is
 * no CoreEntitlements implementation to satisfy it.
 */
static CEError_t
mini_OSEntitlements_query(__unused void *osentitlements, __unused uint8_t cdhash[CS_CDHASH_LEN],
    __unused CEQuery_t query, __unused size_t queryLength)
{
	return (CEError_t)~0ul;
}

static bool
mini_OSEntitlements_get_transmuted(__unused void *osentitlements, const CS_GenericBlob **blob)
{
	*blob = NULL;
	return false;
}

static bool
mini_OSEntitlements_get_xml(__unused void *osentitlements, CS_GenericBlob **blob)
{
	*blob = NULL;
	return false;
}

static bool
mini_get_legacy_profile_exemptions(const uint8_t **profile, size_t *profileLength)
{
	*profile = NULL;
	*profileLength = 0;
	return false;
}

static bool
mini_get_udid(const uint8_t **udid, size_t *udidLength)
{
	*udid = NULL;
	*udidLength = 0;
	return false;
}

static void *
mini_query_context_to_object(__unused CEQueryContext_t ctx)
{
	return NULL;
}

static const amfi_t miniamfi = {
	.OSEntitlements_invalidate = mini_OSEntitlements_invalidate,
	.OSEntitlements_asdict = mini_OSEntitlements_asdict,
	.OSEntitlements_query = mini_OSEntitlements_query,
	.OSEntitlements_get_transmuted = mini_OSEntitlements_get_transmuted,
	.OSEntitlements_get_xml = mini_OSEntitlements_get_xml,
	/*
	 * CoreEntitlements is left zeroed. Only the PPL build of the pmap calls into it
	 * (pmap_cs_enabled() is false here), and a zeroed bundle makes kNoError NULL, which is what
	 * mini_OSEntitlements_query() above relies on.
	 */
	.get_legacy_profile_exemptions = mini_get_legacy_profile_exemptions,
	.get_udid = mini_get_udid,
	.query_context_to_object = mini_query_context_to_object,
};

__startup_func
static void
miniamfi_init(void)
{
	amfi_interface_register(&miniamfi);
}
STARTUP(EARLY_BOOT, STARTUP_RANK_FIRST, miniamfi_init);
