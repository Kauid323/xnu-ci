/*
 * Copyright (c) 2020 Apple Inc. All rights reserved.
 *
 * @APPLE_OSREFERENCE_LICENSE_HEADER_START@
 *
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. The rights granted to you under the License
 * may not be used to create, or enable the creation or redistribution of,
 * unlawful or unlicensed copies of an Apple operating system, or to
 * circumvent, violate, or enable the circumvention or violation of, any
 * terms of an Apple operating system software license agreement.
 *
 * Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 *
 * @APPLE_OSREFERENCE_LICENSE_HEADER_END@
 */
#include <arm/pmap/pmap_internal.h>

/**
 * Placeholder for pmap CS functionality. Eventually all PPL code relating to
 * code signing will be placed into this file.
 *
 * (redwood) 8020 publishes this file as the 33-line placeholder above, and the three
 * symbols below normally come from the closed-source PPL pmap (osfmk/arm/pmap/pmap.c,
 * which is not in the open source drop) or from the PMAP_SUPPORT_PROTOTYPES table that
 * 8796 still had in its pmap.c. A bcm2837 config has neither: it is nos_arm_pmap with
 * no monitor, so nothing defines them and the kernel does not link.
 *
 * They are written the way x86_64/pmap.c writes them -- "unsupported on this
 * architecture, say yes" -- which is the same answer the PPL gives when PMAP_CS is not
 * enabled. pmap_pending_preemption is only an out-of-line symbol when
 * SCHED_PREEMPTION_DISABLE_DEBUG is on; otherwise pmap.h makes it a macro over the
 * inline below, so the definition is unused.
 */

kern_return_t
pmap_cs_allow_invalid(__unused pmap_t pmap)
{
	/* No PMAP_CS: an invalid code directory is not tracked, so nothing to allow. */
	return KERN_SUCCESS;
}

kern_return_t
pmap_cs_fork_prepare(__unused pmap_t old_pmap, __unused pmap_t new_pmap)
{
	/* No PMAP_CS structures to duplicate across fork. */
	return KERN_SUCCESS;
}

#if SCHED_PREEMPTION_DISABLE_DEBUG && (DEBUG || DEVELOPMENT)
bool
pmap_pending_preemption(void)
{
	return _pmap_pending_preemption_real();
}
#endif /* SCHED_PREEMPTION_DISABLE_DEBUG && (DEBUG || DEVELOPMENT) */
